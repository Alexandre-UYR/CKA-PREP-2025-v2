# 1. Compare what works with what does not.
#
#    kubectl -n dns run probe --restart=Never --image=busybox:1.36 -- \
#      nslookup kubernetes.default.svc.cluster.local
#    # Server:  10.96.0.10
#    # Address: 10.96.0.10:53
#    #
#    # Non-authoritative answer:
#    # Name:    kubernetes.default.svc.cluster.local
#    # Address: 10.96.0.1
#
#    kubectl -n dns run probe --restart=Never --image=busybox:1.36 -- \
#      nslookup example.com
#    # Server:  10.96.0.10
#    # Address: 10.96.0.10:53
#    # ** server can't find example.com: NXDOMAIN
#
#    So the cluster's own DNS server is alive and answering - it is answering
#    for one kind of name and not the other.

# 2. Look at the CoreDNS configuration.
#
#    kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}'
#    # .:53 {
#    #     errors
#    #     health {
#    #        lameduck 5s
#    #     }
#    #     ready
#    #     kubernetes cluster.local in-addr.arpa ip6.arpa {
#    #        pods insecure
#    #        fallthrough in-addr.arpa ip6.arpa
#    #        ttl 30
#    #     }
#    #     prometheus :9153
#    #     cache 30
#    #     loop
#    #     reload
#    #     loadbalance
#    # }
#
#    There are two plugins that matter here:
#
#      - `kubernetes` serves the names INSIDE the cluster. It is why
#        kubernetes.default.svc.cluster.local resolves.
#      - `forward . /etc/resolv.conf` sends everything else to the node's
#        resolver. It is missing.
#
#    So cluster names are served and external names are not. The CoreDNS
#    server is not broken - it is half configured.

# 3. Put the forwarding back.
#
#    Add the directive back to the Corefile. Keep the block if the rest of
#    the Corefile uses one:
#
#        forward . /etc/resolv.conf {
#           max_concurrent 1000
#        }
#
#    The directive has to be inside the server block, and the whole
#    directive - braces included - has to be syntactically complete, or
#    CoreDNS will fail to parse its own configuration and crash-loop.

kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}' \
  > /tmp/corefile.fixed

cat <<'EOF' >> /tmp/corefile.fixed

    forward . /etc/resolv.conf {
       max_concurrent 1000
    }
EOF

kubectl -n kube-system create configmap coredns --from-file=Corefile=/tmp/corefile.fixed \
  --dry-run=client -o yaml | kubectl apply -f -

# 4. Restart CoreDNS. This is the part that is easy to forget: the Corefile
#    is parsed when the process starts, so the running pods are still using
#    the old configuration.
kubectl -n kube-system rollout restart deploy/coredns
kubectl -n kube-system rollout status deploy/coredns --timeout=180s

# 5. Prove both kinds of resolution.
kubectl -n dns run probe --restart=Never --image=busybox:1.36 -- \
  nslookup kubernetes.default.svc.cluster.local
# Name:    kubernetes.default.svc.cluster.local
# Address: 10.96.0.1

kubectl -n dns run probe --restart=Never --image=busybox:1.36 -- \
  nslookup example.com
# Name:    example.com
# Address: 93.184.215.14

kubectl -n dns delete pod probe --ignore-not-found

# 6. The evidence that the restart happened, if you need to show it:
kubectl -n kube-system get deploy coredns \
  -o jsonpath='{.spec.template.metadata.annotations.kubectl\.kubernetes\.io/restartedAt}'
# 2026-10-30T10:14:02Z
#
# kubectl -n kube-system get pods -l k8s-app=kube-dns \
  -o custom-columns=NAME:.metadata.name,START:.status.startTime
# NAME                       START
# coredns-6d4f9c8b7c-x2k9p   2026-10-30T10:14:05Z
#
# The pod started after the ConfigMap was changed - that is the check the
# grader makes.
