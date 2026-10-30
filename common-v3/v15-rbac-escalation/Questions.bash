# Question: The permission that lets you grant yourself permissions
#
# The ServiceAccount `helper` in namespace `esc` is bound to the Role
# `helper-role`, and that Role grants `escalate` and `bind` on roles.
#
# `escalate` means "you may create or update a Role granting permissions you
# do not hold yourself". `bind` means "you may bind a Role to a ServiceAccount
# you do not control". Together they turn a read-only ServiceAccount into
# one that is effectively namespace-admin: it can write itself a Role that
# grants it anything in the namespace, and then hand that Role to anyone
# else in there.
#
# Task:
# 1. Prove the hole first:
#      kubectl auth can-i escalate roles \
#        --as=system:serviceaccount:esc:helper -n esc
#    answers yes, and so does the same command with the verb `bind`.
# 2. Close it. The Role `helper-role` must:
#    - still let the ServiceAccount READ pods (get and list);
#    - no longer grant `escalate` or `bind`, and no rule may use a wildcard
#      verb;
#    - leave the ServiceAccount unable to create pods in the namespace.
#
# Prove the fix the same way you proved the hole:
#   kubectl auth can-i escalate roles --as=system:serviceaccount:esc:helper -n esc
#   kubectl auth can-i bind roles     --as=system:serviceaccount:esc:helper -n esc
#   kubectl auth can-i create pods    --as=system:serviceaccount:esc:helper -n esc
#   kubectl auth can-i list pods      --as=system:serviceaccount:esc:helper -n esc
#
# The first three must answer `no` and the last one must still answer `yes`.
#
# Note: `kubectl auth can-i` exits non-zero when the answer is "no", so pipe
# it rather than testing its exit status.
