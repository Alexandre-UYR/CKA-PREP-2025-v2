# 1. The ConfigMap, built from the files.
#
# --from-file takes a directory: every file in it becomes one key, named
# after the file, with the contents of the file as the value. The flag can be
# repeated, and a file with several lines gives one key with a multi-line
# value - it is not split up.
kubectl create namespace cfg --dry-run=client -o yaml | kubectl apply -f -
kubectl -n cfg create configmap colors --from-file=/tmp/cka-lab/colors/primary/

# Have a look at what you got. Five keys, and `black` holds two lines.
kubectl -n cfg get configmap colors -o yaml
# data:
#   black: |-
#     black
#     known as key
#   blue: blue
#   cyan: cyan
#   magenta: magenta
#   yellow: yellow

# `kubectl create` refuses to overwrite, so if the ConfigMap is already there:
#   kubectl -n cfg delete configmap colors
#   kubectl -n cfg create configmap colors --from-file=/tmp/cka-lab/colors/primary/

# 2. The Deployment.
#
# envFrom with a configMapRef imports EVERY key of the ConfigMap as an
# environment variable, named after the key. Five keys in, five environment
# variables out - there is no list of names to keep in step with the
# ConfigMap.
cat <<'EOF' | kubectl -n cfg apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cfg-app
  namespace: cfg
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cfg-app
  template:
    metadata:
      labels:
        app: cfg-app
    spec:
      containers:
        - name: app
          image: nginx
          envFrom:
            - configMapRef:
                name: colors
EOF

kubectl -n cfg rollout status deployment/cfg-app --timeout=120s

# 3. The live check.
kubectl -n cfg exec deploy/cfg-app -- printenv cyan
# cyan

# The other four behave the same way. `black` prints both of its lines:
kubectl -n cfg exec deploy/cfg-app -- printenv black
# black
# known as key

# Listing them all in one go, to see that every key made it across:
kubectl -n cfg exec deploy/cfg-app -- printenv
# HOSTNAME=cfg-app-...
# PATH=/usr/local/sbin:...
# cyan=cyan
# magenta=magenta
# yellow=yellow
# black=black
# known as key
# blue=blue

# The alternative to envFrom - five separate env entries, each with a
# configMapKeyRef - gives the same result, but the names are repeated by
# hand and a sixth key added to the ConfigMap would not show up.
