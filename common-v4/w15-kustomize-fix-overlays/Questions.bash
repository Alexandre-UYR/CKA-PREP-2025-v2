# Question: The overlay that does nothing
#
# There is a Kustomize base at /tmp/cka-lab/kustomize/base: a Deployment `app`
# (2 replicas, image nginx:1.24) and a Service `app` on port 80.
#
# There is also an overlay at /tmp/cka-lab/kustomize/overlays/dev. It is
# supposed to change the image to nginx:1.25 and the replicas to 1, in the
# namespace `dev`. Building it does not do that.
#
# Task:
# 1. Work out why the dev overlay does not produce the Deployment it is
#    supposed to, fix it, and make
#    `kubectl kustomize /tmp/cka-lab/kustomize/overlays/dev` produce a
#    Deployment `app` with image nginx:1.25 and 1 replica, in the namespace
#    `dev`. Create the namespace `dev` if it is not there.
# 2. Create a `prod` overlay next to it, in
#    /tmp/cka-lab/kustomize/overlays/prod: image nginx:1.26, 3 replicas, and
#    the Service as type NodePort.
# 3. Build BOTH overlays with `kubectl kustomize` to check them, then apply
#    the dev one.
#
# The build is the check: `kubectl kustomize` prints exactly what would be
# applied. Read it before you apply anything.
