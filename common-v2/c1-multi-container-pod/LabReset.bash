#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

k delete namespace multicontainer --ignore-not-found --timeout=120s >/dev/null

echo "c1 reset: namespace multicontainer removed"
