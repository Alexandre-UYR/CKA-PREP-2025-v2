# Question: Take a copy of the cluster's brain
#
# Everything the cluster knows - every Pod, Service, Secret and ConfigMap - is
# stored in etcd. If etcd is lost, the cluster is lost with it, and the only
# way back is the backup nobody took.
#
# Task:
# 1. Take a snapshot of the etcd database and save it in your home directory
#    as `snapshotdb`.
# 2. The cluster's etcd is TLS-protected, so you will need the CA certificate,
#    the client certificate and the client key as well as the endpoint.
# 3. Do NOT stop the control plane to do it.
#
# When you are done the snapshot has to be a real one:
# `etcdutl snapshot status ~/snapshotdb`
# (or `ETCDCTL_API=3 etcdctl snapshot status ~/snapshotdb`)
# has to succeed against it and report a non-zero revision count.
