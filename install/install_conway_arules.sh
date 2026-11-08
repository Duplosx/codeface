#!/bin/sh
# arules-compat-fix: Build a private arules 1.5-0.1 for Conway only.
# Usage: sh install/install_conway_arules.sh /path/to/arules_1.5-0.tar.gz
# Original source: https://cran.r-project.org/src/contrib/Archive/arules/arules_1.5-0.tar.gz
set -eu

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 /path/to/arules_1.5-0.tar.gz" >&2
    exit 1
fi

conway_project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
conway_build_dir=$(mktemp -d)
trap 'rm -rf -- "$conway_build_dir"' EXIT
conway_library="$conway_project_dir/codeface/R/.conway-library"

tar -xzf "$1" -C "$conway_build_dir"
patch --batch --fuzz=0 -d "$conway_build_dir/arules" -p1 < "$conway_project_dir/patches/arules-r4-compat.patch"
# arules-compat-fix: The intentional source edits invalidate the archive's checksums.
rm "$conway_build_dir/arules/MD5"
mkdir -p "$conway_library"
R CMD INSTALL --library="$conway_library" "$conway_build_dir/arules"
