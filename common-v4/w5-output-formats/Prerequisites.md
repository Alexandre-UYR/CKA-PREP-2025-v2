# w5 — The same pods, three ways: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `reports` | `LabSetUp.bash` | The Deployment lives here, and the task names the namespace. The setup deletes and re-creates the namespace on each run, so an answer file written against an earlier set of pods cannot pass the validation. |
| 2 | Deployment `website` — nginx:latest, 5 replicas, pod labels `app=website` | `LabSetUp.bash` | The five pods the two files have to describe. Five rather than three, because a list that looks right at three rows can still be missing one at five. |
| 3 | Service `website` — ClusterIP, port 8080 → targetPort 80, selector `app=website` | `LabSetUp.bash` | The rest of the workload, and the reason the Deployment exists. It is not graded: the question is about the output, not about the Service. |
| 4 | The setup waits for all 5 replicas to be Ready | `LabSetUp.bash` | The pods have to have an IP before they can be sorted by it, and a Pod with no IP cannot be ordered. |
| 5 | A writable `/root` on the machine running `kubectl` | the environment | Both answers are files on disk. If `/root` is not writable the candidate cannot produce an answer at all. |
| 6 | The two answer files cleared of any earlier attempt | `LabSetUp.bash` | `rm -f /root/q6a.txt /root/q6b.txt`, so a second run does not pass on a stale answer from the first. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | `/root/q6a.txt` — the 5 pods, sorted by ascending pod IP, each row showing the name and the labels | `LabValidate.bash` — the file exists and is not empty, it has one row per pod, every pod's name is in it, it carries the label `app=website`, and the order of the names in the file matches the order of the pods' live IPs |
| B | `/root/q6b.txt` — the same 5 pods, each row showing the name and the phase, and nothing else | `LabValidate.bash` — the file exists and is not empty, it has one row per pod, every pod's name is in it, it carries the phase `Running`, and it does NOT carry the label text |

## Gotchas

- **`-o custom-columns` lets you choose the columns, and the column list is
  what the grader reads.** `-o custom-columns=NAME:.metadata.name,PHASE:.status.phase`
  gives you those two columns and nothing else. Adding a LABELS column gives
  you the labels, and the second file must not have one.

- **`--sort-by` sorts by a JSONPath field, and the sort is not a column.**
  `kubectl get pods --sort-by=.status.podIP` reorders the rows, and the
  columns you asked for come along with them. The trap is doing the sort and
  the printing in two different commands and expecting the second to inherit
  the order — it does not. Ask for the columns and the sort in the SAME
  command:
  `kubectl get pods --sort-by=.status.podIP -o custom-columns=NAME:.metadata.name,LABELS:.metadata.labels`
  What you ask for in the custom-columns list is what you get, and nothing
  else: leave LABELS out and the labels are not in the output.

- **`--sort-by` needs the field to exist on every item.** Sorting by
  `.status.podIP` on a Pod that has not been scheduled yet sorts an empty
  string to one end, which is why the setup waits for the pods to be Ready
  before the question starts.

- **The pod IP is not the pod name, and the names are not in IP order.** The
  ReplicaSet hash and the random suffix decide the name, so the names sort
  into a different order from the addresses. The grader reads the live IPs
  and compares the order of the names in the file against them.

- **The labels have to be on the right file.** `app=website` in `q6a.txt` is
  what is wanted; the same text in `q6b.txt` is a fail. The grader checks
  both directions, because that is the difference between the two files.

- **A header row is harmless; a missing row is not.** `kubectl get` prints
  `NAME` and `PHASE` headings unless you pass `--no-headers`. The grader
  counts the rows that name a pod, so a heading is fine — but all five pods
  have to be there.

- **The Service on port 8080 pointing at targetPort 80 is not a mistake.** It
  is there so the Deployment looks like a real workload. Nothing in this
  question is graded on it, and nothing needs fixing.

## Environment requirements

- A cluster with at least one node, and registry access for `nginx:latest`.
- Write access to `/root` for the candidate and for the validator.
- No special components. This is a plain Deployment, a plain Service, and two
  files.
