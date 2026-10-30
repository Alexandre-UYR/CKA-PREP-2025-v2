# Question: Give each pod its own identity and its own disk
#
# The `web` workload in the `stateful` namespace is a plain Deployment behind
# a headless Service. Its pods have no stable network identity, and no
# storage of their own - which is exactly what a StatefulSet is for.
#
# Task:
# 1. Turn the `web` workload into a StatefulSet named `web`.
# 2. It must use the headless Service `web-headless` as its `serviceName`, so
#    that each pod gets a stable DNS name: web-0.web-headless,
#    web-1.web-headless, web-2.web-headless, ...
# 3. It must run 3 replicas.
# 4. Each pod must get its OWN PersistentVolume, declared through a
#    `volumeClaimTemplates` entry: 1Gi, access mode ReadWriteOnce, and the
#    cluster's default StorageClass.
# 5. All three pods must come up and be Ready, each with its own bound claim.
#
# The plain Deployment and the StatefulSet cannot both own the same label
# selector, so take the Deployment out of the way when you create the
# StatefulSet.
