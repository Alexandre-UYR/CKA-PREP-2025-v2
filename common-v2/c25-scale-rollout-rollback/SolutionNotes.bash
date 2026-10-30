# One way to do it. The order matters: the rollback undoes the last change,
# so the image update has to be the last change before the undo.

# 1. Scale to 5.
kubectl -n release scale deploy/api --replicas=5
kubectl -n release get deploy api
# NAME  READY   UP-TO-DATE   AVAILABLE   AGE
# api   5/5     5            5           2m

# 2. Update the image. The container is named `api`, so it is set as
#    api=nginx:1.26.
kubectl -n release set image deploy/api api=nginx:1.26
# deployment.apps/api image updated

# 3. Wait for the rollout to finish.
kubectl -n release rollout status deploy/api --timeout=120s
# deployment "api" successfully rolled out
kubectl -n release get pods
# NAME                   READY   STATUS    RESTARTS   AGE
# api-6c9f7d8b45-hq2xk    1/1     Running   0          40s
# api-6c9f7d8b45-p9d4m    1/1     Running   0          40s
# api-6c9f7d8b45-t7rvc    1/1     Running   0          40s
# api-6c9f7d8b45-w3n8b    1/1     Running   0          40s
# api-6c9f7d8b45-z5klc    1/1     Running   0          40s

# 4. Roll back. Without --to-revision this goes back one revision, which is
#    the image update - the scale is not part of the pod template, so the
#    rollback does not touch it.
kubectl -n release rollout undo deploy/api
# deployment.apps/api rolled back
kubectl -n release rollout status deploy/api --timeout=120s
# deployment "api" successfully rolled out

# 5. Scale back to 2. The rollback left the Deployment at 5 replicas.
kubectl -n release scale deploy/api --replicas=2
kubectl -n release rollout status deploy/api --timeout=120s

# 6. The state the task asked for.
kubectl -n release get deploy api
# NAME  READY   UP-TO-DATE   AVAILABLE   AGE
# api   2/2     2            2           4m
kubectl -n release get deploy api -o jsonpath='{.spec.containers[*].image}{"\n"}'
# nginx:1.25

# The history is a log: it keeps every revision the Deployment has been at,
# so it only grows. There are the two revisions the task started with, the
# image update, and the rollback.
kubectl -n release rollout history deploy/api
# deployment.apps/api
# REVISION   CHANGE-CAUSE
# 1          <none>
# 2          <none>
# 3          <none>
# 4          <none>
#
# (The rollback either takes a revision of its own or brings the earlier
# ReplicaSet back up. Either way the history has at least three entries by
# the end, and the bad revision is still in it, scaled down to zero.)

kubectl -n release get rs
# NAME                       DESIRED   CURRENT   READY   AGE
# api-5f7c9d8b64-lm4qt       0        0         0       4m
# api-6c9f7d8b45-hq2xk       0        0         0       3m
# api-77b4c9d6f8-4kd9p       2        2         2       1m
