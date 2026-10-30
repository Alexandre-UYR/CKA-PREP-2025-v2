#!/bin/bash
set -uo pipefail

LABDIR=/tmp/cka-lab

# The snapshot the candidate was supposed to produce.
rm -f "$HOME/snapshotdb" /root/snapshotdb

# The state file the setup wrote.
rm -f "$LABDIR/x2.env"

echo "x2 reset: ~/snapshotdb removed, the state file deleted"
