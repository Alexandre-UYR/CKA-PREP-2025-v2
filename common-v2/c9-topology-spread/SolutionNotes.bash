# The reference answer for c9.
#
# Two steps: add the constraint to the pod template, then scale up.

# ---- 1. the constraint ----
#
# kubectl patch with --type=merge replaces the whole
# topologySpreadConstraints list, which is what we want here.
#
# kubectl edit deployment spread -n topology works too: the constraint goes
# under spec.template.spec.topologySpreadConstraints.

kubectl -n topology patch deployment spread --type=merge -p '{
  "spec": {
    "template": {
      "spec": {
        "topologySpreadConstraints": [
          {
            "maxSkew": 1,
            "topologyKey": "kubernetes.io/hostname",
            "whenUnsatisfiable": "ScheduleAnyway",
            "labelSelector": {
              "matchLabels": {
                "app": "spread"
              }
            }
          }
        ]
      }
    }
  }
}'

# ---- 2. the scale-up ----

kubectl -n topology scale deployment spread --replicas=8

kubectl -n topology rollout status deployment/spread --timeout=180s

# ---- 3. where the pods ended up ----
#
# The distinct node names are what the check looks at.
kubectl -n topology get pods -l app=spread -o wide
# NAME                           READY   STATUS    RESTARTS   AGE   IP            NODE
# spread-6d9f7c8b45-h2k4t        1/1     Running   0          25s   10.244.1.8    worker-1
# spread-6d9f7c8b45-p9wlz        1/1     Running   0          25s   10.244.2.9    worker-2
# ...

kubectl -n topology get pods -l app=spread \
  -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort | uniq -c
#      4 worker-1
#      4 worker-2

# The constraint as the API server stores it:
kubectl -n topology get deployment spread \
  -o jsonpath='{.spec.template.spec.topologySpreadConstraints[0]}{"\n"}'
# {"labelSelector":{"matchLabels":{"app":"spread"}},"maxSkew":1,"topologyKey":"kubernetes.io/hostname","whenUnsatisfiable":"ScheduleAnyway"}

# If the pods were not spread, the usual reason is that the four pods that
# already existed were placed before the constraint was added. The scheduler
# does not move them; delete them and let the Deployment recreate them:
#
#   kubectl -n topology delete pods -l app=spread
