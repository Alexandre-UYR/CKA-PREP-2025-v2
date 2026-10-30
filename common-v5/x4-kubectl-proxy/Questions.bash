# Question: Ask the API server directly
#
# `kubectl get` is a convenience: it talks to the API server and prints what
# it finds, in a form built for humans. The API server is also an ordinary
# HTTP server, and it will answer any client that speaks HTTP.
#
# Task:
# Using `kubectl proxy` - NOT `kubectl get namespaces` - make an API call that
# lists every namespace in the cluster, and save the response to
# /root/namespaces.json.
#
# The proxy serves the API on a local port; point a client at it.
#
# The response has to be the real thing: a JSON document with the namespaces
# in it, all of them.
