# A Pod with a restricted securityContext.
#
# Two securityContexts, at two levels:
#   spec.securityContext                    -> runAsUser, runAsNonRoot, seccompProfile
#   spec.containers[].securityContext       -> allowPrivilegeEscalation, capabilities
#
# busybox with a sleep is the safe image: it runs happily as uid 1000.

cat <<'EOF' > pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: restricted
  namespace: secure
spec:
  securityContext:
    runAsUser: 1000
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: app
      image: busybox:stable
      command: ["sh", "-c", "sleep 3600"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
EOF

kubectl apply -f pod.yaml

kubectl -n secure wait --for=condition=Ready pod/restricted --timeout=120s

# Look at what you actually got:
kubectl -n secure get pod restricted
# NAME        READY   STATUS    RESTARTS   AGE
# restricted  1/1     Running   0          5s

# The pod-level context:
kubectl -n secure get pod restricted -o jsonpath='{.spec.securityContext}'; echo
# {"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}}

# The container-level context:
kubectl -n secure get pod restricted -o jsonpath='{.spec.containers[0].securityContext}'; echo
# {"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}

# The user the container is actually running as:
kubectl -n secure exec restricted -- id
# uid=1000 gid=0(root) groups=0(root)
