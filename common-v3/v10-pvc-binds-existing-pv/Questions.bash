# Question: The claim that will not bind
#
# The PVC `data` in the `bind` namespace will not bind. A PersistentVolume
# `data-pv` exists and is Available - 500Mi, ReadWriteOnce, storage class
# `fast`, and it has data on it.
#
# Task:
# 1. Work out why the claim will not bind to it. Look at the claim and at the
#    volume: the access modes and the size are not the problem.
# 2. Make it bind.
# 3. You must NOT delete the PersistentVolume: it has data on it that has to
#    survive. Deleting and re-creating the claim is allowed.
#
# The volume is not broken and the cluster is not busy: read the claim, read
# the volume, and compare the two.
