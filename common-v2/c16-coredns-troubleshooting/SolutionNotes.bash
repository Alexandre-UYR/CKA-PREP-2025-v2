# The diagnosis.
#
# 1. Look at the pods. CoreDNS is the pod that serves cluster service names,
#    so start there:
#
#      kubectl -n kube-system get pods -l k8s-app=kube-dns
#      kubectl -n kube-system logs deploy/coredns
#
#    The logs say exactly what is wrong:
#
#      plugin/kubernetes: plugin error: 2:1: ... : unknown directive
#      ... Corefile:2 - Error during parsing: unknown plugin 'kubernetesBROKEN'
#
# 2. Look at the configuration that CoreDNS reads:
#
#      kubectl -n kube-system get configmap coredns -o yaml
#      kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}'
#
#    The Corefile names a plugin that does not exist.

# The fix: put the kubernetes plugin back, then restart the Deployment so the
# pods pick the corrected Corefile up. CoreDNS reads its Corefile at
# start-up - editing the ConfigMap alone does not change the running process.

kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}' \
  | sed 's/kubernetesBROKEN/kubernetes/' > /tmp/coredns-corefile.fixed

kubectl -n kube-system create configmap coredns \
  --from-file=Corefile=/tmp/coredns-corefile.fixed \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n kube-system rollout restart deploy/coredns
kubectl -n kube-system rollout status deploy/coredns --timeout=180s

# The verify.
kubectl -n dns run dnsprobe --rm -i --restart=Never --image=busybox:1.36 -- \
  nslookup kubernetes.default.svc.cluster.local
# Server:		10.96.0.10
# Address:	10.96.0.10:53
#
# Non-authoritative answer:
# Name:	kubernetes.default.svc.cluster.local
# Address: 10.96.0.1

# The same check from any pod, or from the node:
kubectl -n kube-system run dnsprobe --rm -i --restart=Never --image=busybox:1.36 -- \
  nslookup kubernetes.default.svc.cluster.local

# Clean the probe pods up.
kubectl -n dns delete pod dnsprobe --ignore-not-found
kubectl -n kube-system delete pod dnsprobe --ignore-not-found

# If the original Corefile is what you want back, and you took a copy of it
# before you broke anything:
#
#   kubectl -n kube-system create configmap coredns --from-file=Corefile=./Corefile.bak \
#     --dry-run=client -o yaml | kubectl apply -f -
#   kubectl -n kube-system rollout restart deploy/coredns
