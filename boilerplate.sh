#!/bin/bash

# boilerplate.sh
# The greatest script that does nothing.
#
# How to use:
#   Export the following variables or pass them as parameters.
#   $ ./boilerplate.sh \
#       <MESSAGE>
#
# Example:
#   $ ./boilerplate.sh \
#       "hello, friend"
#
# NOTE:
#   this script does nothing.

# START


# Constants
declare -r SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
declare -r TEMP_MESSAGE_FILE=$(mktemp)


# Parameters
declare -r MESSAGE=${MESSAGE:-$1}


# Helpers
if [ -z "$TERM" ] || [ "$TERM" == "dumb" ]; then
    tput() {
        return 0
    }
fi
if ! type tput >/dev/null 2>&1; then
    tput() {
        return 0
    }
fi
function log_info() {
    local CYAN=$(tput setaf 6)
    local NC=$(tput sgr0)
    echo "${CYAN}[INFO   ]${NC} $*" 1>&2
}
function log_warning() {
    local YELLOW=$(tput setaf 3)
    local NC=$(tput sgr0)
    echo "${YELLOW}[WARNING]${NC} $*" 1>&2
}
function log_debug() {
    local PURPLE=$(tput setaf 5)
    local NC=$(tput sgr0)
    echo "${PURPLE}[DEBUG  ]${NC} $*" 1>&2
}
function log_error() {
    local RED=$(tput setaf 1)
    local NC=$(tput sgr0)
    echo "${RED}[ERROR  ]${NC} $*" 1>&2
}
function log_success() {
    local GREEN=$(tput setaf 2)
    local NC=$(tput sgr0)
    echo "${GREEN}[SUCCESS]${NC} $*" 1>&2
}
function log_title() {
    local GREEN=$(tput setaf 2)
    local BOLD=$(tput bold)
    local NC=$(tput sgr0)
    echo 1>&2
    echo "${GREEN}${BOLD}---- $* ----${NC}" 1>&2
}
function h_run() {
    local ORANGE=$(tput setaf 3)
    local NC=$(tput sgr0)
    echo "${ORANGE}\$${NC} $*" 1>&2
    eval "$*"
}
function err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}
function print_help() {
    # Prints help section from the top of the file
    #
    # It stops until it finds the '# START' line

    echo "HELP:"
    while read -r LINE; do
        if [[ "${LINE}" == "#!/bin/bash" ]] || [[ "${LINE}" == "" ]]; then
            continue
        fi
        if [[ "${LINE}" == "# START" ]]; then
            return
        fi
        echo "${LINE}" | sed 's/^# /  /g' | sed 's/^#//g'
    done <${BASH_SOURCE[0]}
}


# Functions
function write_to_temp_file() {
    # Write input string to temp file
    # Globals:
    #   TEMP_MESSAGE_FILE
    # Arguments:
    #   1: IN_STRING
    # Outputs:
    #   None
    local IN_STRING=$1

    log_debug "Writing to temp file: ${TEMP_MESSAGE_FILE}"
    echo ${IN_STRING} > ${TEMP_MESSAGE_FILE}
}


# Main
if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    # Script is being invoked directly instead of being sourced
    write_to_temp_file "quero cafe"
    
    log_info "Print the temp file content"
    cat ${TEMP_MESSAGE_FILE}
fi
