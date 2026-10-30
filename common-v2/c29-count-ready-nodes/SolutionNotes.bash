# Work out which node is the control plane.
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.taints}{"\n"}{end}'

# Count the nodes that are Ready and are not that node.
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' \
  | awk -F'|' '$2=="True" && $1!="<control-plane-node>"' | wc -l

# A shorter way if you only want the count, using the taint to exclude the
# control plane:
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' \
  | awk '$2=="True" && $1!="control-plane"'

# Write the number to the file.
COUNT=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' \
  | awk -F'|' -v cp="<control-plane-node>" '$2=="True" && $1!=cp' | wc -l)
echo "$COUNT" > /root/ready-nodes.txt

# Check what you wrote.
cat /root/ready-nodes.txt
