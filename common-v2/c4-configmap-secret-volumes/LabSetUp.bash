#!/bin/bash
set -e

# Pre-state for c4: the namespace and nothing else.
#
# The ConfigMap, the Secret and the Deployment are all the candidate's work,
# so there is no object to build here beyond the namespace they go in.
NS=config

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

echo "✅ c4 environment ready"
echo "   - namespace: $NS"
echo "   - Task: create a ConfigMap, a Secret and a Deployment that uses both"
echo "     as mounted volumes and as environment variables"
