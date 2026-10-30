# The container list of a running Pod cannot be changed, so the first thing to
# find out is what happens when you try.
#
#   $ kubectl -n shared patch pod writer --type=json -p '[{"op":"add","path":"/spec/containers/1",...}]'
#   The Pod "writer" is invalid: spec: Forbidden: pod updates may not change
#   fields other than spec.containers[*].image, spec.initContainers[*].image,
#   ...
#
# So the Pod is deleted and created again with BOTH containers. The name stays
# `writer`, and the emptyDir is declared once and mounted by both containers.
kubectl -n shared delete pod writer --ignore-not-found --wait=true

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: writer
  namespace: shared
  labels:
    app: writer
spec:
  containers:
    - name: writer
      image: busybox:1.36
      command: ["sh", "-c", "echo hello > /data/hi; sleep 10000"]
      volumeMounts:
        - name: work
          mountPath: /data
    - name: reader
      image: busybox:1.36
      command: ["sh", "-c", "sleep 10000"]
      volumeMounts:
        - name: work
          mountPath: /data
  volumes:
    - name: work
      emptyDir: {}
EOF

# The emptyDir is re-created empty, so the first container writes the file
# again - it is still running the same command. Check rather than assume.
kubectl -n shared wait --for=condition=Ready pod/writer --timeout=120s

kubectl -n shared get pod writer -o jsonpath='{.spec.containers[*].name}'
# writer reader

kubectl -n shared get pod writer -o jsonpath='{.spec.containers[*].volumeMounts[*]}'
# [{"name":"work","mountPath":"/data"} {"name":"work","mountPath":"/data"}]

# Read the file from the SECOND container. Without -c, kubectl exec goes to the
# default container, which is the first one.
kubectl -n shared exec writer -c reader -- cat /data/hi
# hello

# The two containers share one directory, so a file written in one is there in
# the other:
kubectl -n shared exec writer -c writer -- sh -c 'echo proof > /data/marker'
kubectl -n shared exec writer -c reader -- cat /data/marker
# proof

# A second Pod would NOT see any of this, even with a volume of the same name:
kubectl -n shared run other --image=busybox:1.36 --restart=Never -- \
  ls /data 2>/dev/null || echo "(no volume mounted)"
# An emptyDir belongs to its Pod. To share storage between Pods you need a
# PersistentVolume and a PersistentVolumeClaim.
