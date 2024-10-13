#!/bin/bash

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    echo "Script is being invoked directly."
else
    echo "Script is being sourced."
fi
