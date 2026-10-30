# 1. Make the namespace ENFORCE the restricted Pod Security Standard.
#
# The three levels are independent labels on the namespace. Only "enforce"
# actually rejects a Pod; "warn" and "audit" only report.
#
# "enforce-version" is optional. Leaving it out lets the API server pick its
# own default; setting it pins the policy to a particular release.

kubectl label namespace psa-test \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest --overwrite

kubectl get namespace psa-test --show-labels
# NAME       STATUS   AGE   LABELS
# psa-test   Active   5s    pod-security.kubernetes.io/enforce=restricted,pod-security.kubernetes.io/enforce-version=latest

# 2. Create a Pod that satisfies the restricted profile.
#
# runAsNonRoot, runAsUser and seccompProfile go on the Pod; they then apply to
# every container. allowPrivilegeEscalation and capabilities have to be on the
# container itself.

cat <<'EOF' > compliant.yaml
apiVersion: v1
kind: Pod
metadata:
  name: compliant
  namespace: psa-test
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
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

kubectl apply -f compliant.yaml

kubectl -n psa-test wait --for=condition=Ready pod/compliant --timeout=120s

kubectl -n psa-test get pod compliant
# NAME        READY   STATUS    RESTARTS   AGE
# compliant   1/1     Running   0          4s

# 3. Show a Pod that violates the standard being rejected.
#
# runAsUser: 0 breaks the restricted profile, and the Pod drops no
# capabilities either. The API server refuses the request at admission time.

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: violation
  namespace: psa-test
spec:
  securityContext:
    runAsUser: 0
  containers:
    - name: app
      image: busybox:stable
      command: ["sh", "-c", "sleep 30"]
EOF

# Error from server (Forbidden): error when creating "STDIN": pods "violation"
# is forbidden: violates PodSecurity "restricted:latest: allowPrivilegeEscalation != false,
# unrestricted capabilities, runAsUser == 0, seccompProfile.type != RuntimeDefault"

# The same command with a namespace that is not labelled succeeds, which is
# what makes the rejection meaningful:
#
# kubectl get ns psa-test -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}'
# restricted
