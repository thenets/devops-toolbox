#!/bin/bash



cat <<END > 
collections:
  - name: amazon.aws
    version: 8.1.0
  - name: amazon.cloud
    version: 0.4.0
    type: git

END
