#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly CODEFACE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly VENV_DIR="${CODEFACE_DIR}/.venv"
readonly R_VERSION="4.3.3-1.2204.0"
readonly R_PACKAGES=(r-base r-base-core r-base-dev r-recommended)
DB_CONFIGS=()
SKIP_DATABASE=0
PYTHON="${VENV_DIR}/bin/python"
CODEFACE="${VENV_DIR}/bin/codeface"
if [[ ${CODEFACE_SYSTEM_PYTHON:-0} == 1 ]]; then
    PYTHON=python3
    CODEFACE=codeface
fi
id_pid=

usage() {
    cat <<'EOF'
Usage: install/verify_codeface.sh [--db-config FILE ...] [--skip-database]

Without arguments, only codeface.conf is checked.
Repeat --db-config to check one or more local or external database schemas.
The first configuration is also used to test the Node.js ID service.
--skip-database checks dependencies only, without a database or ID service.
Set CODEFACE_SYSTEM_PYTHON=1 to check the system Python installation.
EOF
}

while (($#)); do
    case "$1" in
        --skip-database)
            SKIP_DATABASE=1
            shift
            ;;
        --db-config)
            (($# >= 2)) || { usage >&2; exit 2; }
            DB_CONFIGS+=("$2")
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'ERROR: unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done
if [[ ${SKIP_DATABASE} == 1 ]]; then
    [[ ${#DB_CONFIGS[@]} -eq 0 ]] || {
        printf 'ERROR: --skip-database cannot be combined with --db-config\n' >&2
        exit 2
    }
elif [[ ${#DB_CONFIGS[@]} -eq 0 ]]; then
    DB_CONFIGS=("${CODEFACE_DIR}/codeface.conf")
fi

cleanup() {
    if [[ -n ${id_pid} ]]; then
        kill "${id_pid}" 2>/dev/null || true
        wait "${id_pid}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

command -v "${CODEFACE}" >/dev/null || fail "Codeface installation is missing"
"${CODEFACE}" --help >/dev/null
pass "Codeface CLI"

config_value() {
    local config=$1 key=$2 default_value=${3-}
    "${PYTHON}" - "${config}" "${key}" "${default_value}" <<'PY'
import sys
import yaml

path, key, default = sys.argv[1:]
with open(path, encoding="utf-8") as stream:
    data = yaml.safe_load(stream) or {}
value = data.get(key, default)
if value is None or isinstance(value, (dict, list)):
    raise SystemExit(f"{path}: database setting {key!r} must be a scalar")
value = str(value)
if "\n" in value or "\r" in value:
    raise SystemExit(f"{path}: database setting {key!r} must be one line")
print(value)
PY
}

for config in "${DB_CONFIGS[@]}"; do
    [[ -r ${config} ]] || fail "database configuration not readable: ${config}"
    dbhost="$(config_value "${config}" dbhost)"
    dbport="$(config_value "${config}" dbport 3306)"
    dbuser="$(config_value "${config}" dbuser)"
    dbpwd="$(config_value "${config}" dbpwd)"
    dbname="$(config_value "${config}" dbname)"
    [[ ${dbport} =~ ^[0-9]+$ && ${dbport} -ge 1 && ${dbport} -le 65535 ]] ||
        fail "${config}: invalid dbport '${dbport}'"
    [[ ${dbname} =~ ^[A-Za-z0-9_\$]+$ ]] ||
        fail "${config}: invalid dbname '${dbname}'"
    count="$(MYSQL_PWD="${dbpwd}" mysql --protocol=TCP --host="${dbhost}" \
        --port="${dbport}" --user="${dbuser}" --batch --skip-column-names \
        --connect-timeout=10 --execute="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${dbname}'")" ||
        fail "cannot connect using ${config}"
    [[ ${count} -gt 0 ]] || fail "database ${dbname} from ${config} has no tables"
    project_table="$(MYSQL_PWD="${dbpwd}" mysql --protocol=TCP --host="${dbhost}" \
        --port="${dbport}" --user="${dbuser}" --batch --skip-column-names \
        --execute="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${dbname}' AND table_name='project'")"
    [[ ${project_table} == 1 ]] || fail "database ${dbname} is not a Codeface schema"
    pass "MySQL schema ${dbname} at ${dbhost}:${dbport}"
done

for command in Rscript node npm git ctags-universal doxygen sloccount java dot; do
    command -v "${command}" >/dev/null || fail "required command '${command}' is missing"
done
for package in "${R_PACKAGES[@]}"; do
    installed_version="$(dpkg-query -W -f='${Version}' "${package}" 2>/dev/null)" ||
        fail "required R package ${package} is not installed"
    [[ ${installed_version} == "${R_VERSION}" ]] ||
        fail "${package} version mismatch: expected ${R_VERSION}, installed ${installed_version}"
done
expected_ctags='Universal Ctags 5.9.0, Copyright (C) 2015 Universal Ctags Team'
installed_ctags="$(ctags-universal --version | sed -n '1p')"
[[ ${installed_ctags} == "${expected_ctags}" ]] ||
    fail "ctags version mismatch: expected '${expected_ctags}', found '${installed_ctags}'"
libmime_version="$(node -p \
    "require('${CODEFACE_DIR}/id_service/node_modules/libmime/package.json').version")" ||
    fail "libmime is not installed"
[[ ${libmime_version} == 4.2.1 ]] ||
    fail "libmime version mismatch: expected 4.2.1, installed ${libmime_version}"
npm --prefix "${CODEFACE_DIR}/id_service" ls --omit=dev --all >/dev/null ||
    fail "Node.js dependency tree does not match package-lock.json"
"${PYTHON}" -c \
    'import MySQLdb, ctags, ftfy, jira, progressbar, yaml; import codeface'
Rscript - <<'RS'
required <- c("RMySQL", "RCurl", "testthat", "markovchain", "svglite")
pinned <- c(BH="1.75.0-0", slam="0.1-40", arules="1.5-0",
            proxy="0.4-16", logging="0.8-104", rjson="0.2.20")
for (package in unique(c(required, names(pinned)))) {
    loaded <- tryCatch(requireNamespace(package, quietly=TRUE),
                       error=function(e) FALSE)
    if (!loaded) {
        stop(sprintf("R package %s is missing or cannot be loaded", package))
    }
}
for (package in names(pinned)) {
    actual <- packageDescription(package)$Version
    if (actual != pinned[[package]]) {
        stop(sprintf("R package %s version mismatch: expected %s, installed %s",
                     package, pinned[[package]], actual))
    }
}
RS
pass "Python, R, Node.js (including libmime 4.2.1), Java, Graphviz, and ctags dependencies"

if [[ ${SKIP_DATABASE} == 1 ]]; then
    exit 0
fi

primary_config="${DB_CONFIGS[0]}"
id_port="$(config_value "${primary_config}" idServicePort 8080)"
id_host="$(config_value "${primary_config}" idServiceHostname localhost)"
node "${CODEFACE_DIR}/id_service/id_service.js" "${primary_config}" error \
    >"${CODEFACE_DIR}/id_service/verify.log" 2>&1 &
id_pid=$!
curl_host=${id_host}
[[ ${curl_host} == 0.0.0.0 || ${curl_host} == :: ]] && curl_host=localhost
for _ in {1..30}; do
    if users_json="$(curl --fail --silent "http://${curl_host}:${id_port}/getUsers")" &&
       [[ ${users_json} != *'"error"'* ]]; then
        pass "Node.js ID service and database connection"
        exit 0
    fi
    kill -0 "${id_pid}" 2>/dev/null || {
        sed -n '1,120p' "${CODEFACE_DIR}/id_service/verify.log" >&2
        fail "ID service exited during startup"
    }
    sleep 1
done
sed -n '1,120p' "${CODEFACE_DIR}/id_service/verify.log" >&2
fail "ID service did not become ready on ${curl_host}:${id_port}"
