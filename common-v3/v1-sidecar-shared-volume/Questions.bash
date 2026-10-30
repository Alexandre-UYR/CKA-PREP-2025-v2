# Question: A log nobody can read
#
# The `web` Deployment in namespace `sidecar` writes its log to
# /var/log/app.log, but nobody can read it: the file lives inside the
# container's own filesystem, so it disappears on every restart and no other
# container could see it anyway.
#
# Task:
# 1. Add a sidecar container named `logreader` (image busybox:1.36) that tails
#    /var/log/app.log.
# 2. Mount a shared volume `shared-logs` (emptyDir) at /var/log in BOTH the
#    app container and the sidecar, so the log is shared and survives a
#    restart.
# 3. The app container must keep writing to the same path.
#
# The Deployment must end up with exactly two containers, one ready replica,
# and the log must actually be readable from the sidecar:
#
#   kubectl -n sidecar exec deploy/web -c logreader -- cat /var/log/app.log
#
# has to print the app's log lines. If the app is still writing into the
# container layer instead of the shared volume, that command shows nothing.
