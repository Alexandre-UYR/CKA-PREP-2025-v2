#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }
G='\033[32m'; R='\033[31m'; X='\033[0m'
FAILS=0
ok(){ echo -e "${G}PASS${X}  $1"; }
bad(){ echo -e "${R}FAIL${X}  $1"; FAILS=$((FAILS+1)); }
eq(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }
has(){ case "$2" in *"$3"*) ok "$1";; *) bad "$1 (got '$2')";; esac; }
nonempty(){ if [ -n "$2" ]; then ok "$1"; else bad "$1"; fi; }
exists(){ local d=$1; shift; if k get "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
note(){ echo -e "      NOTE  $1"; }
skip(){ echo -e "      SKIP  $1"; }

NS=provisioning
SC=fast
PVC=data
POD=writer

echo "== c11: Dynamic provisioning with a StorageClass =="

# ---- the StorageClass ----
if exists "StorageClass $SC exists" sc "$SC"; then
  eq "the provisioner is rancher.io/local-path" \
    "$(k get sc "$SC" -o jsonpath='{.provisioner}' 2>/dev/null)" "rancher.io/local-path"

  eq "the volumeBindingMode is WaitForFirstConsumer" \
    "$(k get sc "$SC" -o jsonpath='{.volumeBindingMode}' 2>/dev/null)" "WaitForFirstConsumer"

  eq "the class carries the default-class annotation with the value true" \
    "$(k get sc "$SC" -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null)" "true"
else
  skip "the provisioner / binding mode / default annotation checks (StorageClass $SC is missing)"
fi

# ---- exactly one default class in the whole cluster, and it is this one ----
SCANNED=$(k get sc -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null)

DEFCOUNT=$(printf '%s' "$SCANNED" | awk -F'|' '$2=="true"' | wc -l | tr -d ' ')
eq "exactly one StorageClass in the cluster is marked default" "$DEFCOUNT" "1"

DEFNAME=$(printf '%s' "$SCANNED" | awk -F'|' '$2=="true"{print $1}' | head -1)
eq "the default StorageClass is $SC" "$DEFNAME" "$SC"

# ---- the claim ----
if exists "PersistentVolumeClaim $PVC exists in namespace $NS" -n "$NS" pvc "$PVC"; then
  eq "the claim is Bound" \
    "$(k -n "$NS" get pvc "$PVC" -o jsonpath='{.status.phase}' 2>/dev/null)" "Bound"

  eq "the claim was provisioned with StorageClass $SC" \
    "$(k -n "$NS" get pvc "$PVC" -o jsonpath='{.spec.storageClassName}' 2>/dev/null)" "$SC"
else
  skip "the claim phase / StorageClass checks (PersistentVolumeClaim $PVC is missing)"
fi

# ---- the pod ----
if exists "Pod $POD exists in namespace $NS" -n "$NS" pod "$POD"; then
  eq "the Pod is Running" \
    "$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null)" "Running"

  CLAIMVOL=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.volumes[?(@.persistentVolumeClaim.claimName==\"$PVC\")].name}" 2>/dev/null)
  nonempty "the Pod template has a volume backed by PersistentVolumeClaim $PVC" "$CLAIMVOL"

  if [ -n "$CLAIMVOL" ]; then
    MP=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.containers[*].volumeMounts[?(@.name==\"$CLAIMVOL\")].mountPath}" 2>/dev/null)
    eq "the volume backed by claim $PVC is mounted at /data" "$MP" "/data"
  else
    skip "the mount path check (no volume in the Pod template references claim $PVC)"
  fi
else
  skip "the Pod phase / mount checks (Pod $POD is missing)"
fi

note "The default-class flag is per cluster, not per namespace: two classes"
note "marked default is an ambiguity, not a default. Exactly one class may carry"
note "the annotation at any time."
note "With WaitForFirstConsumer the volume is not provisioned when the claim is"
note "created but when a pod that uses it is scheduled - so the claim stays"
note "Pending until 'writer' exists, and the two have to be created together."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c11 PASSED${X}"; else echo -e "${R}c11 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
