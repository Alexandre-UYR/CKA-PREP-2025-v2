# Question: Define a CRD and use it
#
# Task:
# 1. Define a CustomResourceDefinition named widgets.example.com:
#      - group:    example.com
#      - version:  v1
#      - kind:     Widget
#      - plural:   widgets
#      - singular: widget
#      - scope:    Namespaced
#      - a schema that REQUIRES spec.size (a string)
#    Save the manifest to /tmp/cka-lab/c22.crd.yaml
# 2. Create a Widget named w1 in namespace custom with spec.size: large
# 3. Read it back with kubectl get widgets
