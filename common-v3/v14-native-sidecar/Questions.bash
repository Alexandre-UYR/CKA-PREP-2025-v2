# Question: Convert a legacy sidecar into a native one
#
# The Deployment `legacy` in namespace `sidecars` runs its log collector as a
# REGULAR container. That is the legacy sidecar pattern: the collector starts
# together with the app, in an unspecified order, and cannot be restarted on
# its own. The app may therefore be writing log lines before anything is
# collecting them.
#
# Kubernetes 1.28+ lets an initContainer carry `restartPolicy: Always`, which
# makes it a native sidecar: it starts BEFORE the main containers and is
# managed as a sidecar for the life of the pod.
#
# Task:
# 1. Move the `logcollector` container into `spec.initContainers` and give it
#    `restartPolicy: Always`.
# 2. Do not change its image, its command, or the volume it mounts.
# 3. `spec.containers` must end up holding ONLY the `app` container - the
#    logcollector has to move, not be copied.
#
# The Deployment must still run: one ready replica, the app container and the
# logcollector both ready, and the shared emptyDir still mounted at /var/log
# in both of them.
#
# Check your work with:
#   kubectl -n sidecars get deploy legacy -o yaml
#   kubectl -n sidecars get pods
