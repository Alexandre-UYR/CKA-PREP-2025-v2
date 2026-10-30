# Question: The same pods, three ways
#
# The Deployment `website` in namespace `reports` has 5 replicas, and its pods
# are named website-<something>.
#
# Task:
# 1. Write the pods that make up the Deployment to /root/q6a.txt, SORTED BY
#    POD IP, showing the pod NAME and the LABELS.
# 2. Write the same pods to /root/q6b.txt, showing only the NAME and the
#    PHASE.
#
# Both files have to be produced with `kubectl -o custom-columns`. Do not type
# the pod names by hand. The first file must carry the labels; the second must
# NOT.
