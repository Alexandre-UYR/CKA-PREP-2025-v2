# Question: The name that does not resolve
#
# In the `dns-demo` namespace there is a Pod `redis` (redis:7, labels
# app=redis), a Service `redis-svc` of type ClusterIP on port 11211, and a
# Pod `looker` (busybox) you can run commands in.
#
# Task:
# 1. From the `looker` pod, `redis-svc` does not resolve to anything usable.
#    The Service exists and looks correct. Find out why, and fix it.
# 2. From the `looker` pod, use `nslookup` to find BOTH:
#    - the address of the Service `redis-svc`
#    - the address of the Pod `redis`
# 3. Write both addresses to /root/q5.txt, one per line.
#
# Note: a Service's name resolves to its ClusterIP inside the cluster, and
# that resolution goes through CoreDNS. A Service whose selector matches
# nothing still gets a ClusterIP and still resolves - it just resolves to an
# address with nothing behind it, which is why the name resolving is not the
# same as the Service working.
