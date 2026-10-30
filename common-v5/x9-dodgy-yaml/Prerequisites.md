# x9 — The manifest that does not do what it says: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `dodgy` | `LabSetUp.bash` | The Service and the Deployment both live here, and the task names the namespace. The setup deletes and re-creates it on each run. |
| 2 | Service `dodgy-svc` — ClusterIP, port 80 -> **targetPort 8080**, selector `app=dodgy-app` | `LabSetUp.bash` | The Service the Deployment has to match. Its targetPort is 8080, which is the number the fixed manifest has to declare. The selector names the pods the Service is meant to find. |
| 3 | A manifest at `/tmp/cka-lab/dodgy.yaml` — a Deployment with three deliberate mistakes | `LabSetUp.bash` | The thing under investigation. It is written to disk and **not** applied, so the mistake the API server would refuse is still there to be found. |
| 4 | The workload is `busybox:1.36` running `httpd -f -p 8080` | `LabSetUp.bash` | A real HTTP server that listens on 8080. The container port the manifest declares has to be 8080 for the Service's targetPort to match it, and the container really does serve on that port once the manifest is right. |
| 5 | No Deployment in the namespace | the setup's absence of it | The candidate's job is to make the manifest apply and work. The setup must not have applied the broken manifest itself: the API server would have refused it, and the candidate would never see the error. |
| 6 | Registry access for `busybox:1.36` | the environment | The pods have to pull and start. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | `/tmp/cka-lab/dodgy.yaml` exists, and its `spec.selector.matchLabels` matches its pod template's labels | `LabValidate.bash` — the file is parsed and the two label maps are compared |
| B | The manifest's container port is 8080, matching the Service's targetPort | `LabValidate.bash` |
| C | The manifest declares a positive number of replicas | `LabValidate.bash` |
| D | The Deployment exists in namespace `dodgy`, with at least 1 ready replica | `LabValidate.bash` |
| E | The Service `dodgy-svc` has at least 1 endpoint address | `LabValidate.bash` |

## Gotchas

- **A Deployment whose selector does not match its own pod template labels
  is refused by the API server, and the error names the mismatch.** This is
  not a silent no-op:

  ```
  error: the Deployment "dodgy-app" is invalid: spec.template.metadata.labels:
    Invalid value: map[string]string{"app":"dodgy-app"}: `selector` does not
    match template `labels`
  ```

  The API server checks that every label in `spec.selector.matchLabels` is
  present, with the same value, in the pod template's labels. It refuses to
  create the object otherwise, because a Deployment that selects nothing is
  not a Deployment.

- **The error is only half the story.** Read the whole message: the fix is
  to make the two agree, and either side can be changed. Changing the
  selector to `app: dodgy-app` is the usual answer, because the Service
  already selects `app: dodgy-app` — change the template's labels instead
  and the Service would select nothing.

- **A Service whose targetPort does not match any container port resolves
  to no endpoints, and again nothing errors.** The Service is created
  happily, `kubectl get svc` looks perfect, and the Endpoints object is
  empty. The endpoints controller only puts a pod into the Service's
  endpoints when one of the pod's container ports matches the targetPort;
  with the targetPort at 8080 and the container declaring 80, the pod is
  skipped. The symptom is a Service that accepts connections and then
  refuses them.

- **A Deployment with no `replicas` defaults to 1.** The API server fills
  the field in for you. Nothing warns you, and the Deployment looks like it
  says what it should — but one replica is almost never what anyone meant,
  and it is not what the manifest says.

- **The manifest has to be fixed on disk.** The grader reads
  `/tmp/cka-lab/dodgy.yaml` and checks it against the Service's targetPort.
  Applying a corrected copy of the manifest from somewhere else — a heredoc
  in the terminal, a file in the home directory — leaves the file on disk
  wrong, and the grader will not be satisfied by a cluster that happens to
  look right.

- **`kubectl apply` on the broken file fails; `kubectl create` fails too.**
  The rejection comes from the API server, so nothing is created and there
  is no half-created object to clean up. Fix the file and apply it again.

- **Read the applied object back.** `kubectl -n dodgy get deploy dodgy-app -o
  yaml` shows what the API server actually stored, including the replicas it
  defaulted. If the file says two replicas and the object says one, the
  wrong file was applied.

## Environment requirements

- A cluster with at least one node, and registry access for `busybox:1.36`.
- NodePort is not involved, and no special components are needed: this is
  the API server's validation and the endpoints controller, both part of the
  core cluster.
