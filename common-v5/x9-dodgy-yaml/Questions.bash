# Question: The manifest that does not do what it says
#
# The manifest at /tmp/cka-lab/dodgy.yaml is wrong in three ways.
#
# Task:
# 1. Find them all and fix the FILE - do not apply a corrected copy from
#    somewhere else.
# 2. Apply it. The Deployment must be accepted by the API server.
# 3. The Service `dodgy-svc` in the `dodgy` namespace must end up with
#    endpoints.
