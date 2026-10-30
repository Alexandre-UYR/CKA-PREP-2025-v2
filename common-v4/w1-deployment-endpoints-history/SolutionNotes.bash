# 1. The Service's endpoints, as JSON.
#
# The endpoints of a Service are the addresses of the pods its SELECTOR matches.
# Read them straight off the Service rather than trying to work them out.
kubectl -n cache get endpoints cache -o json > /root/q3.json

# Have a look at what you wrote - it should hold a list of addresses under
# "subsets", not a table.
kubectl -n cache get endpoints cache -o json | head -20

# 2. Scale to 5 and wait for the rollout.
kubectl -n cache scale deployment cache --replicas=5
kubectl -n cache rollout status deployment/cache --timeout=120s

# 3. The rollout history.
kubectl -n cache rollout history deployment/cache > /root/q3.txt
cat /root/q3.txt
# deployment.apps/cache
# REVISION    CHANGE-CAUSE
# 1           <none>
# 2           <none>

# 4. The Service must still be pointing at the pods.
kubectl -n cache get svc cache
# NAME    TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
# cache   NodePort   10.96.183.42   <none>        11211:31234/TCP   30s

kubectl -n cache get endpoints cache -o jsonpath='{.subsets[*].addresses[*].ip}'
# 10.244.0.11
# 10.244.0.12
# 10.244.0.13
# 10.244.0.14
# 10.244.0.15
#
# Five addresses now. The file you wrote in step 1 holds three, because that is
# what it was when you wrote it - which is exactly why the order of the task
# matters. Re-run the first command if you want the file to match the Service
# as it is now.

# A one-liner that gets both the count and the file right in the right order:
kubectl -n cache scale deployment cache --replicas=5
kubectl -n cache rollout status deployment/cache --timeout=120s
kubectl -n cache get endpoints cache -o json > /root/q3.json
kubectl -n cache rollout history deployment/cache > /root/q3.txt
