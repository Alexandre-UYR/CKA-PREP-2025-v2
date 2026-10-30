#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

k delete namespace topology --ignore-not-found --timeout=120s >/dev/null

echo "c9 reset: namespace topology removed"
