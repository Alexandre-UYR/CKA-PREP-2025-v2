#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the ConfigMap, the ServiceAccount, the CronJob and every
# Job the schedule (or the candidate) created. Deleting it takes all of them.
k delete namespace cron --ignore-not-found --timeout=120s >/dev/null

echo "v7 reset: namespace cron removed"
