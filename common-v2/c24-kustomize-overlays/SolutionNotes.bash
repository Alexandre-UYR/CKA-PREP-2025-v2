# One way to do it. The `images:` and `replicas:` transformers are the short
# way; a strategic merge patch does the same job.

# ---- the dev overlay ----
mkdir -p /tmp/cka-lab/kustomize/overlays/dev

cat > /tmp/cka-lab/kustomize/overlays/dev/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# The base is referenced with a relative path, resolved from this directory.
resources:
  - ../../base

images:
  - name: nginx
    newTag: "1.25"

replicas:
  - name: app
    count: 1
EOF

# ---- the prod overlay ----
mkdir -p /tmp/cka-lab/kustomize/overlays/prod

cat > /tmp/cka-lab/kustomize/overlays/prod/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

images:
  - name: nginx
    newTag: "1.26"

replicas:
  - name: app
    count: 3
EOF

# The same thing written as a strategic merge patch. Note that the patch has
# to name the kind AND the name of the object it patches - a patch that
# names the wrong one is silently ignored.
#
#   cat > /tmp/cka-lab/kustomize/overlays/dev/kustomization.yaml <<'EOF'
#   apiVersion: kustomize.config.k8s.io/v1beta1
#   kind: Kustomization
#   resources:
#     - ../../base
#   patches:
#     - patch: |
#         - op: replace
#           path: /spec/replicas
#           value: 1
#         - op: replace
#           path: /spec/template/spec/containers/0/image
#           value: nginx:1.25
#       target:
#         kind: Deployment
#         name: app
#   EOF

# ---- build both overlays and read what came out ----
kubectl kustomize /tmp/cka-lab/kustomize/overlays/dev
# apiVersion: apps/v1
# kind: Deployment
# metadata:
#   labels:
#     app: app
#   name: app
# spec:
#   replicas: 1
#   ...
#       containers:
#       - image: nginx:1.25
#         name: app
#         ...

kubectl kustomize /tmp/cka-lab/kustomize/overlays/prod
# apiVersion: apps/v1
# kind: Deployment
# metadata:
#   labels:
#     app: app
#   name: app
# spec:
#   replicas: 3
#   ...
#       containers:
#       - image: nginx:1.26
#         name: app
#         ...

# ---- apply the dev overlay to the cluster ----
kubectl apply -k /tmp/cka-lab/kustomize/overlays/dev
# deployment.apps/app configured
# service/app unchanged

kubectl -n default get deploy app
# NAME  READY   UP-TO-DATE   AVAILABLE   AGE
# app   1/1     1            1           20s
kubectl -n default get pods
# NAME                        READY   STATUS    RESTARTS   AGE
# app-7c9f6b4d8c-x2k9p         1/1     Running   0          20s

# The prod overlay is only built, not applied.
