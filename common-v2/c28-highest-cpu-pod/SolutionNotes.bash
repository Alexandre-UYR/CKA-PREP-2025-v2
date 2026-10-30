# Find the Pod using the most CPU in the `metrics` namespace.
#
# 1. Look at what is there. Note the labels - `workload=batch` matches
#    cpu-hog AND calm-one, so it is not narrow enough to be the answer.
kubectl get pods -n metrics --show-labels
# NAME                       READY   STATUS    RESTARTS   AGE     LABELS
# calm-one-6f7c9d5b8-x4k2p   1/1     Running   0          2m      app=calm-one,workload=batch
# calm-two-59bd7c4f6-q8wzt   1/1     Running   0          2m      app=calm-two,workload=web
# cpu-hog-7d9f4b8c56-x2k9p   1/1     Running   0          2m      app=cpu-hog,workload=batch

# 2. Narrow the search with a label selector and read the CPU column.
kubectl top pods -n metrics -l workload=batch
# NAME                       CPU(cores)   MEMORY(bytes)
# calm-one-6f7c9d5b8-x4k2p   0m          2Mi
# cpu-hog-7d9f4b8c56-x2k9p   9m          2Mi
#
# Or go straight to the one you are after:
kubectl top pods -n metrics -l app=cpu-hog
# NAME                       CPU(cores)   MEMORY(bytes)
# cpu-hog-7d9f4b8c56-x2k9p   9m          2Mi

# The answer is the POD name, so read it off `kubectl get pods`, not off the
# Deployment name.

# 3. Write the answer down, in the form namespace/podname.
POD=$(kubectl top pods -n metrics --no-headers -l app=cpu-hog \
      | sort -k2 -hr | head -1 | awk '{print $1}')
echo "metrics/$POD" > /root/hot-pod.txt
cat /root/hot-pod.txt
# metrics/cpu-hog-7d9f4b8c56-x2k9p

# 4. Record the command you used.
cat <<'EOF' > /root/hot-pod-command.txt
kubectl top pods -n metrics -l app=cpu-hog
EOF
cat /root/hot-pod-command.txt
# kubectl top pods -n metrics -l app=cpu-hog

# A note on the CPU column: kubectl top prints millicores while the value is
# below a core and whole cores above it ("9m" and "1"), so a text sort is
# misleading - normalise to millicores before you compare.
