# Question: Expand a PersistentVolumeClaim
#
# Task:
# In the resize namespace:
#
# 1. Create a PersistentVolume named expand-pv:
#      - 100Mi of storage
#      - access mode ReadWriteOnce
#      - a hostPath volume at /tmp/expand-data
#      - storageClassName: expandable
#
# 2. Create a PersistentVolumeClaim named expand-pvc that binds to it:
#      - 10Mi of storage
#      - access mode ReadWriteOnce
#      - storageClassName: expandable
#
# 3. Expand the claim to 70Mi. The expansion must actually take effect, not
#    just be edited into the spec.
