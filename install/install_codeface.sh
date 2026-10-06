#!/usr/bin/env bash
# Reproducible Codeface installation for Ubuntu 22.04 (including WSL2).
set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly CODEFACE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly VENV_DIR="${CODEFACE_DIR}/.venv"
readonly R_VERSION="4.3.3-1.2204.0"
readonly R_PACKAGES=(r-base r-base-core r-base-dev r-recommended)
readonly CRAN_KEY_URL="https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc"
readonly CRAN_KEY_FINGERPRINT="E298A3A825C0D65DFD57CBB651716619E084DAB9"
readonly CRAN_KEYRING="/usr/share/keyrings/cran-archive-keyring.gpg"
readonly CRAN_SOURCE_FILE="/etc/apt/sources.list.d/cran-r.list"
readonly CRAN_REPOSITORY="deb [signed-by=${CRAN_KEYRING}] https://cloud.r-project.org/bin/linux/ubuntu jammy-cran40/"
readonly R_APT_PREFERENCES="/etc/apt/preferences.d/codeface-r"

DB_MODE="local"
DEPENDENCIES_ONLY=0
DB_CONFIGS=()
LOCAL_DB_PORT="${CODEFACE_DB_PORT:-3306}"

usage() {
    cat <<'EOF'
Usage:
  install/install_codeface.sh [--database local]
  install/install_codeface.sh --database external --db-config FILE [--db-config FILE ...]

Options:
  --database MODE   Database mode: local (default) or external.
  --db-config FILE  Codeface global YAML configuration for an external schema.
                    Repeat to initialize and verify multiple schemas.
  --dependencies-only  Install dependencies without configuring a database.
  -h, --help        Show this help.

Set CODEFACE_SYSTEM_PYTHON=1 to install into system Python instead of a venv.
EOF
}

while (($#)); do
    case "$1" in
        --dependencies-only)
            DEPENDENCIES_ONLY=1
            shift
            ;;
        --database)
            (($# >= 2)) || { usage >&2; exit 2; }
            DB_MODE="$2"
            shift 2
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

if [[ ${DEPENDENCIES_ONLY} == 1 ]]; then
    DB_MODE=external
    [[ ${#DB_CONFIGS[@]} -eq 0 ]] || {
        printf 'ERROR: --dependencies-only cannot be combined with --db-config\n' >&2
        exit 2
    }
fi
[[ ${DB_MODE} == local || ${DB_MODE} == external ]] || {
    printf 'ERROR: --database must be local or external\n' >&2
    exit 2
}
if [[ ${DB_MODE} == local && ${#DB_CONFIGS[@]} -gt 0 ]]; then
    printf 'ERROR: --db-config is only valid with --database external\n' >&2
    exit 2
fi
if [[ ${DB_MODE} == local ]]; then
    if [[ ! ${LOCAL_DB_PORT} =~ ^[0-9]+$ ]] ||
        ((LOCAL_DB_PORT < 1 || LOCAL_DB_PORT > 35535)); then
        printf 'ERROR: CODEFACE_DB_PORT must be an integer from 1 through 35535\n' >&2
        exit 2
    fi
fi
if [[ ${DB_MODE} == external && ${DEPENDENCIES_ONLY} == 0 && ${#DB_CONFIGS[@]} -eq 0 ]]; then
    printf 'ERROR: external mode requires at least one --db-config FILE\n' >&2
    exit 2
fi

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
on_error() {
    local status=$?
    printf 'ERROR: installation failed at line %s: %s (exit %s)\n' \
        "${BASH_LINENO[0]}" "${BASH_COMMAND}" "${status}" >&2
    exit "${status}"
}
trap on_error ERR

if [[ ${EUID} -eq 0 ]]; then
    SUDO=()
else
    command -v sudo >/dev/null || die "sudo is required when not running as root"
    sudo -v || die "sudo access is required to install system packages"
    SUDO=(sudo)
fi

[[ -r /etc/os-release ]] || die "cannot determine the operating system"
# shellcheck disable=SC1091
. /etc/os-release
[[ ${ID:-} == ubuntu && ${VERSION_ID:-} == 22.04 ]] ||
    die "this installer supports Ubuntu 22.04; found ${PRETTY_NAME:-unknown}"

cd "${CODEFACE_DIR}"
for config in "${DB_CONFIGS[@]}"; do
    [[ -r ${config} ]] || die "database configuration is not readable: ${config}"
done

log "Configuring the CRAN repository for R ${R_VERSION}"
"${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get update
"${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    --no-install-recommends ca-certificates curl gnupg

cran_key="$(mktemp)"
cran_keyring="$(mktemp)"
curl --fail --location --retry 3 "${CRAN_KEY_URL}" --output "${cran_key}"
actual_fingerprint="$(gpg --batch --show-keys --with-colons "${cran_key}" |
    awk -F: '$1 == "fpr" {print $10; exit}')"
[[ ${actual_fingerprint} == "${CRAN_KEY_FINGERPRINT}" ]] ||
    die "unexpected CRAN signing-key fingerprint: ${actual_fingerprint:-missing}"
gpg --batch --yes --dearmor --output "${cran_keyring}" "${cran_key}"
"${SUDO[@]}" install -m 0644 "${cran_keyring}" "${CRAN_KEYRING}"
printf '%s\n' "${CRAN_REPOSITORY}" |
    "${SUDO[@]}" tee "${CRAN_SOURCE_FILE}" >/dev/null

# CRAN retains the requested R release, but its unversioned r-cran-* packages
# track current R and eventually become incompatible with it.  Ubuntu Jammy's
# release packages form a fixed, mutually compatible set, so use CRAN only for
# the explicitly pinned R runtime and use Jammy for R add-on packages.
apt_preferences="$(mktemp)"
cat >"${apt_preferences}" <<EOF
Package: r-base r-base-core r-base-dev r-recommended
Pin: version ${R_VERSION}
Pin-Priority: 1001

Package: r-cran-* littler
Pin: release o=Ubuntu
Pin-Priority: 1001

Package: r-cran-* littler
Pin: release o=CRAN
Pin-Priority: -1
EOF
"${SUDO[@]}" install -m 0644 "${apt_preferences}" "${R_APT_PREFERENCES}"
rm -f -- "${cran_key}" "${cran_keyring}" "${apt_preferences}"

log "Installing Ubuntu dependencies (${DB_MODE} database mode)"
"${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get update

for package in "${R_PACKAGES[@]}"; do
    if ! apt-cache madison "${package}" | awk '{print $3}' | grep -Fxq "${R_VERSION}"; then
        die "required ${package}=${R_VERSION} is unavailable from the configured apt repositories. Configure an Ubuntu 22.04 CRAN repository or snapshot containing that exact version, run apt-get update, and retry"
    fi
done

APT_PACKAGES=(
    build-essential default-jdk doxygen gfortran graphviz
    libapparmor-dev libarchive-dev libcairo2-dev libcurl4-openssl-dev
    libgdal-dev libgles2-mesa-dev libglu1-mesa-dev libgraphviz-dev
    libhunspell-dev libmagick++-dev libmysqlclient-dev libpoppler-cpp-dev
    libpoppler-dev libpoppler-glib-dev libssh2-1-dev libssl-dev libudunits2-dev
    libx11-dev libxml2-dev libxslt1-dev libxt-dev libyaml-dev
    git nodejs npm pkg-config python3-dev
    "r-base=${R_VERSION}" "r-base-core=${R_VERSION}" "r-base-dev=${R_VERSION}"
    "r-recommended=${R_VERSION}" r-cran-devtools r-cran-rcurl r-cran-reshape r-cran-rjson
    r-cran-markovchain r-cran-rmysql r-cran-scales r-cran-stringr r-cran-svglite r-cran-xtable
    r-cran-xts r-cran-zoo sloccount subversion texlive universal-ctags
    xorg-dev xsltproc
)
if [[ ${CODEFACE_SYSTEM_PYTHON:-0} == 1 ]]; then
    APT_PACKAGES+=(python3-pip)
else
    APT_PACKAGES+=(python3-venv)
fi
if [[ ${DB_MODE} == local ]]; then
    mysql_x_port=$((LOCAL_DB_PORT + 30000))
    mysql_config="$(mktemp)"
    cat >"${mysql_config}" <<EOF
[mysqld]
port=${LOCAL_DB_PORT}
mysqlx-port=${mysql_x_port}
EOF
    "${SUDO[@]}" install -d -m 0755 /etc/mysql/mysql.conf.d
    "${SUDO[@]}" install -m 0644 "${mysql_config}" \
        /etc/mysql/mysql.conf.d/codeface.cnf
    rm -f -- "${mysql_config}"
    APT_PACKAGES+=(mysql-server)
else
    APT_PACKAGES+=(mysql-client)
fi
"${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    --no-install-recommends "${APT_PACKAGES[@]}"

log "Configuring R's Java support"
"${SUDO[@]}" R CMD javareconf

if [[ ${CODEFACE_SYSTEM_PYTHON:-0} == 1 ]]; then
    log "Installing into system Python"
    PYTHON=("${SUDO[@]}" python3)
else
    log "Creating the Python environment"
    python3 -m venv "${VENV_DIR}"
    PYTHON=("${VENV_DIR}/bin/python")
fi
"${PYTHON[@]}" -m pip install --upgrade \
    "pip==24.3.1" "setuptools==75.6.0" "wheel==0.45.1"
"${PYTHON[@]}" -m pip install --editable "${CODEFACE_DIR}"

config_value() {
    local config=$1 key=$2 default_value=${3-}
    "${PYTHON[@]}" - "${config}" "${key}" "${default_value}" <<'PY'
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

mysql_args_for_config() {
    local config=$1
    DB_HOST="$(config_value "${config}" dbhost)"
    DB_PORT="$(config_value "${config}" dbport 3306)"
    DB_USER="$(config_value "${config}" dbuser)"
    DB_PASSWORD="$(config_value "${config}" dbpwd)"
    DB_NAME="$(config_value "${config}" dbname)"
    [[ ${DB_PORT} =~ ^[0-9]+$ && ${DB_PORT} -ge 1 && ${DB_PORT} -le 65535 ]] ||
        die "${config}: invalid dbport '${DB_PORT}'"
    [[ ${DB_NAME} =~ ^[A-Za-z0-9_\$]+$ ]] ||
        die "${config}: dbname must contain only letters, digits, underscore, or dollar"
    MYSQL_ARGS=(--protocol=TCP --host="${DB_HOST}" --port="${DB_PORT}" --user="${DB_USER}")
}

initialize_configured_schema() {
    local config=$1 table_count
    mysql_args_for_config "${config}"
    log "Checking ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
    MYSQL_PWD="${DB_PASSWORD}" mysql "${MYSQL_ARGS[@]}" --connect-timeout=10 \
        --execute="SELECT 1" >/dev/null ||
        die "cannot connect using database settings from ${config}"
    table_count="$(MYSQL_PWD="${DB_PASSWORD}" mysql "${MYSQL_ARGS[@]}" \
        --batch --skip-column-names --execute="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}'")"
    if MYSQL_PWD="${DB_PASSWORD}" mysql "${MYSQL_ARGS[@]}" --batch --skip-column-names \
        --execute="SELECT 1 FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name='project'" |
        grep -qx 1; then
        log "Database ${DB_NAME} is already initialized"
    elif [[ ${table_count} == 0 ]]; then
        log "Loading Codeface schema into ${DB_NAME}"
        sed -e '/^DROP SCHEMA IF EXISTS/d' \
            -e '/^CREATE SCHEMA IF NOT EXISTS/d' \
            -e "s/\`codeface\`/\`${DB_NAME}\`/g" datamodel/codeface_schema.sql |
            MYSQL_PWD="${DB_PASSWORD}" mysql "${MYSQL_ARGS[@]}"
    else
        die "${DB_NAME} contains ${table_count} tables but no Codeface project table; refusing to overwrite it"
    fi
}

if [[ ${DB_MODE} == local ]]; then
    readonly LOCAL_DB_USER="${CODEFACE_DB_USER:-codeface}"
    readonly LOCAL_DB_PASSWORD="${CODEFACE_DB_PASSWORD:-codeface}"
    [[ ${LOCAL_DB_USER} =~ ^[A-Za-z0-9_]+$ ]] || die "invalid CODEFACE_DB_USER"
    sql_password=${LOCAL_DB_PASSWORD//\'/\'\'}

    log "Starting local MySQL"
    if command -v systemctl >/dev/null && systemctl is-system-running >/dev/null 2>&1; then
        "${SUDO[@]}" systemctl enable --now mysql
    else
        "${SUDO[@]}" service mysql start
    fi
    mysqladmin --protocol=socket -uroot ping >/dev/null 2>&1 ||
        "${SUDO[@]}" mysqladmin --protocol=socket -uroot ping >/dev/null

    log "Creating the local Codeface database and user"
    "${SUDO[@]}" mysql --protocol=socket -uroot <<SQL
CREATE DATABASE IF NOT EXISTS \`codeface\` CHARACTER SET utf8;
CREATE USER IF NOT EXISTS '${LOCAL_DB_USER}'@'localhost' IDENTIFIED BY '${sql_password}';
ALTER USER '${LOCAL_DB_USER}'@'localhost' IDENTIFIED BY '${sql_password}';
GRANT ALL PRIVILEGES ON \`codeface\`.* TO '${LOCAL_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
    LOCAL_CONFIG_DIR="$(mktemp -d)"
    trap 'rm -rf -- "${LOCAL_CONFIG_DIR:-}"' EXIT
    config="${LOCAL_CONFIG_DIR}/codeface.conf"
    "${PYTHON[@]}" - "${CODEFACE_DIR}/codeface.conf" "${config}" \
        "${LOCAL_DB_USER}" "${LOCAL_DB_PASSWORD}" codeface 8080 \
        "${LOCAL_DB_PORT}" <<'PY'
import sys
import yaml

source, destination, user, password, database, service_port, db_port = sys.argv[1:]
with open(source, encoding="utf-8") as stream:
    config = yaml.safe_load(stream)
config.update(dbhost="localhost", dbport=int(db_port), dbuser=user, dbpwd=password,
              dbname=database, idServicePort=int(service_port))
with open(destination, "w", encoding="utf-8") as stream:
    yaml.safe_dump(config, stream, sort_keys=False)
PY
    DB_CONFIGS+=("${config}")
    initialize_configured_schema "${config}"
else
    for config in "${DB_CONFIGS[@]}"; do
        initialize_configured_schema "${config}"
    done
fi

log "Installing the Node.js ID service"
npm --prefix "${CODEFACE_DIR}/id_service" ci --no-audit --no-fund

if [[ ${CODEFACE_INSTALL_CPPSTATS:-0} == 1 ]]; then
    log "Installing cppstats"
    readonly CPPSTATS_URL="https://github.com/nlschn/cppstats/archive/refs/tags/py3-complete.tar.gz"
    cppstats_tmp="$(mktemp -d)"
    trap 'rm -rf -- "${cppstats_tmp:-}" "${LOCAL_CONFIG_DIR:-}"' EXIT
    curl --fail --location --retry 3 "${CPPSTATS_URL}" -o "${cppstats_tmp}/cppstats.tar.gz"
    tar -xzf "${cppstats_tmp}/cppstats.tar.gz" -C "${cppstats_tmp}"
    "${PYTHON[@]}" -m pip install "${cppstats_tmp}/cppstats-py3-complete"
    rm -rf -- "${cppstats_tmp}"
fi

if [[ ${CODEFACE_INSTALL_R_PACKAGES:-1} == 1 ]]; then
    log "Installing Codeface R packages (this can take several minutes)"
    "${SUDO[@]}" Rscript "${CODEFACE_DIR}/packages.r"
fi

log "Verifying installation"
VERIFY_ARGS=()
if [[ ${DEPENDENCIES_ONLY} == 1 ]]; then
    VERIFY_ARGS+=(--skip-database)
fi
for config in "${DB_CONFIGS[@]}"; do
    VERIFY_ARGS+=(--db-config "${config}")
done
bash "${SCRIPT_DIR}/verify_codeface.sh" "${VERIFY_ARGS[@]}"
log "Installation complete"
if [[ ${CODEFACE_SYSTEM_PYTHON:-0} != 1 ]]; then
    log "Activate with: source ${VENV_DIR}/bin/activate"
fi
