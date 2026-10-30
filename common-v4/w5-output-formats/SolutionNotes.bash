# The five pods, as the cluster has them.
kubectl -n reports get pods -l app=website -o wide
# NAME                       READY   STATUS    RESTARTS   AGE   IP            NODE
# website-6b9c7d5f84-2xk4m   1/1     Running   0          40s   10.244.0.21   kind-worker
# website-6b9c7d5f84-7pd3n   1/1     Running   0          40s   10.244.0.19   kind-worker
# website-6b9c7d5f84-hq8vt   1/1     Running   0          40s   10.244.0.22   kind-worker
# website-6b9c7d5f84-mq2rw   1/1     Running   0          40s   10.244.0.18   kind-worker
# website-6b9c7d5f84-tb5zc   1/1     Running   0          40s   10.244.0.20   kind-worker
#
# The names are in a different order from the addresses. That is the point of
# the first file.

# 1. The first file: name and labels, sorted by pod IP.
#
#    -o custom-columns picks the columns. The first name is the heading, the
#    part after the dot is the JSONPath that fills it.
#    --sort-by sorts the rows by a JSONPath field - and it has to be asked
#    for in the SAME command as the columns, because sorting and printing
#    are two separate steps of the same pipeline.
kubectl -n reports get pods -l app=website \
  --sort-by=.status.podIP \
  -o custom-columns=NAME:.metadata.name,LABELS:.metadata.labels \
  > /root/q6a.txt

cat /root/q6a.txt
# NAME                       LABELS
# website-6b9c7d5f84-mq2rw   app=website
# website-6b9c7d5f84-7pd3n   app=website
# website-6b9c7d5f84-tb5zc   app=website
# website-6b9c7d5f84-2xk4m   app=website
# website-6b9c7d5f84-hq8vt   app=website
#
# Five rows, in ascending order of IP. The addresses above are from this
# cluster; yours will be different.

# 2. The second file: name and phase only, no labels.
#
#    The same command with a different column list. Whatever is not in the
#    column list is not in the output - so this file cannot carry the labels.
kubectl -n reports get pods -l app=website \
  -o custom-columns=NAME:.metadata.name,PHASE:.status.phase \
  > /root/q6b.txt

cat /root/q6b.txt
# NAME                       PHASE
# website-6b9c7d5f84-7pd3n   Running
# website-6b9c7d5f84-mq2rw   Running
# website-6b9c7d5f84-tb5zc   Running
# website-6b9c7d5f84-2xk4m   Running
# website-6b9c7d5f84-hq8vt   Running
#
# No labels, and no sorting needed on this one.

# A couple of variations that also work:
#
#   - keep the headings out of the files:
#     kubectl -n reports get pods -l app=website --no-headers \
#       --sort-by=.status.podIP \
#       -o custom-columns=NAME:.metadata.name,LABELS:.metadata.labels > /root/q6a.txt
#
#   - put the IP in the file as well, which makes the sort visible:
#     kubectl -n reports get pods -l app=website \
#       --sort-by=.status.podIP \
#       -o custom-columns=NAME:.metadata.name,IP:.status.podIP,LABELS:.metadata.labels \
#       > /root/q6a.txt
#
# The third way to see the same pods, which the question does not ask for, is
# the plain table or the JSON:
#
#   kubectl -n reports get pods -l app=website
#   kubectl -n reports get pods -l app=website -o json
