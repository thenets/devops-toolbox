#!/bin/bash

# GitHub Release Asset Downloader
# Simplest way to download the latest artifact from a public GitHub project
#
# How to use:
#   Export the following variables or pass them as parameters.
#   $ ./github-release-downloader.sh \
#       <GITHUB_ORG> \
#       <GITHUB_REPO> \
#       <SEARCH_PATTERN>
#
# Example:
#   $ ./github-release-downloader.sh \
#       gohugoio \
#       hugo \
#       "_linux-amd64.tar.gz"
#
# Inspired by:
#   https://gist.github.com/umohi/bfc7ad9a845fc10289c03d532e3d2c2f

# START

# Parameters
declare -r GITHUB_ORG=${GITHUB_ORG:-$1}
declare -r GITHUB_REPO=${GITHUB_REPO:-$2}
declare -r SEARCH_PATTERN=${SEARCH_PATTERN:-$3}

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
log_info() {
    local CYAN=$(tput setaf 6)
    local NC=$(tput sgr0)
    echo "${CYAN}[INFO   ]${NC} $*" 1>&2
}
log_warning() {
    local YELLOW=$(tput setaf 3)
    local NC=$(tput sgr0)
    echo "${YELLOW}[WARNING]${NC} $*" 1>&2
}
log_error() {
    local RED=$(tput setaf 1)
    local NC=$(tput sgr0)
    echo "${RED}[ERROR  ]${NC} $*" 1>&2
}
log_success() {
    local GREEN=$(tput setaf 2)
    local NC=$(tput sgr0)
    echo "${GREEN}[SUCCESS]${NC} $*" 1>&2
}
log_title() {
    local GREEN=$(tput setaf 2)
    local BOLD=$(tput bold)
    local NC=$(tput sgr0)
    echo 1>&2
    echo "${GREEN}${BOLD}---- $* ----${NC}" 1>&2
}
h_run() {
    local ORANGE=$(tput setaf 3)
    local NC=$(tput sgr0)
    echo "${ORANGE}\$${NC} $*" 1>&2
    eval "$*"
}

err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}


# Functions
function get_tags() {
    # DEPRECATED, using release instead
    log_info "Checking https://api.github.com/repos/${GITHUB_ORG}/${GITHUB_REPO}/tags"

    # TODO add error handling
    TAGS=$(curl -sL https://api.github.com/repos/${GITHUB_ORG}/${GITHUB_REPO}/tags)
}

function get_latest_tag() {
    # DEPRECATED, using release instead
    get_tags

    TAG_LATEST=$(echo ${TAGS} | jq -r '.[0]')
    TAG_LATEST_NAME=$(echo $TAG_LATEST | jq -r .name)

    log_info "[get_latest_tag] latest tag identified: ${TAG_LATEST_NAME}"
}

function get_releases() {
    log_info "[get_releases] checking https://api.github.com/repos/${GITHUB_ORG}/${GITHUB_REPO}/releases"

    # TODO add error handling
    RELEASES=$(curl -sL https://api.github.com/repos/${GITHUB_ORG}/${GITHUB_REPO}/releases)
}

function get_latest_release() {
    get_releases

    RELEASE_LATEST=$(echo ${RELEASES} | jq -r '.[0]')
    RELEASE_LATEST_NAME=$(echo $RELEASE_LATEST | jq -r .name)
    local _ID=$(echo $RELEASE_LATEST | jq -r .id)

    log_info "[get_latest_release] latest release identified: name=${RELEASE_LATEST_NAME} id=${_ID}"
}

function get_release_assets() {
    local _RELEASE_NAME=$1

    RELEASE=""
    ASSETS=""

    # TODO error handling, release not found
    RELEASE=$(echo ${RELEASES} | jq -r ".[] | select(.name == \"$_RELEASE_NAME\")")
    ASSETS=$(echo ${RELEASES} | jq -r ".[] | select(.name == \"$_RELEASE_NAME\") | .assets")

    local _ASSETS_COUNT=$(echo ${ASSETS} | jq length)
    log_info "[get_release_assets] release=${_RELEASE_NAME} - total_of_assets=${_ASSETS_COUNT}"
}

function search_asset_by_name() {
    local _CONTAINS=$1

    ASSET=""
    ASSET_NAME=""
    ASSET_URL=""
    # TODO assert ASSETS is > 0

    ASSET=$(echo $ASSETS | jq -r ".[] | select(.name | contains(\"$_CONTAINS\"))")

    ASSET_NAME=$(echo ${ASSET} | jq -r ".name" | head -n 1)
    ASSET_URL=$(echo ${ASSET} | jq -r ".browser_download_url" | head -n 1)

    log_info "[search_asset_by_name] found ${ASSET_NAME}"
    log_info "[search_asset_by_name] ${ASSET_URL}"
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

# Input validation
declare -i MISSING_ARG=0
if [[ "${GITHUB_ORG}" == "" ]]; then
    echo "ERROR! Missing 'GITHUB_ORG' argument!"
    MISSING_ARG=1
fi
if [[ "${GITHUB_REPO}" == "" ]]; then
    echo "ERROR! Missing 'GITHUB_REPO' argument!"
    MISSING_ARG=1
fi
if [[ "${SEARCH_PATTERN}" == "" ]]; then
    echo "ERROR! Missing 'SEARCH_PATTERN' argument!"
    MISSING_ARG=1
fi
if [[ ${MISSING_ARG} -gt 0 ]]; then
    print_help
    exit 1
fi

# Variables (DEPRECATED)
# declare TAGS
# declare TAG_LATEST
# declare TAG_LATEST_NAME

# Variables
declare RELEASES
declare RELEASE_LATEST
declare RELEASE_LATEST_NAME
declare RELEASE
declare ASSETS
declare ASSET

# Main
function main() {
    log_info "Parameters:"
    log_info "   GITHUB_ORG     : ${GITHUB_ORG}"
    log_info "   GITHUB_REPO    : ${GITHUB_REPO}"
    log_info "   SEARCH_PATTERN : ${SEARCH_PATTERN}"

    # TODO check deps, like curl and jq

    # Retrieve
    get_latest_release
    get_release_assets ${RELEASE_LATEST_NAME}
    search_asset_by_name ${SEARCH_PATTERN}

    declare -r OUTPUT_FILE_PATH="$(pwd)/${ASSET_NAME}"

    # Download
    if [[ -f "${OUTPUT_FILE_PATH}" ]]; then
        log_warning "File already exist! ${OUTPUT_FILE_PATH}"
        log_warning "Skipping..."
        exit 0
    fi
    log_info "Downloading..."
    h_run "curl --progress-bar -o ${OUTPUT_FILE_PATH} ${ASSET_URL}"
    log_success "Saved on: ${OUTPUT_FILE_PATH}"
}

main
