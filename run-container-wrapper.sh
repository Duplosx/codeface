#!/bin/bash

PATH_ROOT="/scratch/codeface"

## fix problems with Kerberos keys
kdestroy
unset KRB5CCNAME
export HOME=$(mktemp -d --tmpdir=/tmp)

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

# Enqueue a clean-up job (just in case the job fails)
sbatch -Aanywhere -panywhere --cpus-per-task=1 --time=2 --nodelist=${SLURM_NODELIST} \
    /scratch/codeface/container/cleanup_node.bash


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

# execute all arguments (script with parameters)
"$@" 2>&1

# remove temp folder again
rm -rf ${TMPDIR}
if [ -d "${TMPDIR}" ]; then
    echo "Temporary folder '${TMPDIR}' could not be removed!"
else
    echo "Temporary folder '${TMPDIR}' removed successfully."
fi


# DEBUG INFORMATION

# print out end-time
echo
echo =================================================================
echo % End Time: $(date)
echo =================================================================
