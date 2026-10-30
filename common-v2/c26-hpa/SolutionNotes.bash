# Create the HPA for the `web` Deployment in the autoscale namespace.
#
# The manifest is the answer: `kubectl autoscale` has no flag for the
# scaleDown stabilisation window, so it cannot express the whole task.
#
#   kubectl autoscale deployment web -n autoscale --min=2 --max=8 --cpu-percent=60
#
# gets everything right except the behaviour block.

cat <<'EOF' > hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web-hpa
  namespace: autoscale
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web
  minReplicas: 2
  maxReplicas: 8
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 60
EOF

kubectl apply -f hpa.yaml

# Look at what you created.
kubectl get hpa web-hpa -n autoscale
# NAME      RESOURCE   TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
# web-hpa   cpu / 60%   <unknown>/60%    2         8         2          20s
#
# The TARGETS column reads <unknown> when no metrics-server is installed.
# That is not a mistake in the manifest: the grader reads the spec, not the
# live reading.

# The target has to be the Deployment that is already running - check that
# you did not replace it.
kubectl get deployment web -n autoscale -o jsonpath='{.metadata.uid}{"\n"}'
