#!/bin/bash

set -e

function wait_for_connection() {
	# The domain you want to ping
	local DOMAIN="thenets.org"

	# Maximum number of retries before giving up
	local MAX_RETRIES=100
	local RETRY_COUNT=0

	echo "wait_for_connection: Waiting for $DOMAIN to become reachable..."

	while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
		if ping -c 1 $DOMAIN &> /dev/null; then
			echo "wait_for_connection: $DOMAIN is now reachable!"
			break
		else
			echo "wait_for_connection: $DOMAIN is not reachable. Retrying in 5 seconds..."
			sleep 5
			RETRY_COUNT=$((RETRY_COUNT + 1))
		fi
	done

	if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
		echo "wait_for_connection: Failed to reach $DOMAIN after $MAX_RETRIES retries."
	fi
}

wait_for_connection
