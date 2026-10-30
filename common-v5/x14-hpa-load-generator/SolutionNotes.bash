# 1. Install the metrics server.
#
#    The autoscaler reads the metrics API (metrics.k8s.io), not the kubelet.
#    Nothing serves that API until metrics-server is running.
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# On kind, minikube and most other local clusters the kubelet's serving
# certificate is self-signed, so metrics-server has to be told to trust it.
kubectl -n kube-system patch deployment metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args","value":["--cert-dir=/tmp","--secure-port=10250","--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname","--kubelet-use-node-status-port","--kubelet-insecure-tls"]}]'

kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s

# The APIService has to become Available, and the API has to answer.
kubectl get apiservice v1beta1.metrics.k8s.io
# NAME                     SERVICE                     AVAILABLE   AGE
# v1beta1.metrics.k8s.io   metrics-server/metrics-server   True     30s

kubectl get --raw /apis/metrics.k8s.io/v1beta1/pods | head -c 200
# {"kind":"PodMetricsList","apiVersion":"metrics.k8s.io/v1beta1","metadata":{},...

# 2. The HorizontalPodAutoscaler.
#
#    'kubectl autoscale' is the short way round; the manifest is the same
#    object. The target is 50% of the container's CPU REQUEST (200m), so the
#    autoscaler will scale out once the pods average more than 100m of CPU.
kubectl -n autoscale autoscale deployment hpa-example \
  --name=hpa --min=1 --max=10 --cpu-percent=50

# ... which is:
#
# apiVersion: autoscaling/v2
# kind: HorizontalPodAutoscaler
# metadata:
#   name: hpa
#   namespace: autoscale
# spec:
#   scaleTargetRef:
#     apiVersion: apps/v1
#     kind: Deployment
#     name: hpa-example
#   minReplicas: 1
#   maxReplicas: 10
#   metrics:
#     - type: Resource
#       resource:
#         name: cpu
#         target:
#           type: Utilization
#           averageUtilization: 50

kubectl -n autoscale get hpa hpa
# NAME   REFERENCE                       TARGET        MINPODS   MAXPODS   REPLICAS   AGE
# hpa    Deployment/hpa-example/scale   0%/50%        1         10        1          15s

# 3. The load generator.
#
#    The Service is called hpa-example and it is in the same namespace, so
#    the short name resolves: hpa-example -> hpa-example.autoscale.svc.cluster.local
kubectl -n autoscale run load-generator --image=busybox:1.28 --restart=Never \
  --command -- sh -c "while sleep 0.01; do wget -q http://hpa-example; done"

# 4. Watch it happen.
#
#    metrics-server needs a moment to produce its first samples, and the
#    autoscaler syncs every 15 seconds, so the scale-out takes a minute or
#    two rather than being instant.
kubectl -n autoscale get hpa hpa --watch
# NAME   REFERENCE                       TARGET        MINPODS   MAXPODS   REPLICAS   AGE
# hpa    Deployment/hpa-example/scale   305%/50%      1         10        1          2m
# hpa    Deployment/hpa-example/scale   305%/50%      1         10        4          2m

kubectl -n autoscale get deploy hpa-example
# NAME          READY   UP-TO-DATE   AVAILABLE   AGE
# hpa-example   4/4     4            4           3m

# If the TARGET column stays at 0%, the metrics API is not answering yet:
#   kubectl get apiservice v1beta1.metrics.k8s.io
#   kubectl -n kube-system logs deploy/metrics-server
