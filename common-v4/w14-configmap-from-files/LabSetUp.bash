#!/bin/bash
set -e

# w14 - A ConfigMap made of files
#
# The pre-state is a directory of small files on disk and an empty namespace.
# The candidate has to turn the files into a ConfigMap and then get every key
# of that ConfigMap into the environment of a running pod.
#
# The interesting part of the pre-state is the file `black`: it has TWO lines,
# so its key has a multi-line value. `kubectl create configmap --from-file`
# does not split a file into several keys - it makes one key per file.

NS=cfg
DEP=cfg-app
CM=colors
ROOT=/tmp/cka-lab/colors
DIR="$ROOT/primary"

mkdir -p "$DIR"

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

# Clear the namespace of anything an earlier attempt left behind. A ConfigMap
# left over from a previous run would make `kubectl create configmap` fail
# with AlreadyExists, and the candidate's answer would never be tested.
kubectl delete configmap --all -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
kubectl delete deployment "$DEP" -n "$NS" --ignore-not-found >/dev/null 2>&1 || true

# The five files. They are written with printf and no trailing newline, so
# that the value of a key is exactly the colour name and nothing else.
printf '%s' "cyan"    > "$DIR/cyan"
printf '%s' "magenta" > "$DIR/magenta"
printf '%s' "yellow"  > "$DIR/yellow"
printf '%s' "blue"    > "$DIR/blue"
printf '%s\nknown as key' "black" > "$DIR/black"

FILES=$(ls "$DIR" | sort | tr '\n' ' ')

echo "✅ w14 environment ready"
echo "   - namespace: $NS (empty - no ConfigMap, no Deployment)"
echo "   - files on disk: $DIR"
echo "     cyan, magenta, yellow, blue  - one line each"
echo "     black                        - two lines, the second one is 'known as key'"
echo "   - Task: build the ConfigMap '$CM' from those files, then run them all"
echo "     as environment variables in the Deployment '$DEP'"
