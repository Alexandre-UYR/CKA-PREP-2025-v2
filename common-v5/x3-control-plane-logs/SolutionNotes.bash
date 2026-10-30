# 1. Look at what is under /var/log.
ls -l /var/log/ | grep -E 'kube|kubelet|proxy'
# lrwxrwxrwx 1 root root  62 Jan  1 12:00 kube-apiserver.log -> /var/log/containers/kube-apiserver-node1_kube-system_kube-apiserver-node1_9f1c.../0.log
# lrwxrwxrwx 1 root root  62 Jan  1 12:00 kube-controller-manager.log -> /var/log/containers/kube-controller-manager-node1_kube-system_kube-controller-manager-node1_9f1c.../0.log
# lrwxrwxrwx 1 root root  62 Jan  1 12:00 kube-proxy.log -> /var/log/containers/kube-proxy-zrhk9_kube-system_kube-proxy-zrhk9_3ab7.../0.log
# lrwxrwxrwx 1 root root  62 Jan  1 12:00 kube-scheduler.log -> /var/log/containers/kube-scheduler-node1_kube-system_kube-scheduler-node1_9f1c.../0.log
# -rw-r----- 1 root root 11422 Jan  1 12:00 kubelet.log
#
# The symlinks are the tidy answer: the kubelet made them, one per container it
# runs. The kubelet's own log is a plain file - it is not running in a
# container, so it has no container log.

# The real files, if you want them, are under /var/log/containers/:
ls -l /var/log/containers/
# drwxr-xr-x 2 root root  4096 Jan  1 12:00 kube-apiserver-node1_kube-system_kube-apiserver-node1_9f1c...
# ...

# 2. Write the five paths, in the order the task gives.
cat > /root/control-plane-logs.txt <<'EOF'
/var/log/kube-apiserver.log
/var/log/kube-scheduler.log
/var/log/kube-controller-manager.log
/var/log/kubelet.log
/var/log/kube-proxy.log
EOF

# 3. The second question: who decides where a pod runs?
#
#   the API server       serves the API
#   the scheduler        decides WHERE a pod runs          <- this one
#   the controller mgr   reconciles the state you asked for
#   kube-proxy           programs the node's network rules
echo scheduler > /root/scheduler-component.txt

# 4. Check your work.
cat /root/control-plane-logs.txt
cat /root/scheduler-component.txt
for f in $(cat /root/control-plane-logs.txt); do sudo ls -l "$f"; done
#
# A note on what did NOT work: /var/log/apiserver.log - there is no such file.
# The files carry the kube- prefix that the components actually run under. And
# the scheduler's answer is the component's name, not the log file's name:
# the component is the scheduler, its log file is kube-scheduler.log.
