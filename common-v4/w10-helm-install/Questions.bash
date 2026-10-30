# Question: Install a chart, and install it differently
#
# The chart hello-world 1.0.0 is on disk at /tmp/cka-lab/charts/hello-world.
# Its values.yaml sets replicaCount: 1 and image: nginx:1.25, and its
# templates render a Deployment and a Service from those two values.
#
# Task:
# 1. Create the namespace `apps`.
# 2. Install the chart at /tmp/cka-lab/charts/hello-world into it as the
#    release `hello`.
# 3. Change the number of replicas to 3. Do it with a values FILE, not by
#    editing the chart, and save that file to /root/hello-values.yaml.
# 4. Install the release `hello` using that file.
#
# When you are done: the release `hello` in namespace `apps` is deployed, and
# the Deployment it manages has 3 ready replicas running the image nginx:1.25.
#
# Do not edit the chart on disk. The replica count has to come from the values
# file.
