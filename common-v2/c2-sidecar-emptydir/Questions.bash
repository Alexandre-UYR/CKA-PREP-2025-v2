# Question: Sidecar sharing an emptyDir
#
# Task:
# In the sidecar namespace, the Deployment `app` is already running a single
# nginx container. Update the EXISTING Deployment `app` so that:
#   - it has a second container named `sidecar`
#   - that container uses the image busybox:stable
#   - it runs:
#       sh -c 'while true; do echo "$(date) app log line" >> /var/log/app.log; sleep 5; done'
#   - a volume named `logs` of type emptyDir is added to the pod
#   - that volume is mounted at /var/log in BOTH the nginx container and the
#     sidecar container
#
# The two containers must really share the file: once the rollout is done, the
# file /var/log/app.log must exist inside the sidecar container.
