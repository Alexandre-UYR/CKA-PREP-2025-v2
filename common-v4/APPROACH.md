# The approach (common-v4)

The same method as every other set in this repo. The full write-up is in
[`../APPROACH.md`](../APPROACH.md); the file-by-file contract every scenario
folder follows is in [`../LAB-CONTRACT.md`](../LAB-CONTRACT.md).

```
   pre-state            task                 answer            reset
  (already there)  ────────────────▶  (you write this)  ────────────────▶ (back to pre-state)
   LabSetUp.bash                          solve it         LabValidate.bash
```

## What this set is for

`common-v2` teaches the shapes of things across the curriculum and `common-v3` is
the diagnosis pass. This set is the **build** pass: the questions where you
create something and put it where other people can reach it — Deployments and
their rollouts, Services of every type, Ingress and Gateway API, Helm and
Kustomize, node placement, and the configuration objects that feed them.

## What makes a good pre-state here

The questions in this set are mostly *creation* tasks, which is the risk: a
creation task with no pre-state is a task with nothing to work out. So the
pre-states here are the interesting states a real cluster gets into:

| Question | The pre-state is not empty |
|---|---|
| w1 | A working Deployment and Service, so the questions are about what the cluster REPORTS, not about building one |
| w2 | A Service with a selector that matches nothing — it looks right and resolves to no address |
| w4 | A Service that resolves to nothing, and a lookup Pod already waiting |
| w6 | A Deployment with the wrong strategy and a missing label |
| w7 | Two node paths that have to be right, and a control-plane node that needs a toleration |
| w8 | A volume with something already on it, and a PV that has to be bound rather than replaced |
| w11 | Two nodes deliberately taken out of service |
| w13 | A Secret that already exists, so the question is how to consume it |
| w15 | An overlay that builds without error and changes nothing |
| w18 | A Service whose port and targetPort are different numbers |
| w20 | A Pod that has already written the file the second container has to read |

## The rules that keep a creation task honest

**Grade the outcome, not the method.** Three different Services in front of one
Deployment all work; the validator checks that each of them resolves to the pods.

**Grade the stated constraint.** "Do not delete the Service", "do not change the
pod labels", "keep the same nodePort" — those are part of the answer. The setup
records a UID at the start and the validator compares it at the end.

**Prove the behaviour where the task's point is the behaviour.** A Service with
the right spec but no endpoints is not a working Service, so where it matters the
validator counts endpoint addresses or makes a request.

**Ask for the artefact.** Several of these tasks ask for a file — the endpoints as
JSON, the rollout history, the corrected manifest, the values file. Those files
are graded by CONTENT, not by existing. A file that exists but holds the wrong
thing is not an answer.
