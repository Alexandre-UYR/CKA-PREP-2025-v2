# Question: The app that cannot start
#
# The `cfg` Deployment in namespace `init` crashes on start: it reads
# /etc/app/config.yaml, which does not exist.
#
# Task:
# 1. Add an init container that PRODUCES that file from the ConfigMap
#    `app-config`, and mount both the ConfigMap and the produced file into the
#    main container so that it starts and the file contains the ConfigMap's
#    value.
# 2. The file must be readable at /etc/app/config.yaml inside the main
#    container.
#
# The Deployment must end up with one ready replica, and this must work:
#
#   kubectl -n init exec deploy/cfg -- cat /etc/app/config.yaml
#
# has to print the ConfigMap's value.
