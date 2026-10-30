#!/bin/bash
set -uo pipefail

LABDIR=/tmp/cka-lab

# The two files the candidate was supposed to produce.
rm -f /root/control-plane-logs.txt "$HOME/control-plane-logs.txt"
rm -f /root/scheduler-component.txt "$HOME/scheduler-component.txt"

# The state file the setup wrote.
rm -f "$LABDIR/x3.logs"

# Nothing on the node was changed by this question, so there is nothing else to
# put back: the log files belong to the cluster.

echo "x3 reset: the two answer files removed, the state file deleted"
