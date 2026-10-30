# 1. Look at the Secret. It has already been rotated.
kubectl -n rot get secret app-secret -o jsonpath='{.data.TOKEN}' | base64 -d
# new-value

# 2. Look at how the Deployment reads it - twice.
kubectl -n rot get deploy app -o yaml | grep -A6 -e 'env:' -e 'volumeMounts:'
#         env:
#           - name: TOKEN
#             valueFrom:
#               secretKeyRef:
#                 name: app-secret
#                 key: TOKEN
#         volumeMounts:
#           - name: secret-vol
#             mountPath: /etc/secret
#             readOnly: true

# 3. Look inside the running container. The environment still holds the OLD
#    value: the kubelet injected it when the container started, and the
#    container has not started again since.
POD=$(kubectl -n rot get pods -l app=app -o jsonpath='{.items[0].metadata.name}')
kubectl -n rot exec "$POD" -- printenv TOKEN
# old-value

# 4. The mounted file is a projection, not a copy. The kubelet rewrites it in
#    place when the Secret changes - on its own schedule, so it is not there
#    the instant you look.
kubectl -n rot exec "$POD" -- cat /etc/secret/TOKEN
# old-value

# Wait for the kubelet, and look again.
sleep 90
kubectl -n rot exec "$POD" -- cat /etc/secret/TOKEN
# new-value

# So: the file updated by itself, the environment variable did not.

# 5. To get the environment variable to the new value, the container has to
#    start again. The secretKeyRef is read again at start-up - there is no need
#    to change the Deployment, and no need to touch the Secret.
kubectl -n rot rollout restart deployment app
kubectl -n rot rollout status deployment app --timeout=120s

POD=$(kubectl -n rot get pods -l app=app -o jsonpath='{.items[0].metadata.name}')
kubectl -n rot exec "$POD" -- printenv TOKEN
# new-value
kubectl -n rot exec "$POD" -- cat /etc/secret/TOKEN
# new-value

# Which one you want depends on the application. A program that reads its
# configuration once at start-up is happy with the environment variable, and
# needs a restart to pick up a new value. A program that re-reads the file on
# every request picks up the rotation on its own, with no restart at all.
#
# The trap to know about: mounting the Secret with subPath does NOT refresh.
# A subPath mount is a bind mount of a single file, and the kubelet never
# updates it. The same Secret mounted at /etc/secret without subPath is
# refreshed in place.
