#!/bin/bash

# Script help message example
#
# How to use:
#   $ ./help-message.sh \
#       <PARAM_1> \
#       <PARAM_2>
#
# Example:
#   $ ./help-message.sh \
#       quero \
#       cafe
#
# NOTE:
#   The line '# START' is important. It is the limit of the help section.
#   The 'print_help()' function will read until it finds that line.

# START

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


# Main
print_help
