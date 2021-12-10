#!/bin/bash
# shellcheck disable=SC2046
set -euo pipefail
IFS=$'\n\t'

# USAGE:
#    ./tools/tidy.sh
#
# NOTE: This script requires the following tools:
# - shfmt
# - prettier
# - clang-format
# - shellcheck

cd "$(cd "$(dirname "$0")" && pwd)"/..

if [[ "${1:-}" == "-v" ]]; then
    shift
    set -x
fi
if [[ $# -gt 0 ]]; then
    cat <<EOF
USAGE:
    $0 [-v]
EOF
    exit 1
fi

prettier=prettier
if type -P npm &>/dev/null && type -P "$(npm bin)/prettier" &>/dev/null; then
    prettier="$(npm bin)/prettier"
fi

if [[ -z "${CI:-}" ]]; then
    if type -P rustfmt &>/dev/null; then
        rustfmt $(git ls-files '*.rs')
    fi
    if type -P shfmt &>/dev/null; then
        shfmt -l -w $(git ls-files '*.sh')
    else
        echo >&2 "WARNING: 'shfmt' is not installed"
    fi
    if type -P "${prettier}" &>/dev/null; then
        "${prettier}" -l -w $(git ls-files '*.yml')
    else
        echo >&2 "WARNING: 'prettier' is not installed"
    fi
    if type -P clang-format &>/dev/null; then
        clang-format -i $(git ls-files '*.c')
        clang-format -i $(git ls-files '*.cpp')
    else
        echo >&2 "WARNING: 'clang-format' is not installed"
    fi
    if type -P shellcheck &>/dev/null; then
        shellcheck $(git ls-files '*.sh')
        # SC2154 doesn't seem to work on dockerfile.
        shellcheck -e SC2148,SC2154 $(git ls-files '*Dockerfile')
    else
        echo >&2 "WARNING: 'shellcheck' is not installed"
    fi
else
    rustfmt --check $(git ls-files '*.rs')
    shfmt -d $(git ls-files '*.sh')
    "${prettier}" -c $(git ls-files '*.yml')
    clang-format -i $(git ls-files '*.cpp')
    git diff --exit-code
    shellcheck $(git ls-files '*.sh')
    # SC2154 doesn't seem to work on dockerfile.
    shellcheck -e SC2148,SC2154 $(git ls-files '*Dockerfile')
fi
