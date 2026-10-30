# One way to do it. Any route that ends with a deployed release, a healthy
# Deployment and a repaired chart is a correct answer.

# 1. Install the chart.
helm install broken /tmp/cka-lab/charts/broken-chart -n webapps
#
# NAME    NAMESPACE  REVISION  UPDATED  STATUS    CHART             APP VERSION
# broken  webapps    1         ...      deployed  broken-chart-0.1.0  1.0
#
# Helm says "deployed" and means it: the objects were created. It has not
# checked that any of them work.

# 2. Look at what Helm thinks, then look at the cluster.
helm status broken -n webapps
kubectl get pods -n webapps
# NAME                        READY   STATUS              RESTARTS   AGE
# broken-chart-6d8f7c9c4-v9x   0/1     ImagePullBackOff   0          20s
#
# The pod's own events say why:
kubectl describe pod -n webapps -l app.kubernetes.io/instance=broken
#   Warning  Failed  Failed to pull image "nginx:0.0.0-does-not-exist":
#   rpc error: code = NotFound description = failed to pull and unpack image
#   "nginx:0.0.0-does-not-exist": failed to resolve reference: pull access
#   denied, repository does not exist or may require authorization

# 3. Fix the chart. The image tag does not exist, so point the template at a
#    tag that does. The tag is hard-coded in the template, not taken from
#    values.yaml, so the file itself has to change.
sed -i.bak 's|nginx:0.0.0-does-not-exist|nginx:1.25|' \
  /tmp/cka-lab/charts/broken-chart/templates/deployment.yaml
rm -f /tmp/cka-lab/charts/broken-chart/templates/deployment.yaml.bak
#
# (Check what the chart now renders before touching the release:
#  helm template broken /tmp/cka-lab/charts/broken-chart -n webapps)

# 4. Editing the file changed nothing in the cluster. The release only picks
#    the new template up on the next upgrade.
helm upgrade broken /tmp/cka-lab/charts/broken-chart -n webapps
#
# Release "broken" has been upgraded. Happy Helming!
# RELEASE: broken
# STATUS: deployed
# REVISION: 2

# 5. Wait for the new pods to come up.
kubectl -n webapps rollout status deploy/broken-chart --timeout=120s
# deployment "broken-chart" successfully rolled out

# 6. The state the task asked for.
helm list -n webapps
# NAME    NAMESPACE  REVISION  UPDATED  STATUS    CHART             APP VERSION
# broken  webapps    2         ...      deployed  broken-chart-0.1.0  1.0
kubectl -n webapps get deploy broken-chart
# NAME           READY   UP-TO-DATE   AVAILABLE   AGE
# broken-chart   1/1     1            1           1m
kubectl -n webapps get pods
# NAME                        READY   STATUS    RESTARTS   AGE
# broken-chart-6d8f7c9c4-2xqz   1/1     Running   0          30s
