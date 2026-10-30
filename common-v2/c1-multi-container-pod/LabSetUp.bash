#!/bin/bash
set -e

# The pre-state for c1 is deliberately thin: the task is to CREATE a Pod, so
# there is nothing broken to reproduce. What does have to exist is the
# namespace the task names.
NS=multicontainer

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

echo "✅ c1 environment ready"
echo "   - namespace: $NS"
echo "   - Task: create a Pod with two containers (redis and memcached)"
