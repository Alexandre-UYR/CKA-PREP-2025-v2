# Question: The tag that does not exist
#
# The Pod `app` in the `reg` namespace is in ImagePullBackOff - the image
# cannot be pulled.
#
# Task:
# 1. Work out which part of the image reference is wrong. The ConfigMap
#    `image-tags` in the same namespace lists the tags that DO exist, one key
#    per image.
# 2. Fix the Pod so that it starts. The Pod must end up Running, with its
#    container ready.
# 3. Do NOT change the ConfigMap.
#
# The Pod's events say why the pull failed, and that is where the wrong tag is
# named. `kubectl describe pod` is the tool for it.
