# 1. Define the CRD and save the manifest.
#
# The plural in names is what makes "kubectl get widgets" work, and the
# required list lives inside the schema of the spec property - not at the top
# level of the CRD schema.

cat <<'EOF' > /tmp/cka-lab/c22.crd.yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: widgets.example.com
spec:
  group: example.com
  scope: Namespaced
  names:
    plural: widgets
    singular: widget
    kind: Widget
    listKind: WidgetList
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              required:
                - size
              properties:
                size:
                  type: string
EOF

kubectl apply -f /tmp/cka-lab/c22.crd.yaml

# Wait for the API server to serve the new kind before using it.
kubectl wait --for=condition=Established crd/widgets.example.com --timeout=60s

kubectl get crd widgets.example.com
# NAME                  CREATED AT
# widgets.example.com   10s

# 2. Create a Widget.
#
# The apiVersion is <group>/<version> and the kind is names.kind.

cat <<'EOF' > /tmp/cka-lab/c22.widget.yaml
apiVersion: example.com/v1
kind: Widget
metadata:
  name: w1
  namespace: custom
spec:
  size: large
EOF

kubectl apply -f /tmp/cka-lab/c22.widget.yaml

# 3. Read it back.
#
# The resource is addressed by its PLURAL name.

kubectl -n custom get widgets
# NAME   AGE
# w1     3s

kubectl -n custom get widgets w1 -o yaml
# apiVersion: example.com/v1
# kind: Widget
# metadata:
#   name: w1
#   namespace: custom
# spec:
#   size: large

# The schema really is enforced - a Widget without spec.size is rejected:
#
# kubectl apply -f - <<'EOF'
# apiVersion: example.com/v1
# kind: Widget
# metadata:
#   name: bad
#   namespace: custom
# spec: {}
# EOF
#
# The Widget "bad" is invalid: spec.size: Required value
