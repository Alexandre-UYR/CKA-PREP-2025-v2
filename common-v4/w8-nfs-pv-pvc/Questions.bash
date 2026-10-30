# Question: A volume with something already on it
#
# The `web` namespace is empty. There is a PersistentVolume `pvvol` - 1Gi,
# ReadWriteMany, reclaim policy Retain, storage class "" - and it is
# Available. There is already a file on that volume.
#
# Task:
# 1. Create a PersistentVolumeClaim `pvc001` in the `web` namespace that
#    requests 200Mi and binds to the existing PV `pvvol`. Its access mode is
#    ReadWriteOnce, and its storage class must be the PV's own storage class,
#    so that the two agree.
# 2. Create a Deployment `web` that mounts the claim at /usr/share/nginx/html.
# 3. Create a Service `web` on port 80 in front of it.
# 4. The file that is already on the volume must be SERVED. Check it by
#    curling the Service.
#
# The claim must bind to the existing volume - do not create a new one, and do
# not change the PV.
