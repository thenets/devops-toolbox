#!/bin/bash

# Slack sender script
# Simplest way to send messages to users and Slack channels
#
# How to use:
#   Export the following variables or pass them as parameters.
#   $ ./slack_sender.sh \
#       <SLACK_APP_OAUTH_TOKEN> \
#       <SLACK_CHANNEL_ID> \
#       <SLACK_MESSAGE_MARKDOWN>
#
# Example:
#   $ ./slack_sender.sh \
#       xoxb-not-a-real-token-this-will-not-work \
#       C05FSAP0RM0 \
#       '👾 Hi, I am a bot that can post *_fancy_* messages to any public channel.'
#
# Based on the following official documentation:
#   https://api.slack.com/tutorials/tracks/posting-messages-with-curl

# START

# Constants
declare -r MESSAGE_JSON=$(mktemp)

# Parameters
declare -r SLACK_CHANNEL_ID=${SLACK_CHANNEL_ID:-$1}
declare -r SLACK_APP_OAUTH_TOKEN=${SLACK_APP_OAUTH_TOKEN:-$2}
declare -r SLACK_MESSAGE_MARKDOWN=${SLACK_MESSAGE_MARKDOWN:-$3}

# Functions
function send_message() {
    cat <<EOF > ${MESSAGE_JSON}
{
	"channel": "${SLACK_CHANNEL_ID}",
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
        -H "Authorization: Bearer ${SLACK_APP_OAUTH_TOKEN}" \
        -X POST https://slack.com/api/chat.postMessage)
    echo ${OUTPUT} | jq .

    if [[ "$(echo ${OUTPUT} | jq -r .ok)" == "false" ]]; then
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
if [[ "${SLACK_CHANNEL_ID}" == "" ]]; then
    echo "ERROR! Missing 'SLACK_CHANNEL_ID' argument!"
    MISSING_ARG=1
fi
if [[ "${SLACK_APP_OAUTH_TOKEN}" == "" ]]; then
    echo "ERROR! Missing 'SLACK_APP_OAUTH_TOKEN' argument!"
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
