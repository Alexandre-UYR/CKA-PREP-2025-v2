# Question: The app that is killed before it starts
#
# The `slow` Deployment in namespace `probe` is restarted over and over and
# never becomes Ready. The application needs 60 seconds to start.
#
# Task:
# 1. Find the probe that is killing it.
# 2. Fix it so the container is allowed to finish starting: add a startupProbe
#    that gives it enough time, and make sure the liveness probe no longer
#    fires while the app is still starting.
# 3. The pod must end up Running and Ready, and it must STAY up - check the
#    restart count, not just the phase.
#
# Watch the arithmetic: a startup probe is allowed
#
#   failureThreshold x periodSeconds
#
# seconds to succeed, and the kubelet restarts the container if it has not
# succeeded within that budget. That budget has to cover the application's
# 60-second start-up.
