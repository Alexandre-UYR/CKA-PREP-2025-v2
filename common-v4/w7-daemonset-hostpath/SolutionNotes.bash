# 1. What is on the control-plane node?
#
#    The toleration has to name the taint the node actually carries.
kubectl get nodes -o wide
kubectl get node <control-plane-node> -o jsonpath='{.spec.taints}{"\n"}'
# [{"effect":"NoSchedule","key":"node-role.kubernetes.io/control-plane"}]

# 2. The DaemonSet.
#
#    - hostNetwork: true, so the agent shares the node's network.
#    - two hostPath volumes: `path` is a directory on the NODE, `mountPath` is
#      where it shows up inside the container.
#    - DirectoryOrCreate on /var/lib/docker/containers: that directory does
#      not exist on a containerd node, and a hostPath with the default type
#      does not create anything, so the pod would never start.
#    - a toleration for the control-plane taint, with no `effect` so it covers
#      the NoSchedule taint (and an operator of Equal with an empty value,
#      because the taint itself carries no value).

cat <<'EOF' | kubectl apply -n agent -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentd
  namespace: agent
  labels:
    app: fluentd
spec:
  selector:
    matchLabels:
      app: fluentd
  template:
    metadata:
      labels:
        app: fluentd
    spec:
      hostNetwork: true
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Equal
          value: ""
          effect: NoSchedule
        - key: node-role.kubernetes.io/master
          operator: Equal
          value: ""
          effect: NoSchedule
      containers:
        - name: fluentd
          image: quay.io/fluentd/fluentd:v1.6
          volumeMounts:
            - name: varlog
              mountPath: /var/log
            - name: varlibdockercontainers
              mountPath: /var/lib/docker/containers
      volumes:
        - name: varlog
          hostPath:
            path: /var/log
            type: Directory
        - name: varlibdockercontainers
          hostPath:
            path: /var/lib/docker/containers
            type: DirectoryOrCreate
EOF

# 3. Watch it settle.
kubectl -n agent rollout status daemonset/fluentd --timeout=180s

kubectl -n agent get ds fluentd
# NAME      DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
# fluentd   3         3         3       3            3           <none>          30s

# DESIRED is the number of nodes and READY is DESIRED. If DESIRED is one
# short, the control-plane node was skipped: the toleration is missing or
# names the wrong key.

kubectl -n agent get pods -o wide
# NAME                        READY   STATUS    RESTARTS   AGE   NODE
# fluentd-2xk4t              1/1     Running   0          30s   control-plane-node
# fluentd-6d9lb              1/1     Running   0          30s   worker-1
# fluentd-qm8zt              1/1     Running   0          30s   worker-2

# A pod that will not start on the control-plane node says so:
kubectl -n agent describe pod fluentd-2xk4t | tail -20
# Events:
#   Warning  FailedScheduling  2m  default-scheduler
#   0/1 nodes are available: 1 node(s) had untolerated taint
#   {node-role.kubernetes.io/control-plane: }. preemption: 0/1 nodes are
#   available: 1 No preemption victims found for incoming pod.
#
# If you want the agent to read the ConfigMap, mount it at /fluentd/etc - NOT
# over /fluentd/etc/fluent.conf with the fluent-bit.conf key, which is not
# fluentd's syntax and stops the agent from starting.
#
#   volumeMounts:
#     - name: config
#       mountPath: /fluentd/etc
#   volumes:
#     - name: config
#       configMap:
#         name: fluentd-config
