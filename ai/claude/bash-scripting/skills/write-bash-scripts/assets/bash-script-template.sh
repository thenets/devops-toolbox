#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS] ARGUMENT

Describe what the script does.

Options:
  -h, --help  Show this help message
EOF
}

log() {
    local level=$1
    shift
    printf '[%s] %s\n' "${level}" "$*" >&2
}

die() {
    log ERROR "$*"
    exit 1
}

main() {
    local argument=''

    while (($# > 0)); do
        case $1 in
            -h|--help)
                usage
                return 0
                ;;
            --)
                shift
                break
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                if [[ -n ${argument} ]]; then
                    die "Expected one argument"
                fi
                argument=$1
                ;;
        esac
        shift
    done

    if (($# > 0)); then
        if [[ -n ${argument} || $# -ne 1 ]]; then
            die "Expected one argument"
        fi
        argument=$1
    fi

    [[ -n ${argument} ]] || {
        usage >&2
        return 2
    }

    log INFO "Processing ${argument} from ${SCRIPT_DIR}"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
