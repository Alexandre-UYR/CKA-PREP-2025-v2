# Question: Cluster names work, the internet does not
#
# Pods in the `dns` namespace can resolve `kubernetes.default.svc.cluster.local`
# perfectly well, but they cannot resolve anything outside the cluster.
#
# Task:
# 1. Diagnose the difference.
# 2. Fix the cluster's DNS so that external names resolve too. Remember that
#    CoreDNS reads its configuration at start-up — changing the ConfigMap is
#    not enough on its own.
# 3. Verify BOTH kinds of resolution from a pod: a cluster service name and
#    an external name.
