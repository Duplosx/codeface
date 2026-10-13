"""Regression tests for forward windows and incremental range analysis."""
import os
import sqlite3
import subprocess
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import codeface.logger
from codeface.cli import get_parser
from codeface.dbmanager import DBManager
from codeface.incremental import (completion_signature, is_complete,
                                  mark_complete, invalidate_completion)
from codeface.project import project_analyse
from codeface.util import BatchJobPool, generate_analysis_windows, get_analysis_windows


class MemoryDB(DBManager):
    """Run the real timeline SQL against an isolated relational fixture."""
    def __init__(self):
        self.con = sqlite3.connect(':memory:')
        self.con.executescript('''
            PRAGMA foreign_keys=ON;
            CREATE TABLE project (id INTEGER PRIMARY KEY AUTOINCREMENT,
                                  name TEXT, analysisMethod TEXT);
            CREATE TABLE release_timeline (id INTEGER PRIMARY KEY AUTOINCREMENT,
                type TEXT, tag TEXT, projectId INTEGER REFERENCES project(id) ON DELETE CASCADE);
            CREATE TABLE release_range (id INTEGER PRIMARY KEY AUTOINCREMENT,
                releaseStartId INTEGER REFERENCES release_timeline(id) ON DELETE CASCADE,
                releaseEndId INTEGER REFERENCES release_timeline(id) ON DELETE CASCADE,
                projectId INTEGER REFERENCES project(id) ON DELETE CASCADE,
                releaseRCStartId INTEGER REFERENCES release_timeline(id) ON DELETE SET NULL);
            CREATE TABLE `commit` (id INTEGER PRIMARY KEY AUTOINCREMENT,
                releaseRangeId INTEGER REFERENCES release_range(id) ON DELETE SET NULL);
        ''')

    def doExec(self, stmt, args=None):
        cursor = self.con.execute(stmt.replace('%s', '?'), args or ())
        self.rows = cursor.fetchall()
        self.cur = SimpleNamespace(rowcount=len(self.rows))

    def doFetchAll(self):
        return self.rows


class TestForwardWindows(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        self.git('init', '-q')
        self.git('config', 'user.name', 'Window Test')
        self.git('config', 'user.email', 'window@example.invalid')
        self.gitdir = str(self.repo / '.git')

    def git(self, *args, env=None):
        return subprocess.check_output(['git', '-C', str(self.repo)] + list(args),
                                       env=env, text=True).strip()

    def commit(self, day):
        date = (datetime(2020, 1, 1, tzinfo=timezone.utc) + timedelta(days=day)).isoformat()
        env = dict(os.environ, GIT_AUTHOR_DATE=date, GIT_COMMITTER_DATE=date)
        self.git('commit', '--allow-empty', '-qm', 'day {}'.format(day), env=env)
        return self.git('rev-parse', 'HEAD')

    def test_forward_boundaries_and_growing_tail(self):
        commits = [self.commit(day) for day in (0, 45, 90, 135, 180, 225)]
        revs, rcs, dates = generate_analysis_windows(self.gitdir, 3)
        self.assertEqual(revs, [commits[i] for i in (0, 2, 4, 5)])
        self.assertEqual(rcs, [None] * 4)
        self.assertEqual(dates[0], '2020-01-01')
        new_tail = self.commit(250)
        self.assertEqual(generate_analysis_windows(self.gitdir, 3)[0], revs[:-1] + [new_tail])
        latest = self.commit(310)
        self.assertEqual(generate_analysis_windows(self.gitdir, 3)[0], revs[:-1] + [new_tail, latest])

    def test_empty_windows_and_short_history(self):
        first, second = self.commit(0), self.commit(10)
        self.assertEqual(generate_analysis_windows(self.gitdir, 3)[0], [first, second])
        last = self.commit(300)
        self.assertEqual(generate_analysis_windows(self.gitdir, 3)[0], [first, second, last])

    def test_invalid_windows_and_single_commit(self):
        self.commit(0)
        for size in (0, -3, 3):
            with self.assertRaises(ValueError):
                generate_analysis_windows(self.gitdir, size)
        for count in (0, -2, 1.5):
            with self.assertRaises(ValueError):
                get_analysis_windows({'numWindows': count})

    def test_date_range_signature_detects_merged_historical_commits(self):
        first, last = self.commit(0), self.commit(90)
        branch = self.git('branch', '--show-current')
        args = ({'project': 'test'}, self.gitdir, 1, 2, (first, last, None), True)
        before = completion_signature(*args)
        self.git('checkout', '-qb', 'historical', first)
        self.commit(45)
        self.git('checkout', '-q', branch)
        self.git('merge', '--no-ff', '-qm', 'merge historical commits', 'historical')
        self.assertNotEqual(completion_signature(*args), before)

    def test_completion_invalidates_on_settings_database_and_missing_cache(self):
        first, last = self.commit(0), self.commit(100)
        conf = {'project': 'test', 'revisions': [first, last], 'all_files': False}
        args = (self.gitdir, 1, 2, (first, last, None), True)
        signature = completion_signature(conf, *args)
        cache = self.root / 'vcs_analysis.db'
        cache.touch()
        mark_complete(str(self.root), signature)
        self.assertTrue(is_complete(str(self.root), signature))
        conf['revisions'].append('later')
        self.assertEqual(completion_signature(conf, *args), signature)
        conf['all_files'] = True
        self.assertNotEqual(completion_signature(conf, *args), signature)
        self.assertNotEqual(completion_signature(conf, self.gitdir, 9, 2,
                                                (first, last, None), True), signature)
        cache.unlink()
        self.assertFalse(is_complete(str(self.root), signature))
        cache.touch()
        invalidate_completion(str(self.root))
        self.assertFalse(is_complete(str(self.root), signature))

    def test_incremental_pipeline_skips_and_retries_changed_ranges(self):
        commits = [self.commit(day) for day in (0, 90, 180, 225)]
        db = MemoryDB()
        self.addCleanup(db.con.close)
        analysed = []
        complexity = []
        fail_complexity = [False]

        class Config(dict):
            def write(self):
                pass
            def get_conf_file_loc(self):
                return 'unused.conf'

        def config(*args):
            return Config(project='test', repo='repo', tagging='tag', revisions=[],
                          rcs=[], windowSize=3, numWindows=-1)

        def analyse(conf, start, end, rc, outdir, *args):
            analysed.append((start, end))
            Path(outdir).mkdir(parents=True, exist_ok=True)
            (Path(outdir) / 'vcs_analysis.db').touch()

        def external(cmd, **kwargs):
            if str(cmd[0]).endswith('complexity.r'):
                complexity.append(cmd[-1])
                if fail_complexity[0]:
                    raise RuntimeError('complexity failed')

        def run(**kwargs):
            project_analyse(str(self.root / 'results'), str(self.root), 'global.conf',
                            'project.conf', True, 'info', None, False, False,
                            1, 'default', False, incremental=True, **kwargs)

        with patch('codeface.project.Configuration.load', side_effect=config), \
             patch('codeface.project.DBManager', return_value=db), \
             patch('codeface.project.doProjectAnalysis', side_effect=analyse), \
             patch('codeface.project.dispatch_ts_analysis') as summaries, \
             patch('codeface.project.execute_command', side_effect=external):
            run()
            self.assertEqual(analysed, list(zip(commits, commits[1:])))
            first_ids = db.get_release_ranges(db.getProjectID('test', 'tag'))
            run()
            self.assertEqual(len(analysed), 3)
            self.assertEqual(len(complexity), 3)
            self.assertEqual(summaries.call_count, 2)
            new_tail = self.commit(250)
            fail_complexity[0] = True
            with self.assertRaises(RuntimeError):
                run()
            self.assertEqual(analysed[-1], (commits[-2], new_tail))
            self.assertEqual(len(analysed), 4)
            new_ids = db.get_release_ranges(db.getProjectID('test', 'tag'))
            self.assertEqual(first_ids[:-1], new_ids[:-1])
            self.assertNotEqual(first_ids[-1], new_ids[-1])
            fail_complexity[0] = False
            run()
            self.assertEqual(len(analysed), 5)
            run()
            self.assertEqual(len(analysed), 5)
            run(all_files=True)
            self.assertEqual(len(analysed), 8)


class TestTimelineUpdates(unittest.TestCase):
    def setUp(self):
        self.db = MemoryDB()
        self.addCleanup(self.db.con.close)

    def update(self, revs, allow=True):
        return self.db.update_release_timeline('test', 'tag', revs, [None] * len(revs),
                                               allow_tail_change=allow)

    def test_replacing_tail_preserves_earlier_ranges_and_deletes_old_commits(self):
        ids = self.update(['a', 'b', 'c'])
        pid = self.db.getProjectID('test', 'tag')
        for rid in ids:
            self.db.doExecCommit('INSERT INTO `commit` (releaseRangeId) VALUES (%s)', (rid,))
        new = self.update(['a', 'b', 'd', 'e'])
        self.assertEqual(self.db.getProjectID('test', 'tag'), pid)
        self.assertEqual(self.db.get_release_ranges(pid), ids[:1] + new)
        self.db.doExec('SELECT releaseRangeId FROM `commit`')
        self.assertEqual(self.db.doFetchAll(), [(ids[0],)])
        self.assertEqual(self.update(['a', 'b', 'd', 'e']), [])

    def test_non_tail_change_or_explicit_revisions_recreates_project(self):
        self.update(['a', 'b', 'c'])
        pid = self.db.getProjectID('test', 'tag')
        self.update(['a', 'x', 'c'])
        next_pid = self.db.getProjectID('test', 'tag')
        self.assertNotEqual(pid, next_pid)
        self.update(['a', 'x', 'd'], allow=False)
        self.assertNotEqual(next_pid, self.db.getProjectID('test', 'tag'))


class TestWindowCLIAndPool(unittest.TestCase):
    def test_incremental_flag_is_opt_in(self):
        args = ['run', '-p', 'project.conf', 'results', 'repos']
        self.assertFalse(get_parser().parse_args(args).incremental)
        self.assertTrue(get_parser().parse_args(args + ['--incremental']).incremental)

    def test_parallel_jobs_complete_before_return(self):
        with tempfile.TemporaryDirectory() as directory:
            pool = BatchJobPool(2)
            for index in range(3):
                pool.add(os.mkdir, (os.path.join(directory, str(index)),))
            pool.join()
            self.assertEqual(sorted(os.listdir(directory)), ['0', '1', '2'])
