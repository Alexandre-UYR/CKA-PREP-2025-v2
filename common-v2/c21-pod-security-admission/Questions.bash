# Question: Enforce the restricted Pod Security Standard
#
# Task:
# 1. Make the namespace psa-test ENFORCE the `restricted` Pod Security
#    Standard.
# 2. Create a Pod named compliant in namespace psa-test that satisfies that
#    standard: runAsNonRoot: true, a runAsUser that is not 0,
#    allowPrivilegeEscalation: false, the RuntimeDefault seccomp profile, and
#    all capabilities dropped.
# 3. Show that a Pod which violates the standard is rejected by the API
#    server.
