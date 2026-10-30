# Question: Make it work harder, then watch it
#
# The cluster has no metrics. Without a metrics API there is nothing for a
# HorizontalPodAutoscaler to read, so no workload in this cluster has ever
# scaled automatically.
#
# Task:
# 1. Install a metrics server, so that the cluster has a metrics API.
# 2. Create a HorizontalPodAutoscaler `hpa` in the `autoscale` namespace that
#    targets the Deployment `hpa-example`: minimum 1 pod, maximum 10 pods,
#    targeting 50% of the container's CPU request.
# 3. Run a load generator Pod (busybox:1.28) in the `autoscale` namespace that
#    hammers the Service `hpa-example` in a loop:
#
#        while sleep 0.01; do wget -q http://hpa-example; done
#
# 4. Watch the Deployment scale up.
#
# The Deployment and the Service are not to be changed. Their CPU request and
# CPU limit stay as they are.
