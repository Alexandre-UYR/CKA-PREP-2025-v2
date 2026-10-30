# Question: One base, two environments
#
# Task:
# A Kustomize base is at /tmp/cka-lab/kustomize/base. It holds a Deployment
# `app` (2 replicas, image nginx:1.24) and a Service `app` on port 80.
#
# Create two overlays on top of that base:
#   /tmp/cka-lab/kustomize/overlays/dev
#   /tmp/cka-lab/kustomize/overlays/prod
#
# Both overlays must use the base. The dev overlay must deploy image
# nginx:1.25 with 1 replica; the prod overlay must deploy image nginx:1.26
# with 3 replicas.
#
# Build each overlay with `kustomize build` (or `kubectl kustomize`) and apply
# the dev one to the cluster.
