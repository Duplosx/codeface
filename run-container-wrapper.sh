#!/bin/bash

PATH_ROOT="/scratch/codeface"

# open virtualenv
source "${PATH_ROOT}/virtualenv3/bin/activate"


# DEBUG INFORMATION

echo =================================================================
echo % Job Name: ${SLURM_JOB_NAME}
echo % Task ID: ${SLURM_JOB_ID}
echo % Nodelist: ${SLURM_NODELIST}
echo % Time: $(date)
echo =================================================================
echo


# COMMAND EXECUTION

# logging
echo =================================================================
echo "Calling run-container-wrapper.sh with the following arguments:"
echo "$@"
echo =================================================================
echo

# read -t parameter from arguments and create folder on cluster
PARAMETER_T=$(echo $@ | grep -m 1 -Poe " -t .[^[:space:]]*")
TMPDIR=$(echo "${PARAMETER_T}" | cut -c 4-)
mkdir -p ${TMPDIR}
#ls -lah /local/codeface/

# execute all arguments (script with parameters)
"$@" 2>&1

# remove temp folder again
rm -rf ${TMPDIR}

# DEBUG INFORMATION

# print out end-time
echo
echo =================================================================
echo % End Time: $(date)
echo =================================================================
