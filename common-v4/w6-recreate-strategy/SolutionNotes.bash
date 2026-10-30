# 1. The two changes, straight onto the object.
#
#    --type='merge' is a JSON merge patch. It replaces the whole `strategy`
#    object, which is what we want: the API server refuses a Recreate strategy
#    that still carries a rollingUpdate block, and a strategic merge patch
#    (the default) would leave that block behind and get the update rejected.
#
#    The label goes on the Deployment's own metadata, not on the pod template.

kubectl -n cka4 patch deployment proxy --type='merge' -p \
  '{"metadata":{"labels":{"client":"user"}},"spec":{"strategy":{"type":"Recreate"}}}'

# 2. Save the corrected spec.
kubectl -n cka4 get deployment proxy -o yaml > /root/q4.yaml

# Have a look at what you wrote. The two things you care about are the label
# under metadata.labels and the strategy type.
kubectl -n cka4 get deployment proxy -o jsonpath='{.metadata.labels}{"\n"}{.spec.strategy}{"\n"}'
# map[app:proxy client=user]
# map[rollingUpdate:map[maxSurge:25% maxUnavailable:25%] type:RollingUpdate]

# 3. Apply the file. The UID is the same as it was - this is an update, not a
#    replacement.
kubectl apply -f /root/q4.yaml

kubectl -n cka4 get deployment proxy -o jsonpath='{.metadata.uid}{" "}{.metadata.labels}{" "}{.spec.strategy.type}{" "}{.spec.template.metadata.labels}{"\n"}'
# 6f2c1a80-.... map[app:proxy client=user] Recreate map[app:proxy]

kubectl -n cka4 rollout status deployment/proxy --timeout=120s

# The alternative, if you would rather work in the file: take the spec, edit
# it, and apply it. Watch two things.
#
#   a) delete the whole rollingUpdate block under spec.strategy - the API
#      server refuses a Recreate strategy that still has one:
#
#        spec:
#          strategy:
#            rollingUpdate:      <-- delete these two lines and the one above
#              maxSurge: 25%
#              maxUnavailable: 25%
#            type: RollingUpdate  <-- becomes: type: Recreate
#
#   b) apply it straight away. The dump carries metadata.resourceVersion, and
#      the Deployment controller bumps that every time it updates the status,
#      so an old dump can fail with "the object has been modified".
#
# kubectl -n cka4 get deployment proxy -o yaml > /root/q4.yaml
# vi /root/q4.yaml
# kubectl apply -f /root/q4.yaml
#
# And a third way, which also keeps the file honest - patch, then take the
# file from the patched object:
#
# kubectl -n cka4 patch deployment proxy --type='merge' -p \
#   '{"metadata":{"labels":{"client":"user"}},"spec":{"strategy":{"type":"Recreate"}}}'
# kubectl -n cka4 get deployment proxy -o yaml > /root/q4.yaml
# kubectl apply -f /root/q4.yaml
