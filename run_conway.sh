#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

pushd ${DIR} > /dev/null

    # logging
    echo =================================================================
    echo "Calling codeface  with following arguments:"
    echo "$@"
    echo =================================================================
    echo

    # get parameters from command line
    TMPDIR=$1 # currently ignored
    CASESTUDY=$2
    CFCONF=$3
    CSCONF=$4
    REPOS=$5
    MAILINGLISTS=$6
    RESULTS=$7
    LOGS=$8

    CFDIR="/mnt/codeface"
    CFDATA="/mnt/codeface-data"
    CFEXTRACT="/mnt/codeface-extraction"
    CFGHW="/mnt/GitHubWrapper/build/libs/GitHubWrapper-1.0-SNAPSHOT.jar"
    TITAN="${CFDIR}/titan"

    ## create log folder
    mkdir -p ${LOGS}

    pushd $CFDIR

        ## start ID service
        pushd "id_service"
            echo "### " $(date "+%F %T") "Starting ID service" 2>&1 > "${LOGS}/id_service.log"
            nodejs id_service.js ${CFCONF} "info" 2>&1 >> "${LOGS}/id_service.log" &
            IDSERVICE=$!
        popd

        ## set stack size large enough to prevent C stack overflow errors
        ulimit -s 512000
        ## run codeface analysis with current tagging set
        codeface -j 11 -l "devinfo" run --recreate -c ${CFCONF} -p ${CSCONF} ${RESULTS} ${REPOS} > ${LOGS}/codeface_run.log 2>&1

        # ## run mailing-list analysis (attached to feature/proximity analysis!)
        # codeface -j 11 -l "devinfo" ml -c ${CFCONF} -p ${CSCONF} "${RESULTS}" "${MAILINGLISTS}" > ${LOGS}/codeface_ml.log 2>&1
        # codeface -j 11 -l "devinfo" ml --use-corpus -c ${CFCONF} -p ${CSCONF} "${RESULTS}" "${MAILINGLISTS}" > ${LOGS}/codeface_ml.log 2>&1

        ## run conway analysis (do NOT give -j paramater, it may break the analysis!)
        unset DISPLAY
        codeface -l "devinfo" conway -c ${CFCONF} -p ${CSCONF} "${RESULTS}" ${REPOS} ${TITAN} > ${LOGS}/codeface_conway.log 2>&1

        # ## run GitHubWrapper extraction
        # mkdir -p "${RESULTS}/${CASESTUDY}_issues/"
        # java -Xmx100G -jar "${CFGHW}" \
        #     -dump "${RESULTS}/${CASESTUDY}_issues/issues.json" \
        #     -tokens "${CFDATA}/configurations/tokens.txt" \
        #     -repo "${REPOS}/${CASESTUDY}/" \
        #     -workDir "${REPOS}/" > ${LOGS}/codeface_githubwrapper.log 2>&1

        ## run extraction process for this configuration
        pushd "${CFEXTRACT}" > /dev/null
            # ISSUEPROCESS="${CFEXTRACT}/run-issues.py"
            # python ${ISSUEPROCESS} -c ${CFCONF} -p ${CSCONF} ${RESULTS} > ${LOGS}/codeface_issues.log 2>&1

            ISSUEPROCESS="${CFEXTRACT}/run-jira-issues.py"
            python ${ISSUEPROCESS} -c ${CFCONF} -p ${CSCONF} ${RESULTS} > ${LOGS}/codeface_issues_jira.log 2>&1

            EXTRACTION="${CFEXTRACT}/run-extraction.py"
            python ${EXTRACTION} -c ${CFCONF} -p ${CSCONF} ${RESULTS} > ${LOGS}/codeface_extraction.log 2>&1
            # add parameter '--range' to run extractions also for all ranges
            # add parameter '--implementation' to extract function implementations
            # add parameter '--commit-messages' to extract commit messages

            # MBOXPARSING="${CFEXTRACT}/run-parsing.py"
            # ## Remove already existing log file to be able to append later
            # rm ${LOGS}/codeface_mbox_parsing.log
            # ## MboxParsing without filepath
            # python ${MBOXPARSING} -c ${CFCONF} -p ${CSCONF} ${RESULTS} ${MAILINGLISTS} >> ${LOGS}/codeface_mbox_parsing.log 2>&1
            # ## MboxParsing with filepath
            # python ${MBOXPARSING} -c ${CFCONF} -p ${CSCONF} -f ${RESULTS} ${MAILINGLISTS} >> ${LOGS}/codeface_mbox_parsing.log 2>&1
            # ## MboxParsing file (base name only)
            # python ${MBOXPARSING} -c ${CFCONF} -p ${CSCONF} --file ${RESULTS} ${MAILINGLISTS} >> ${LOGS}/codeface_mbox_parsing.log 2>&1
            # ## MboxParsing file with filepath
            # python ${MBOXPARSING} -c ${CFCONF} -p ${CSCONF} --file -f ${RESULTS} ${MAILINGLISTS} >> ${LOGS}/codeface_mbox_parsing.log 2>&1
        popd

        ## stop ID service
        kill $IDSERVICE

    popd

popd > /dev/null
