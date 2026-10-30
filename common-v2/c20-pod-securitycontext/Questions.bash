# Question: Run a Pod with restricted privileges
#
# Task:
# In the secure namespace, create a Pod named restricted that:
#   - runs as the user 1000 (runAsUser: 1000)
#   - refuses to run as root (runAsNonRoot: true)
#   - drops ALL Linux capabilities (capabilities.drop: ["ALL"])
#   - forbids privilege escalation (allowPrivilegeEscalation: false)
#   - uses the RuntimeDefault seccomp profile
#
# Do not add any capability back. The Pod must run.
