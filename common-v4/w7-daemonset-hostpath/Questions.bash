# Question: One pod on every node
#
# The `agent` namespace holds a ConfigMap `fluentd-config` with the agent's
# configuration, and nothing else. The DaemonSet does not exist yet.
#
# Task:
# 1. Deploy a DaemonSet `fluentd` in the `agent` namespace, from the image
#    `quay.io/fluentd/fluentd:v1.6`.
# 2. It must use `hostNetwork: true`, so the agent can see the network of the
#    node it runs on.
# 3. It must mount TWO hostPath volumes:
#      - `varlog`, the host path `/var/log`, mounted at `/var/log`
#      - `varlibdockercontainers`, the host path `/var/lib/docker/containers`,
#        mounted at `/var/lib/docker/containers`
# 4. It must be scheduled and Ready on EVERY node in the cluster, including
#    the control-plane node.
#
# Check `kubectl -n agent get ds fluentd`: DESIRED must equal the number of
# nodes in the cluster, and READY must equal DESIRED.
