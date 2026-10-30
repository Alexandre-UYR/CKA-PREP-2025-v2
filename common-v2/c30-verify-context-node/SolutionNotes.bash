# Which context am I pointed at?
kubectl config current-context
# e.g. minikube

# Confirm it points where you think.
kubectl cluster-info

# Which node am I on?
hostname
# e.g. minikube

# The control plane's version.
kubectl version
# Client Version: v1.31.0
# Server Version: v1.31.0

# Write the answers down.
kubectl config current-context > /root/current-context.txt
hostname > /root/current-node.txt

# Check what you wrote.
cat /root/current-context.txt
cat /root/current-node.txt

# If the context is wrong, switch it before you do anything else.
# kubectl config use-context <the right one>
