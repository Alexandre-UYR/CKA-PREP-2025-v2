# Question: Which one sees the new value?
#
# The Secret `app-secret` in namespace `rot` has been rotated. Its TOKEN key now
# holds `new-value`.
#
# The Deployment `app` reads that secret twice: once as the environment variable
# TOKEN, and once as the file /etc/secret/TOKEN.
#
# Task:
# 1. Work out which of the two picks up the new value on its own, and which one
#    does not. Check BOTH from inside the container:
#      cat /etc/secret/TOKEN
#      printenv TOKEN
#    The mounted file is refreshed by the kubelet, on its own schedule - it can
#    take up to about two minutes. Do not conclude that it did not update before
#    you have waited for it.
# 2. Make sure the pod is serving the NEW value from inside the container.
# 3. Leave the Deployment wired to the Secret. TOKEN must still come from a
#    secretKeyRef on `app-secret`, and the Secret must still be mounted at
#    /etc/secret. Do not hard-code the value anywhere.
