# 1. Look at the Deployment.
kubectl -n rollout get deploy web
# NAME   READY   UP-TO-DATE   AVAILABLE   AGE
# web    3/3     0            3           10m

# Three ready replicas, zero up to date: the pods are the OLD ones, and the new
# template has never been rolled out.

kubectl -n rollout get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
# nginx:1.26

kubectl -n rollout get pods -l app=web -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{"\n"}{end}'
# web-6b9f7c5d4-h2xq   nginx:1.25
# web-6b9f7c5d4-p7kl   nginx:1.25
# web-6b9f7c5d4-zq4n   nginx:1.25

# 2. The describe output says why.
kubectl -n rollout describe deploy web
# ...
# StrategyType:           RollingUpdate
# RollingUpdateStrategy:  25% max unavailable, 25% max surge
# Paused:                 true
# Conditions:
#   Type           Status  Reason
#   ----           ------  ------
#   Available      True    MinimumReplicasAvailable
#   Progressing    False   DeploymentPaused
#   Progressing    False   DeploymentPaused

kubectl -n rollout get deploy web -o jsonpath='{.spec.paused}{"\n"}'
# true

# A paused Deployment does not roll out a changed pod template. The controller
# only synchronises the status; it never creates the new ReplicaSet.

# 3. The wrong turn, worth ruling out: the rolling update strategy.
kubectl -n rollout get deploy web -o jsonpath='{.spec.strategy}{"\n"}'
# map[rollingUpdate:map[maxSurge:25% maxUnavailable:25%] type:RollingUpdate]

# maxSurge is how many pods MAY be created above the desired count and
# maxUnavailable is how many may be unavailable. With BOTH at zero the
# controller is not allowed to create the new pod and not allowed to delete the
# old one, so the rollout would be deadlocked - a rolling update needs one of
# the two to be non-zero. But the API server will not let you set them both to
# zero:
kubectl -n rollout patch deploy web --type=merge \
  -p '{"spec":{"strategy":{"rollingUpdate":{"maxSurge":0,"maxUnavailable":0}}}}'
# The Deployment "web" is invalid: spec.strategy.rollingUpdate.maxUnavailable:
#   Invalid value: 0: may not be 0 when `maxSurge` is 0

# So the strategy is not what is stopping this rollout.

# 4. The fix: resume the rollout.
kubectl -n rollout rollout resume deploy/web
# deployment.apps/web resumed

# ... which is the same as:
kubectl -n rollout patch deploy web --type=merge -p '{"spec":{"paused":false}}'

# 5. Watch it finish.
kubectl -n rollout rollout status deploy/web --timeout=180s
# deployment "web" successfully rolled out

kubectl -n rollout get deploy web
# NAME   READY   UP-TO-DATE   AVAILABLE   AGE
# web    3/3     3            3           3m

kubectl -n rollout get pods -l app=web -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{"\n"}{end}'
# web-6b9f7c5d4-4hbm   nginx:1.26
# web-6b9f7c5d4-9ktv   nginx:1.26
# web-6b9f7c5d4-wr6d   nginx:1.26

# The Deployment was never deleted, so it kept its UID.
kubectl -n rollout get deploy web -o jsonpath='{.metadata.uid}{"\n"}'
# 8f2c1d54-3b6e-4a19-9c7d-2e5f6a8b0c1d
