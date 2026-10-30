# Question: Guaranteed, not Burstable
#
# The Deployment `mixed` in the `qos` namespace is running, but its pod is in
# the `Burstable` QoS class. It needs to be in the `Guaranteed` class.
#
# Task:
# 1. Work out why the pod is Burstable. The Deployment's manifest is not the
#    whole story - something else in the namespace is filling in the resource
#    settings for you.
# 2. Fix the Deployment so that the pod's `.status.qosClass` reports
#    `Guaranteed`.
# 3. For the pod to be Guaranteed, EVERY container - the main one AND the init
#    container - must set CPU and memory requests EQUAL to their limits.
# 4. Keep the resource values sensible: the init container's limits must not
#    exceed the main container's.
#
# The QoS class lives on the pod, not on the Deployment:
#   kubectl -n qos get pod -l app=mixed -o jsonpath='{.items[0].status.qosClass}'
