# Question: Kill the old pods before you make the new ones
#
# The Deployment `proxy` in the `cka4` namespace runs 6 replicas of
# nginx:1.28 and its pods carry `app=proxy`.
#
# Two things are wrong with it.
#
# Task:
# 1. When the Deployment is updated, the old pods must be killed off BEFORE
#    the new ones are created. Change the update strategy so that is what
#    happens.
# 2. The Deployment itself must carry the label `client=user`. The PODS keep
#    `app=proxy` - do not rename the pods' labels to satisfy the requirement
#    in step 2.
# 3. Save the corrected spec to /root/q4.yaml and apply it.
#
# The Deployment must be edited in place. Do not delete it and create a new
# one: its UID has to stay the same.
