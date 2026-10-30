# 1. See what the name actually resolves to, from inside the cluster.
kubectl -n dns-demo exec looker -- nslookup redis-svc
# Server:		10.96.0.10
# Address:	10.96.0.10:53
#
# Non-authoritative answer:
# Name:	redis-svc.dns-demo.svc.cluster.local
# Address: 10.96.31.22
#
# The NAME resolves - to the Service's ClusterIP. That is CoreDNS answering
# from the Service object, and it happens whether or not the Service points
# at anything. So "the name resolves" is not the same as "the Service
# works".

# 2. Look at the Service and at its endpoints.
kubectl -n dns-demo get svc redis-svc -o jsonpath='{.spec.selector}'
# map[app:redis-v2]

kubectl -n dns-demo get endpoints redis-svc
# NAME       ENDPOINTS   AGE
# redis-svc  <none>      2m
#
# Nothing behind the ClusterIP. The endpoints of a Service are the pods its
# selector matches.

# 3. Compare with the pod's labels.
kubectl -n dns-demo get pods --show-labels
# NAME    READY   STATUS    RESTARTS   AGE   LABELS
# looker  1/1     Running   0          3m    app=looker
# redis   1/1     Running   0          3m    app=redis
#
# The Service asks for app=redis-v2; the pod is labelled app=redis. Nothing
# matches.

# 4. Fix the Service, in place.
kubectl -n dns-demo patch svc redis-svc -p '{"spec":{"selector":{"app":"redis"}}}'

kubectl -n dns-demo get endpoints redis-svc
# NAME       ENDPOINTS        AGE
# redis-svc  10.244.0.19      3m
#
# The endpoints controller takes a second or two to catch up.

# 5. Now take both addresses from nslookup, out of the looker pod.
kubectl -n dns-demo exec looker -- nslookup redis-svc | grep -A1 'Name:'
# Name:	redis-svc.dns-demo.svc.cluster.local
# Address: 10.96.31.22

kubectl -n dns-demo exec looker -- nslookup redis | grep -A1 'Name:'
# Name:	redis.dns-demo.pod.cluster.local
# Address: 10.244.0.19
#
# A Pod with a name gets a DNS name of its own, <pod>.<namespace>.pod.cluster.local,
# and its address is the Pod IP.

# 6. Write both to the file, one per line.
kubectl -n dns-demo exec looker -- nslookup redis-svc \
  | awk '/Address:/{print $2}' | tail -1 > /root/q5.txt
kubectl -n dns-demo exec looker -- nslookup redis \
  | awk '/Address:/{print $2}' | tail -1 >> /root/q5.txt

cat /root/q5.txt
# 10.96.31.22
# 10.244.0.19

# The `tail -1` matters: nslookup prints the DNS server's own address as well
# as the answer, and the two have to be told apart. The addresses above are
# the live ones - read them off the cluster rather than from this note, because
# they are different on every cluster.
#
# If you would rather not parse the nslookup output, the same two addresses
# come straight off the objects:
#
#   kubectl -n dns-demo get svc redis-svc -o jsonpath='{.spec.clusterIP}'
#   kubectl -n dns-demo get pod redis -o jsonpath='{.status.podIP}'
#
# but the task asks for the addresses as nslookup reports them, so run
# nslookup and check that what it says matches the objects.
