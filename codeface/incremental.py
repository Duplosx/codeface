"""Completion records for per-range analysis; global summaries always rerun."""

import hashlib
import json
import os
from tempfile import NamedTemporaryFile

from .util import execute_command


def completion_signature(conf, repo, project_id, range_id, revisions, range_by_date):
    # The growing revision list must not invalidate unchanged earlier windows.
    settings = {key: value for key, value in conf.items()
                if key not in ('revisions', 'rcs', 'numWindows')}
    commits = execute_command(['git', '--git-dir=' + repo, 'rev-parse'] +
                              [rev + '^{commit}' for rev in revisions if rev]).splitlines()
    members = None
    if range_by_date:
        # Date-based analysis searches HEAD, so a later merge can introduce
        # historical commits even when both boundary hashes stay unchanged.
        git_log = ['git', '--git-dir=' + repo, 'log', '--no-merges']
        dates = [execute_command(git_log + ['--format=%ct', '-1', rev]).strip()
                 for rev in commits[:2]]
        members = sorted(execute_command(git_log + [
            '--format=%H', '--since=' + dates[0], '--before=' + dates[1], 'HEAD'
        ]).splitlines())
    data = [1, settings, os.path.realpath(repo), project_id, range_id,
            commits, range_by_date, members]
    return hashlib.sha256(json.dumps(data, sort_keys=True, default=str).encode('utf-8')).hexdigest()


def completion_path(outdir):
    return os.path.join(outdir, '.analysis-complete.json')


def is_complete(outdir, signature):
    if not os.path.isfile(os.path.join(outdir, 'vcs_analysis.db')):
        return False
    try:
        with open(completion_path(outdir)) as record:
            return json.load(record) == signature
    except (OSError, ValueError):
        return False


def invalidate_completion(outdir):
    try:
        os.unlink(completion_path(outdir))
    except FileNotFoundError:
        pass


def mark_complete(outdir, signature):
    with NamedTemporaryFile(mode='w', dir=outdir, delete=False) as record:
        json.dump(signature, record)
    os.replace(record.name, completion_path(outdir))
