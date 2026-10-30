# Question: Two rules that contradict each other
#
# Nothing can be created in the `conflict` namespace. A Pod that states no
# resources of its own is refused, and so is one that states too much: the
# defaults the namespace applies to every container are larger than the quota
# allows.
#
# Task:
# 1. Work out which two objects are fighting each other, and how.
# 2. Create a Pod `fits` in the `conflict` namespace that the API server
#    ACCEPTS, with resources that fit inside the quota.
# 3. You may NOT change the ResourceQuota, and you may NOT change the
#    LimitRange. Both of them have to be exactly as they are.
#
# The Pod must be Running with its container ready when you are done.
