# Question: The same Secret, two ways
#
# The Secret `app-secret` in the `secrets` namespace holds two keys:
# `username` and `password`. Nothing else is in the namespace.
#
# Task:
# 1. Create a Deployment `secret` in the `secrets` namespace, image nginx,
#    that exports BOTH keys of the Secret `app-secret` as environment
#    variables AND mounts both keys as files under /etc/secret.
# 2. Then show it working: the variables from inside the pod, and the files
#    from inside the pod.
#
# The values must come from the Secret. Do not hard-code them.
