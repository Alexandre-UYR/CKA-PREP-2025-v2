# Question: A volume that belongs to one Pod
#
# The `ephem` namespace is empty. The cluster has a default StorageClass.
#
# Task:
# 1. Create a Pod `eph` in the `ephem` namespace with a generic ephemeral
#    volume: a volume named `work`, whose `ephemeral.volumeClaimTemplate`
#    asks for 500Mi and ReadWriteOnce, mounted at `/work`.
# 2. Prove that the volume belongs to the Pod: while the Pod runs, a
#    PersistentVolumeClaim exists, and that claim is owned by the Pod - not by
#    the namespace.
#
# An ephemeral volume is created for the Pod and destroyed with it. You do
# not create the claim yourself, and you do not delete it yourself.
