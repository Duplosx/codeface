#!/bin/bash

# Source the run configuration
echo "Source config"
source ../run.conf

#cd codeface

# Start the id service
echo "Start id service"
nodejs id_service/id_service.js "${CFCONF}" "info" &
IDSERVICE=$!

# Run codeface with the given parameters
echo "Run codeface"
if [ $1 == "run" ]; then
    codeface -j 1 -l "devinfo" run --recreate -c "${CFCONF}" -p "${CSCONF}" "${RESULTS}" "${REPOS}" > "${LOGS}/codeface_run.log" 2>&1
elif [ $1 == "ml" ]; then
    codeface -j 1 -l "devinfo" ml -c "${CFCONF}" -p "${CSCONF}" "${RESULTS}" "${MAILINGLISTS}" > "${LOGS}/codeface_ml.log" 2>&1
elif [ $1 == "conway" ]; then
    codeface -l "devinfo" conway -c "${CFCONF}" -p "${CSCONF}" "${RESULTS}" "${REPOS}" "${TITAN}" > "${LOGS}/codeface_conway.log" 2>&1
else
    echo "Missing parameter. Use run, ml, or conway."
fi

# Kill the id-service
echo "Kill id service"
kill $IDSERVICE

