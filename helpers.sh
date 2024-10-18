#!/bin/bash

# Helpers
# =========================
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
log_debug() {
    local PURPLE=$(tput setaf 5)
    local NC=$(tput sgr0)
    echo "${PURPLE}[DEBUG  ]${NC} $*" 1>&2
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
