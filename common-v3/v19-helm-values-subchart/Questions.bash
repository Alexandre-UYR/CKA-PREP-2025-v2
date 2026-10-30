# Question: Overriding a subchart's values
#
# The chart at /tmp/cka-lab/charts/stack is a parent chart with a subchart.
# Its values.yaml holds the frontend's settings and a section for the
# `backend` subchart; the subchart itself is vendored under charts/.
#
# Task:
# 1. Write the values you need to /tmp/cka-lab/stack-values.yaml:
#      - the frontend image tag 2.1.0
#      - 3 frontend replicas
#      - the SUBCHART backend on image tag 2.0.5, with 2 replicas and
#        service port 9090
# 2. Create the namespace `apps`, then install the chart with that values
#    file as the release `stack`:
#
#      helm install stack /tmp/cka-lab/charts/stack -n apps -f /tmp/cka-lab/stack-values.yaml
#
# 3. Check what was rendered:
#
#      helm template stack /tmp/cka-lab/charts/stack -f /tmp/cka-lab/stack-values.yaml
#
#    It must show a frontend Deployment with 3 replicas and the image tag
#    2.1.0, a backend Deployment with 2 replicas and the image tag 2.0.5, and
#    a backend Service on port 9090.
#
# Mind the difference between the parent chart's own values and the
# subchart's: a subchart's values live under the subchart's own key.
