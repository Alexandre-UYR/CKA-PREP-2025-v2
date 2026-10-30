# x10 — nginx as somebody else: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `sec` | `LabSetUp.bash` | The Pod lives here and the task names the namespace. |
| 2 | ConfigMap `nginx-conf` with one key, `nginx.conf` | `LabSetUp.bash`, from `/tmp/cka-lab/nginx.conf` | The configuration the task tells the candidate to use. It already listens on 8000 and it names the paths nginx writes to, so the candidate can read the paths off it rather than guess them. |
| 3 | Pod `myuserpod`, image `nginx:1.25`, no `securityContext` | `LabSetUp.bash` | The workload under investigation. With no `securityContext` the container runs as root, and with the stock configuration it serves on port 80. |
| 4 | The image's own filesystem: `/var/cache/nginx` and `/var/run/nginx` owned by root | the `nginx:1.25` image | The trap. nginx writes its temporary files and its pid file under those directories, and a non-root user cannot write there. |
| 5 | The Pod to be running when the exercise starts | `LabSetUp.bash` polls for readiness | The pre-state has to be a working Pod, otherwise the candidate cannot tell "I broke it" from "it was already broken". |

The configuration the ConfigMap holds, in full, so that the paths it names are
not a surprise:

```
worker_processes 1;

error_log  /tmp/nginx-error.log warn;
pid        /var/run/nginx/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    access_log    /tmp/nginx-access.log;

    client_body_temp_path /tmp/client_temp;
    proxy_temp_path       /var/cache/nginx/proxy_temp;
    fastcgi_temp_path     /var/cache/nginx/fastcgi_temp;
    uwsgi_temp_path       /var/cache/nginx/uwsgi_temp;
    scgi_temp_path        /var/cache/nginx/scgi_temp;

    server {
        listen       8000;
        server_name  _;

        location / {
            default_type text/plain;
            return 200 "nginx is running as a non-root user\n";
        }
    }
}
```

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The Pod's `runAsUser` is 4242 | `LabValidate.bash` |
| B | The Pod's `runAsGroup` is 4242, or `fsGroup` is 4242 | `LabValidate.bash` |
| C | The Pod is Running and its container is ready | `LabValidate.bash` |
| D | The configuration comes from the ConfigMap `nginx-conf`, mounted at `/etc/nginx/nginx.conf` | `LabValidate.bash` |
| E | A writable volume mounted at every path the configuration writes to — `/var/run/nginx` and `/var/cache/nginx` | `LabValidate.bash`, which reads the paths out of the ConfigMap |
| F | A request from inside the Pod to `http://localhost:8000` returns HTTP 200 | `LabValidate.bash` (live) |
| G | The process inside the container reports UID 4242 | `LabValidate.bash` (live) |

## Gotchas

- **A container cannot bind a port below 1024 as a non-root user.** Port 80 is
  in the privileged range, so the stock configuration — and the stock
  `default.conf` that comes with the image — cannot be used. The configuration
  has to move to 8000, which is what the ConfigMap does.

- **A read-only root filesystem is not the only thing that stops nginx working
  as a non-root user.** It also writes to `/var/cache` and `/var/run`, and
  those directories are owned by root in the image. Those paths need to be
  writable, usually by mounting `emptyDir` volumes over them. A Pod with
  `runAsUser: 4242` and nothing else starts nginx, and nginx then exits with
  `mkdir() "/var/cache/nginx/proxy_temp" failed (13: Permission denied)`.

- **The Pod's `securityContext` cannot be edited in place.** A Pod's spec is
  immutable in that field, so `kubectl edit pod` is refused and the Pod has to
  be deleted and re-created. The setup deletes and re-creates the Pod too, so
  that a second run starts from the same state.

- **The official image's entrypoint script.** `/docker-entrypoint.sh` edits
  `/etc/nginx/conf.d/default.conf` before it starts nginx, and a non-root user
  cannot write there. The container then exits before nginx has started, with
  an error about the config file. Setting the container's `command` to
  `nginx -g "daemon off;"` bypasses the entrypoint script entirely.

- **The ConfigMap has to be mounted at `/etc/nginx/nginx.conf`.** Mounting it
  into `/etc/nginx/conf.d/` leaves the stock `nginx.conf` in place, and that one
  still pulls in `/etc/nginx/conf.d/default.conf` — which listens on port 80.
  nginx then fails to bind 80 as a non-root user.

- **nginx creates its temporary directories at start-up.** The directories have
  to be writable before the first start, not after: nginx does not need them
  until the first request, but it does create them at start-up and it exits if
  it cannot.

- **The UID and the GID are part of the answer.** The task fixes them at 4242,
  and the grader checks them. `fsGroup` is accepted for the group, but the user
  has to be 4242 as well.

## Environment requirements

- A cluster with at least one node, and registry access for `nginx:1.25` and
  for `curlimages/curl` (the latter only for the fallback probe).
- No special components. This is plain Pod, ConfigMap and volume behaviour.
- The exercise is done on the node running the Pod, so a Linux container
  runtime. The live check uses `bash` inside the container; on an image
  without `bash` the validator falls back to making the same request from a
  throwaway Pod.
