# 1. Look at the Pod first.
kubectl -n reg get pod app
# NAME   READY   STATUS             RESTARTS   AGE
# app    0/1     ImagePullBackOff   0          40s

# 2. The status says only that the container is waiting. The events say WHY
#    the pull failed, and they name the tag.
kubectl -n reg describe pod app
# ...
# Events:
#   Type     Reason     From     Message
#   ----     ------     ----     -------
#   Normal   Scheduled  default  Successfully assigned reg/app to node-1
#   Warning  Failed     kubelet  Error: ErrImagePull: failed to pull and unpack image
#     "nginx:1.99": rpc error: code = NotFound desc = failed to resolve reference
#     "nginx:1.99": not found
#   Normal   Pulling    kubelet  Pulling image "nginx:1.99"
#   Warning  Failed     kubelet  Failed to pull image "nginx:1.99": ...
#     not found
#   Normal   BackOff    kubelet  Back-off pulling image "nginx:1.99"

# The shorter form of the same thing:
kubectl -n reg get events --sort-by=.lastTimestamp | grep -i pull
# LAST SEEN   TYPE      REASON    OBJECT   MESSAGE
# 12s          Warning   Failed    pod/app  Failed to pull image "nginx:1.99": not found

# 3. Which tags actually exist? The ConfigMap in the same namespace says so.
kubectl -n reg get cm image-tags -o yaml
# apiVersion: v1
# data:
#   nginx: 1.25 1.26
# kind: ConfigMap
# metadata:
#   name: image-tags
#   namespace: reg

# The key is the image; the value is the list of its tags. So the image
# reference should be nginx:1.25 or nginx:1.26 - not nginx:1.99.

# 4. Fix the Pod. The image field of a running Pod can be changed in place,
#    so there is no need to delete and re-create it.
kubectl -n reg set image pod/app app=nginx:1.25
# pod/app image updated

# 5. The kubelet pulls the new image and restarts the container.
kubectl -n reg get pod app -w
# NAME   READY   STATUS    RESTARTS   AGE
# app    0/1     Running   0          52s
# app    1/1     Running   0          58s

# 6. Confirm it is really up, and that nothing is waiting any more.
kubectl -n reg get pod app
# NAME   READY   STATUS    RESTARTS   AGE
# app    1/1     Running   0          1m

kubectl -n reg get pod app -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}'
# (nothing - the container is running, not waiting)

# 7. The ConfigMap is untouched - that was part of the task.
kubectl -n reg get cm image-tags -o jsonpath='{.data.nginx}'
# 1.25 1.26

# If you would rather edit the Pod by hand, `kubectl edit pod app` and change
# the image field does exactly the same thing.
#
# And if the pull had failed for a different reason - a wrong repository name
# rather than a wrong tag - the event would have said so, and the fix would
# have been the repository instead. The event is always the place that tells
# you which part of the reference is wrong.
