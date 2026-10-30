# 1. Install a metrics server. The upstream manifests are one file.
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# On a cluster with a self-signed kubelet certificate, metrics-server refuses
# to scrape and 'kubectl top' never answers. In that case patch the
# Deployment so that it trusts the kubelet:
#   kubectl -n kube-system patch deployment metrics-server --type=json \
#     -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

kubectl -n kube-system rollout status deployment metrics-server --timeout=120s

# 2. Wait for the numbers to arrive. The first requests answer 'no metrics
#    available' for a little while.
kubectl top nodes
# NAME       CPU(cores)   CPU%   MEMORY(bytes)   MEM%
# kind-worker            17m    1%    1205Mi          15%
# kind-worker2           21m    1%    1102Mi          14%
#
# The node the hog landed on carries the extra 64 MiB.

# 3. Write the busiest node down. The memory column has to be turned into one
#    unit first - 2Gi is bigger than 1205Mi, but it sorts before it as a
#    string.
kubectl top nodes --no-headers \
  | awk '{m=""; for(i=2;i<=NF;i++) if ($i ~ /^[0-9.]+(Ki|Mi|Gi|Ti)$/) {m=$i; break};
         if(m!="") {n=m+0; u=m; sub(/^[0-9.]+/,"",u);
                    if(u=="Ki") n=n/1024; else if(u=="Gi") n=n*1024; else if(u=="Ti") n=n*1048576;
                    print n, $1}}' \
  | sort -k1 -g | tail -n 1 | awk '{print $2}' > /root/busiest-node.txt

cat /root/busiest-node.txt
# kind-worker2

# 4. The hungriest Pod in the namespace. Note that the Pod name is not the
#    Deployment name.
kubectl top pods -n metrics
# NAME                          CPU(cores)   MEMORY(bytes)
# calm-one-6d4c7f9b8b-2qz4k     0m           1Mi
# calm-two-58f9c6d4b7-x8r2m     0m           1Mi
# hog-7d9f4c8b6-2xk4p           0m           71Mi

kubectl top pods -n metrics --no-headers \
  | awk '{m=""; for(i=2;i<=NF;i++) if ($i ~ /^[0-9.]+(Ki|Mi|Gi|Ti)$/) {m=$i; break};
         if(m!="") {n=m+0; u=m; sub(/^[0-9.]+/,"",u);
                    if(u=="Ki") n=n/1024; else if(u=="Gi") n=n*1024; else if(u=="Ti") n=n*1048576;
                    print n, $1}}' \
  | sort -k1 -g | tail -n 1 | awk '{print "metrics/" $2}' > /root/hottest-pod.txt

cat /root/hottest-pod.txt
# metrics/hog-7d9f4c8b6-2xk4p

# 5. Both files, and the answer:
cat /root/busiest-node.txt /root/hottest-pod.txt
# kind-worker2
# metrics/hog-7d9f4c8b6-2xk4p
