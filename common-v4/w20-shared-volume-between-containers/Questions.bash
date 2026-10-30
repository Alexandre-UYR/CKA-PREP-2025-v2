# Question: One volume, two containers
#
# In the `shared` namespace there is a Pod `writer` with ONE container
# (busybox:1.36). It writes `hello` into /data/hi and then sleeps. The Pod has
# an emptyDir volume `work` mounted at /data, and the file /data/hi really is
# there.
#
# Task:
# Add a SECOND container to the Pod `writer` that mounts the SAME volume at
# /data and can read what the first container wrote.
#
# The Pod must end up with two containers sharing one volume, and reading
# /data/hi from the second container must return `hello`.
