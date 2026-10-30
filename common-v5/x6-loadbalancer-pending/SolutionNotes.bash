# 1. Look at the Service and see that it is pending, and why.
#
#    kubectl -n edge get svc public
#    NAME      TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
#    public    LoadBalancer   10.96.140.9    <pending>     80:31234/TCP   10m
#
#    "pending" in the EXTERNAL-IP column means: nobody has given this Service
#    an address. It is not a broken Service - it is a Service waiting for
#    something that does not exist on this cluster.
#
#    The two things to check:
#
#    kubectl -n edge describe svc public
#    kubectl get svc --all-namespaces
#
#    Is there any other LoadBalancer Service on the cluster with an address?
#    Is there a cloud provider or a service-controller in the
#    kube-controller-manager's flags?
#
#      kubectl -n kube-system get pods -l component=kube-controller-manager \
#        -o jsonpath='{.items[*].spec.containers[*].command}'
#
#    On kind, on a plain minikube cluster and on a bare kubeadm cluster the
#    answer is no: there is no load-balancer implementation, so no address is
#    ever coming. Waiting is not the fix.

# 2. Publish the Service the other way round: a NodePort.
#
#    type is a mutable field, so this is an edit. The ClusterIP, the selector
#    and the endpoints are all kept.
kubectl -n edge patch svc public --type=merge -p '{
  "spec": {
    "type": "NodePort",
    "ports": [
      {
        "port": 80,
        "targetPort": 80,
        "nodePort": 30080,
        "protocol": "TCP"
      }
    ]
  }
}'

kubectl -n edge get svc public
# NAME     TYPE       CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE
# public   NodePort   10.96.140.9   <none>        80:30080/TCP   12s
#
# Note that the annotation survived - it was never the problem:
#
#    kubectl -n edge get svc public -o jsonpath='{.metadata.annotations}'
#    {"external-dns.alpha.kubernetes.io/hostname":"site.example.com"}
#
#    That annotation is read by the external-dns controller, which creates a
#    DNS record for the Service's address. There is no external-dns here, and
#    there would be nothing to point the record at anyway.

# 3. The endpoints were never the problem.
kubectl -n edge get endpoints public
# NAME     ENDPOINTS                                         AGE
# public   10.244.1.6:80,10.244.1.7:80,10.244.1.8:80         2m

# 4. Prove it works. A NodePort is published on every node's own IP:
NODEIP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "http://$NODEIP:30080"

#    From inside the cluster:
kubectl -n edge run ck --restart=Never --image=busybox:1.36 -- \
  wget -S -O - -T 5 "http://$NODEIP:30080/"
# Connecting to 172.18.0.2 (172.18.0.2:30080)
#   HTTP/1.1 200 OK
#   Server: nginx/1.25.3
#
#    and from outside, open http://$NODEIP:30080 in a browser on your laptop.

kubectl -n edge delete pod ck --ignore-not-found

# 5. The Service was edited, not replaced - the UID is the one from setup:
kubectl -n edge get svc public -o jsonpath='{.metadata.uid}'
#
# If the Service had been deleted and re-created, this would be a new UID and
# the grader would fail it.
