# Question: A ConfigMap made of files
#
# On the machine there is a directory, /tmp/cka-lab/colors/primary/, holding
# five files: cyan, magenta, yellow, black and blue. Every file holds a colour
# name. The file `black` holds two lines: the colour name, and the line
# `known as key`.
#
# Task:
# 1. Create the ConfigMap `colors` in the namespace `cfg` from the files in
#    /tmp/cka-lab/colors/primary/. Every file becomes one key, named after the
#    file, and the contents of the file become the value of that key.
# 2. Create the Deployment `cfg-app` in the namespace `cfg` — image nginx, 1
#    replica — that exports EVERY key of that ConfigMap as an environment
#    variable, using `envFrom`.
# 3. Check one of them from inside the pod:
#
#      kubectl -n cfg exec deploy/cfg-app -- printenv cyan
#
#    The value it prints has to be the content of the file `cyan`.
#
# Note: the `black` key has to keep BOTH lines. It is one key, not two.
