# Question: ConfigMap and Secret as files and as env vars
#
# Task:
# In the config namespace, create:
#   - a ConfigMap named app-config with the key LOG_LEVEL set to debug
#   - a Secret named app-secret with the key DB_PASS set to s3cret
#
# Then create a Deployment named app (image nginx, 1 replica) in the same
# namespace that:
#   - mounts the ConfigMap app-config as a volume at /etc/config, read-only
#   - mounts the Secret app-secret as a volume at /etc/secret, read-only
#   - gets the environment variable LOG_LEVEL from the ConfigMap, via
#     configMapKeyRef
#   - gets the environment variable DB_PASS from the Secret, via secretKeyRef
#
# Both routes are required: the file-based route (the volume mounts) and the
# env var route. Neither environment variable may be a plain literal value.
