# Question: Count the nodes that are actually usable
#
# Task:
# Count the nodes in the cluster that are Ready AND schedulable, EXCLUDING the
# control-plane node - the one tainted
# node-role.kubernetes.io/control-plane:NoSchedule
#
# Write just the number into /root/ready-nodes.txt. Nothing else in the file.
#
# Show the command you used.
