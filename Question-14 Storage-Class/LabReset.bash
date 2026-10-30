#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# Remove the class the candidate created.
k delete sc local-storage --ignore-not-found >/dev/null

# Put the default flag back where it was. The setup recorded the state of every
# class before the question, so restore exactly that.
BEFORE=$(cat /tmp/cka-lab/q14.sc.before 2>/dev/null || true)
if [ -n "$BEFORE" ]; then
  ORIG=$(printf '%s' "$BEFORE" | tr ';' '\n' | awk -F= '$2=="true"{print $1}' | head -1)
  for sc in $(printf '%s' "$BEFORE" | tr ';' '\n' | awk -F= 'NF && $1!=""{print $1}'); do
    if [ "$sc" = "$ORIG" ]; then
      k patch sc "$sc" --type=merge \
        -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' >/dev/null 2>&1
    else
      k patch sc "$sc" --type=merge \
        -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' >/dev/null 2>&1
    fi
  done
  echo "Restored the default StorageClass to: ${ORIG:-<none>}"
else
  echo "No StorageClass snapshot was recorded, leaving the default flag as it is."
fi

rm -f /tmp/cka-lab/q14.sc.before /tmp/cka-lab/q14.pvc.before

echo "Q14 reset"
