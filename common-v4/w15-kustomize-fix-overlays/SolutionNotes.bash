# 1. Why the dev overlay does nothing.
#
# Build it and look at what comes out:
kubectl kustomize /tmp/cka-lab/kustomize/overlays/dev
# error: no matches for Id Deployment.v1.apps/worker.[noNs]; failed to find
# unique target for patch Deployment.v1.apps/worker.[noNs]
#
# The message names the culprit: the patch is looking for a Deployment called
# "worker". Read the overlay's two files:
#
#   cat /tmp/cka-lab/kustomize/overlays/dev/kustomization.yaml
#   namespace: dev
#   resources:
#     - ../../base
#   patchesStrategicMerge:
#     - patch-deployment.yaml
#
#   cat /tmp/cka-lab/kustomize/overlays/dev/patch-deployment.yaml
#   apiVersion: apps/v1
#   kind: Deployment
#   metadata:
#     name: worker        <-- the base has no Deployment called "worker"
#
# A strategic merge patch is matched against the resources in the base by
# kind and name. Nothing is called "worker" in the base, so the patch never
# applies to anything: the build stops with the error above. (Older releases
# of kustomize ignored such a patch silently and printed the base unchanged -
# the same mistake, reported more quietly.)
#
# The fix: the patch has to name the resource it patches.
cat > /tmp/cka-lab/kustomize/overlays/dev/patch-deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: app
          image: nginx:1.25
EOF

# Build it again - now it changes something:
kubectl kustomize /tmp/cka-lab/kustomize/overlays/dev
#
# apiVersion: apps/v1
# kind: Deployment
# metadata:
#   labels:
#     app: app
#   name: app
#   namespace: dev
# spec:
#   replicas: 1
#   ...
#       containers:
#       - image: nginx:1.25
#         name: app
#
# (The build also prints a warning: `patchesStrategicMerge` is deprecated. The
# equivalent modern spelling is `patches:` with a `path:` entry. Both do the
# same thing.)
#
#   patches:
#     - path: patch-deployment.yaml
#
# 2. The prod overlay.
mkdir -p /tmp/cka-lab/kustomize/overlays/prod

cat > /tmp/cka-lab/kustomize/overlays/prod/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: prod

resources:
  - ../../base

patches:
  - target:
      kind: Deployment
      name: app
    patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: app
      spec:
        replicas: 3
        template:
          spec:
            containers:
              - name: app
                image: nginx:1.26
  - target:
      kind: Service
      name: app
    patch: |-
      apiVersion: v1
      kind: Service
      metadata:
        name: app
      spec:
        type: NodePort
EOF

# The prod overlay patches two different kinds, so it uses `patches` with an
# explicit target rather than the older `patchesStrategicMerge`.

# 3. Build both, then apply the dev one.
kubectl kustomize /tmp/cka-lab/kustomize/overlays/dev  | head -30
kubectl kustomize /tmp/cka-lab/kustomize/overlays/prod | head -30

# The namespace has to exist before anything can be applied into it.
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -k /tmp/cka-lab/kustomize/overlays/dev
kubectl -n dev rollout status deployment/app --timeout=120s

kubectl -n dev get deploy,svc
# NAME   READY   UP-TO-DATE   AVAILABLE   AGE
# app    1/1     1            1           20s
#
# NAME   TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
# app    ClusterIP   10.96.140.201   <none>        80/TCP         20s
#
# The prod overlay was built but not applied - the task only asks for the dev
# one to be applied.
