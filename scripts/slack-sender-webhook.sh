#!/bin/bash

# Slack sender script
# Simplest way to send messages to users and Slack channels
#
# How to use:
#   Export the following variables or pass them as parameters.
#   $ ./slack-sender-webhook.sh \
#       <SLACK_WEBHOOK_URL> \
#       <SLACK_MESSAGE_MARKDOWN>
#
# Example:
#   $ ./slack-sender-webhook.sh \
#       https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX \
#       '👾 Hi, I am a bot that can post *_fancy_* messages to any public channel.'
#
# Based on the following official documentation:
#   https://api.slack.com/messaging/webhooks

# START

# Constants
declare -r MESSAGE_JSON=$(mktemp)

# Parameters
declare -r SLACK_WEBHOOK_URL=${SLACK_WEBHOOK_URL:-$1}
declare -r SLACK_MESSAGE_MARKDOWN=${SLACK_MESSAGE_MARKDOWN:-$3}

# Functions
function send_message() {
    cat <<EOF > ${MESSAGE_JSON}
{
	"blocks": [
		{
			"type": "section",
			"text": {
				"type": "mrkdwn",
				"text": "${SLACK_MESSAGE_MARKDOWN}"
			}
		}
	]
}
EOF

    set -e
    echo "[INFO] JSON validation"
    cat ${MESSAGE_JSON} | jq .

    echo "[INFO] Sending message"
    OUTPUT=$(curl -s -H "Content-type: application/json" \
        --data-binary @${MESSAGE_JSON} \
        -X POST ${SLACK_WEBHOOK_URL})
    echo ${OUTPUT}

    if [[ "${OUTPUT}" != "ok" ]]; then
        echo "ERROR! Couldn't send the message"
        set -e
        rm -f ${MESSAGE_JSON}
        exit 1
    fi

    rm -f ${MESSAGE_JSON}
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
if [[ "${SLACK_WEBHOOK_URL}" == "" ]]; then
    echo "ERROR! Missing 'SLACK_WEBHOOK_URL' argument!"
    MISSING_ARG=1
fi
if [[ "${SLACK_MESSAGE_MARKDOWN}" == "" ]]; then
    echo "ERROR! Missing 'SLACK_MESSAGE_MARKDOWN' argument!"
    MISSING_ARG=1
fi
if [[ ${MISSING_ARG} -gt 0 ]]; then
    print_help
    exit 1
fi


# Main
send_message
