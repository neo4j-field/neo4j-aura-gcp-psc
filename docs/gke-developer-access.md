# Accessing Neo4j Aura PSC via a GKE Cluster

This guide covers a scenario where developers cannot reach Neo4j Aura over a
private interconnect — either because the interconnect doesn't exist or because
corporate policy prohibits developer traffic on it — and public traffic to Aura
is disabled. All traffic must leave the developer's laptop over the public
internet, enter a foothold inside the consumer VPC, and proxy from there to the
PSC endpoint.

Two patterns satisfy this constraint:

- **Option A — IAP TCP Forwarding** — an SSH tunnel through Google's Identity
  Aware Proxy to a bastion VM in the consumer VPC. The bastion proxies to the
  PSC endpoint.
- **Option B — GKE DNS Endpoint** — connect to a GKE cluster's control plane
  via its public DNS endpoint, exec into a pod, and proxy from the pod to the
  PSC endpoint. No extra VM required.

If you haven't set up a bastion before, start with Option A — it requires no
existing GKE cluster and the Terraform in this repo includes a ready-to-use
bastion module. If your team already runs a GKE cluster in the consumer VPC,
Option B skips the VM entirely.

---

## Option A — IAP TCP Forwarding

IAP TCP forwarding opens an encrypted tunnel from your laptop to a bastion VM
inside the consumer VPC. The traffic leaves your laptop over HTTPS (TCP/443) to
Google's edge, enters Google's private backbone, and terminates on the bastion.
The bastion's `socat` proxy then forwards it to the PSC endpoint IP.

This option uses only `gcloud` CLI and the bastion module already included in
this repo. For the complete walkthrough — Terraform setup, bastion deployment,
`/etc/hosts` configuration, port-forward commands, and Neo4j Desktop connection
steps — see [`developer-desktop-access.md`](developer-desktop-access.md).

---

## Option B — GKE DNS Endpoint

GKE's DNS-based control-plane endpoint lets `kubectl` reach a private GKE
cluster over the public internet without routing through a VPN or private
interconnect. Once you have a shell in a pod inside the cluster, that pod is
inside the consumer VPC and can reach the PSC endpoint IP directly.

### What you will build

```
Your laptop
  │
  │  kubectl (HTTPS/443 to GKE DNS endpoint — public internet)
  ▼
GKE cluster control plane
  │
  │  kubectl exec into pod in consumer VPC
  ▼
Pod (consumer VPC)
  │
  │  direct TCP to PSC endpoint IP
  ▼
PSC endpoint  →  Neo4j Aura VDC
```

### Prerequisites

- A GKE cluster running in the same VPC as the PSC endpoint.
- `gcloud` CLI authenticated; `kubectl` configured for the cluster.
- The PSC endpoint IP (from `terraform output psc_endpoint_ip`).

### Step 1: Enable the DNS-based endpoint on your cluster

The DNS endpoint exposes the GKE control plane under a stable public hostname,
allowing `kubectl` to connect without access to the private master IP.

```bash
gcloud container clusters update CLUSTER_NAME \
  --region REGION \
  --enable-dns-endpoint
```

Reference:

- [GKE DNS-based endpoint concept](https://cloud.google.com/kubernetes-engine/docs/concepts/network-isolation#dns-based_endpoint)
- [GKE blog announcement](https://cloud.google.com/blog/products/containers-kubernetes/new-dns-based-endpoint-for-the-gke-control-plane)

### Step 2: Fetch credentials and verify cluster access

```bash
gcloud container clusters get-credentials CLUSTER_NAME \
  --region REGION \
  --project PROJECT_ID

kubectl get nodes
```

`kubectl get nodes` should return your cluster's node list without requiring a
VPN connection. If it hangs, confirm the DNS endpoint feature is enabled in the
GCP Console under **Kubernetes Engine > Clusters > your cluster > Networking**.

### Step 3: Open a shell in a running pod

List pods to find one to use as a jump point:

```bash
kubectl get pods --all-namespaces
```

Exec into it:

```bash
kubectl exec -it POD_NAME -n NAMESPACE -- /bin/sh
```

Reference: [Get a shell to a running container](https://kubernetes.io/docs/tasks/debug/debug-application/get-shell-running-container/)

If no suitable pod is running, deploy a minimal one:

```bash
kubectl run neo4j-proxy --image=busybox --restart=Never -- sleep 3600
kubectl exec -it neo4j-proxy -- /bin/sh
```

### Step 4: Verify connectivity to the PSC endpoint from the pod

From inside the pod shell, probe the PSC endpoint IP on the Bolt port:

```bash
# Replace 10.x.x.x with your psc_endpoint_ip from terraform output
nc -zv 10.x.x.x 7687 && echo "Bolt reachable"
nc -zv 10.x.x.x 7474 && echo "Browser reachable"
```

Both should return immediately with a connection success. If they time out,
check that the pod's VPC subnet routes to the PSC endpoint — confirm the PSC
forwarding rule status is `ACCEPTED` in the GCP Console.

### Step 5: Forward ports to your laptop for desktop access

For Neo4j Desktop or browser access from your laptop, open a port-forward in a
**separate terminal** on your laptop (not inside the pod):

```bash
kubectl port-forward pod/POD_NAME \
  7687:7687 \
  7474:7474 \
  7473:7473 \
  -n NAMESPACE
```

This binds those ports on `localhost` and tunnels them through the GKE DNS
endpoint to the pod. The pod, inside the consumer VPC, has direct access to the
PSC endpoint IP.

Then follow the `/etc/hosts` and Neo4j Desktop steps from
[`developer-desktop-access.md`](developer-desktop-access.md#step-2-add-the-neo4j-hostname-to-etchosts)
— the routing is identical; the pod replaces the bastion VM.

---

## Comparison

| | Option A — IAP SSH Tunnel | Option B — GKE DNS Endpoint |
|-|--------------------------|-----------------------------|
| Requires a VM | Yes (e2-micro bastion) | No — reuses existing cluster |
| Requires a GKE cluster | No | Yes |
| Extra software on laptop | `gcloud` | `gcloud` + `kubectl` |
| `/etc/hosts` change needed | Yes | Yes |
| Traverses public internet | Yes (IAP to Google edge) | Yes (GKE DNS endpoint) |
| IAM to configure | `roles/iap.tunnelResourceAccessor` | GKE RBAC + `roles/container.developer` |
| Audit trail | Cloud Audit Logs (IAP) | Cloud Audit Logs (GKE) |
| Cost | e2-micro (~$7/mo) | No additional cost |

**Use Option A** when no GKE cluster exists in the consumer VPC or when you
prefer a dedicated, single-purpose bastion not shared with running workloads.

**Use Option B** when your team already has a GKE cluster in the consumer VPC
and wants to reach the PSC endpoint without provisioning an extra VM.
