#!/bin/bash

# References
# - https://stackoverflow.com/questions/911168/how-can-i-detect-if-my-shell-script-is-running-through-a-pipe/30520299#30520299
# - https://www.cyberciti.biz/faq/linux-unix-bash-check-interactive-shell/ 

# TTY example
#   $ ./shell-env-test.sh
[[ -t 1 ]] && \
    echo 'STDOUT is attached to TTY'

# Pipeline examples
#   $ ./shell-env-test.sh | tee
#   $ ./shell-env-test.sh 2>&1 | tee
[[ -p /dev/stdout ]] && \
    echo 'STDOUT is attached to a pipe'

# Redirection example
#   $ ./shell-env-test.sh >> shell-env-test.log
#   $ cat ./shell-env-test.log
[[ ! -t 1 && ! -p /dev/stdout ]] && \
    echo 'STDOUT is attached to a redirection'

# Interactive example:
#  $ ./shell-env-test.sh
#
# Non-interactive example:
#  $ ./shell-env-test.sh | tee
if [ -t 1 ]
then
    echo "I will do interactive stuff here."
else
    echo "I will do non-interactive stuff here or simply exit with an error."
fi
