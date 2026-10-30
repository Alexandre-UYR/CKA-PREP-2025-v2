# Question: Dynamic provisioning with a StorageClass
#
# Task:
# Create a StorageClass named `fast` with:
#   - provisioner: rancher.io/local-path
#   - volumeBindingMode: WaitForFirstConsumer
# and make it the default StorageClass for the cluster.
#
# Then, in the `provisioning` namespace, create a PersistentVolumeClaim named
# `data`. The claim must NOT name a StorageClass - it has to pick up the new
# default by itself.
#
# Also create a Pod named `writer` in the same namespace that mounts that
# claim at /data.
#
# The claim must end up in the Bound phase.
