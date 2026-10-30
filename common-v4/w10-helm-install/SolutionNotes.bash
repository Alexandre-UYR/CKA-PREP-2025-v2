# 1. The namespace. Helm does not create it for you.
kubectl create namespace apps

# 2. The install.
helm install hello /tmp/cka-lab/charts/hello-world -n apps

# What did that give us? One replica, because that is what the chart's own
# values.yaml says.
kubectl -n apps get deploy
# NAME         READY   UP-TO-DATE   AVAILABLE   AGE
# hello-world  1/1     1            1           20s

# 3. The replica count has to change without the chart changing, so it comes
#    from a values file. The key is the one the template reads -
#    {{ .Values.replicaCount }} - so the file holds that key, as YAML.
cat > /root/hello-values.yaml <<'EOF'
replicaCount: 3
EOF

#    Check the file before installing it. `helm template` renders the chart
#    without touching the cluster, so this costs nothing and changes nothing.
helm template hello /tmp/cka-lab/charts/hello-world -f /root/hello-values.yaml

#    The rendered Deployment must say three replicas. If it still says one,
#    the file is not in a shape the chart can read: `replicaCount=3` on one
#    line, or the key nested under something else, would both leave the
#    chart showing its own default.

# 4. Install using the file. The release name `hello` is taken now, so this
#    is an upgrade rather than a second install:
helm upgrade hello /tmp/cka-lab/charts/hello-world -n apps -f /root/hello-values.yaml
#    `helm upgrade --install ...` does both steps in one command, and is what
#    you want if you are not sure whether the release is already there.

# 5. The result.
helm list -n apps
# NAME    NAMESPACE   REVISION    UPDATED             STATUS      CHART       APP VERSION
# hello   apps        2           2025-01-01 10:00:00  deployed    hello-world 1.25.0

kubectl -n apps get deploy
# NAME         READY   UP-TO-DATE   AVAILABLE   AGE
# hello-world  3/3     3            3           25s

kubectl -n apps rollout status deployment/hello-world --timeout=120s

# The chart on disk is still the chart the setup wrote:
cat /tmp/cka-lab/charts/hello-world/values.yaml
# replicaCount: 1
# image: nginx:1.25
#
# The chart's own values.yaml is untouched. The override lives in
# /root/hello-values.yaml, which is what the task asked for.
