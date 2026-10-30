#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

NS=provisioning
SC=fast
BEFORE_FILE=/tmp/cka-lab/c11.sc.before

# The namespace takes the claim and the Pod with it.
k delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# The StorageClass is cluster-scoped, so it has to be removed by name.
k delete sc "$SC" --ignore-not-found >/dev/null 2>&1 || true

# A volume provisioned by the class can outlive its claim, and it survives the
# namespace deletion. Remove those by hand: anything left behind on the class
# this question created, or still claimed from the namespace it used.
PVS=$(k get pv -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.spec.storageClassName}{"|"}{.spec.claimRef.namespace}{"\n"}{end}' 2>/dev/null)
printf '%s\n' "$PVS" | while IFS='|' read -r pv sc ns; do
  [ -n "${pv:-}" ] || continue
  if [ "$sc" = "$SC" ] || [ "$ns" = "$NS" ]; then
    k delete pv "$pv" --ignore-not-found >/dev/null 2>&1 || true
  fi
done

# Put the default flag back exactly where it was. The setup recorded every
# class and the value of its default annotation, so each one is restored to
# its original value - including the class that held the flag before.
BEFORE=$(cat "$BEFORE_FILE" 2>/dev/null || true)
if [ -n "$BEFORE" ]; then
  printf '%s\n' "$BEFORE" | tr ';' '\n' | while IFS= read -r line; do
    [ -n "$line" ] || continue
    name="${line%%=*}"
    val="${line#*=}"
    [ -n "$name" ] || continue
    if [ "$val" = "true" ]; then
      k annotate sc "$name" storageclass.kubernetes.io/is-default-class="true" --overwrite >/dev/null 2>&1 || true
    elif [ -n "$val" ]; then
      k annotate sc "$name" storageclass.kubernetes.io/is-default-class="$val" --overwrite >/dev/null 2>&1 || true
    else
      k annotate sc "$name" storageclass.kubernetes.io/is-default-class- >/dev/null 2>&1 || true
    fi
  done
  echo "c11 reset: namespace $NS removed, StorageClass $SC deleted, the default-class"
  echo "         annotation restored on every class that was there before"
else
  echo "c11 reset: namespace $NS removed, StorageClass $SC deleted"
  echo "         (no StorageClass snapshot was recorded, so the default flag was left as it is)"
fi

rm -f "$BEFORE_FILE"
