# Question: The four everyday volume types
#
# Task:
# In the `volumes` namespace, create a Pod named `all-volumes` (image
# nginx:1.25) with four volumes and one mount each:
#   - `tmp`  - an emptyDir volume,                      mounted at /tmp
#   - `cfg`  - the ConfigMap `app-config`,              mounted at /etc/config
#   - `sec`  - the Secret `app-secret`,                 mounted at /etc/secret
#   - `host` - a hostPath volume at /tmp/hostdata,      mounted at /host
#
# The Pod must run, and the mounts must really work:
#   kubectl -n volumes exec all-volumes -- ls /etc/config   # lists nginx.conf
#   kubectl -n volumes exec all-volumes -- ls /etc/secret   # is not empty
#   kubectl -n volumes exec all-volumes -- ls /tmp          # works
