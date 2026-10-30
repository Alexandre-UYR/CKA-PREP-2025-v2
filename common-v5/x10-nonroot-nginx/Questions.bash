# Question: nginx as somebody else
#
# The Pod `myuserpod` in the `sec` namespace runs nginx as root. It has to run
# as UID 4242 and GID 4242 instead, and it has to keep working.
#
# Task:
# 1. Change the Pod so that it runs as UID 4242 and GID 4242. Do not change the
#    UID or the GID to anything else.
# 2. Make it work. A non-root user cannot bind port 80, so nginx has to listen
#    on 8000 instead. Use the ConfigMap `nginx-conf` for the configuration.
# 3. nginx also has to write to directories that are owned by root in the image.
#    Give it writable paths for them.
#
# Done means: the Pod is Running, its container is ready, and a request made
# from inside the Pod to http://localhost:8000 returns HTTP 200.
