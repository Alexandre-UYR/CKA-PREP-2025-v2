# 1. Start the proxy. It runs in the foreground, so it has to go into the
#    background - otherwise the next command never runs.
kubectl proxy &
# Starting proxy on http://127.0.0.1:8001
#
# (kubectl proxy --port=8001 if 8001 is already taken; the answer then has to
# be fetched from the port it is actually on.)

# 2. Talk to the API server through it. The proxy serves the API under /api
#    and /apis; the core group's version is v1, and namespaces are a
#    collection of the core group.
curl -s http://127.0.0.1:8001/api/v1/namespaces > /root/namespaces.json

# 3. Check what came back.
head -c 300 /root/namespaces.json
# {"kind":"NamespaceList","apiVersion":"v1","metadata":{"resourceVersion":"4821"},"items":[{"metadata":{"name":"cka-proxy-alpha","uid":"...
#
# The top-level object is a NamespaceList. The namespaces themselves are the
# elements of "items".

python3 -c 'import json; d=json.load(open("/root/namespaces.json")); print(len(d["items"]), "namespaces")'
# 6 namespaces

kubectl get namespaces --no-headers | wc -l
# 6
#
# The two the setup created are in there too:
kubectl get namespaces
# NAME              STATUS   AGE
# cka-proxy-alpha   Active   10s
# cka-proxy-beta    Active   10s
# default           Active   3h
# kube-node-lease   Active   3h
# kube-public       Active   3h
# kube-system       Active   3h

# 4. Stop the proxy when you are done.
kill %1

#
# A note on what did NOT work: `kubectl get namespaces -o json > file` does
# produce a JSON document with the namespaces in it, but it is not the API's
# answer to an HTTP request - the task is the proxy. And a path without the
# version in it (/api/namespaces) returns nothing.
