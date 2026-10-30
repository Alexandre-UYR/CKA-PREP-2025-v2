#!/bin/bash
set -e

# The pre-state for c20 is deliberately thin: the task is to CREATE a Pod, so
# there is nothing broken to reproduce. What has to exist is the namespace the
# task names.
#
# The namespace is created WITHOUT any pod-security labels. The candidate is
# writing a securityContext by hand here, not asking the API server to enforce
# one for them - that is the next question.
NS=secure

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

echo "✅ c20 environment ready"
echo "   - namespace: $NS"
echo "   - Task: create a Pod 'restricted' with a restricted securityContext"
