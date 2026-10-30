# Question: Get a Host header to the right place
#
# In the namespace `web` there is a Deployment `thirdpage` (nginx, 1 replica)
# and a Service `thirdpage` on port 80. The nginx configuration the Deployment
# uses echoes a marker string, so you can tell its answers from anybody else's.
#
# Traefik is not installed.
#
# Task:
# 1. Install the Traefik chart from the Helm repository https://helm.traefik.io
#    (the chart is called `traefik`) into the namespace `traefik`. Create the
#    namespace yourself.
# 2. Create the Ingress `web` in the namespace `web` that forwards requests for
#    the host `www.example.com` to the Service `thirdpage` on port 80. The
#    Ingress has to use the ingress class `traefik`.
# 3. Prove it works: from inside the cluster, send a request to the Traefik
#    service with the Host header set to `www.example.com`, and look at the
#    response.
#
#      kubectl -n web exec probe -- \
#        curl -s -H 'Host: www.example.com' http://traefik.traefik.svc.cluster.local/
#
# The response has to be HTTP 200 and the body has to contain the marker the
# third page echoes.
#
# A pod called `probe` is already running in the namespace `web`, with curl in
# it. Use it, or any other pod you like.
