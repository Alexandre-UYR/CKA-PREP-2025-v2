# Question: Take the pods over from their old owner
#
# The Deployment `web` was deleted in namespace `adopt` and left its
# ReplicaSet and its two running pods behind. The pods are still Running and
# still controlled by the orphaned ReplicaSet.
#
# Task:
# 1. Create a ReplicaSet `web-adopted` in namespace `adopt` with 2 replicas,
#    whose selector matches those pods.
# 2. Make the EXISTING pods belong to `web-adopted` rather than to the old
#    ReplicaSet. The pods must be ADOPTED, not replaced - the same pods, with
#    the same names and the same UIDs, must end up running under
#    `web-adopted`.
# 3. The two pods must end up Running and controlled by `web-adopted`, and
#    the old ReplicaSet must no longer own them.
#
# There is one trap in here: a ReplicaSet only adopts a pod that has no
# controller, so the old owner has to let go of the pods first.
