# Question: Gateway API basics
#
# Task:
# The Gateway API CRDs are not installed in this cluster. Install them, then:
#
#   1. Create a Gateway named `edge` with:
#      - gatewayClassName: nginx
#      - one listener on protocol HTTP, port 80
#
#   2. Create an HTTPRoute named `edge-route` that:
#      - attaches to that Gateway
#      - serves the host `app.example.com`
#      - sends requests to Service `web`, port 80
#
# A Deployment `web` (nginx) and a Service `web` on port 80 already exist in the
# default namespace - do not change them.
#
# No gateway controller has to be installed: the Gateway and the HTTPRoute only
# have to exist and have to be correct.
