#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The policy first, so that deleting the namespaces is not the only thing
# standing between the candidate and a stale NetworkPolicy.
k delete networkpolicy api -n pol --ignore-not-found >/dev/null

# Everything the setup created - the api, the Service, the two probe pods, and
# anything the candidate added - lives in these three namespaces.
k delete namespace pol --ignore-not-found --timeout=120s >/dev/null
k delete namespace client --ignore-not-found --timeout=120s >/dev/null
k delete namespace other --ignore-not-found --timeout=120s >/dev/null

echo "v12 reset: NetworkPolicy api and namespaces pol, client, other removed"
