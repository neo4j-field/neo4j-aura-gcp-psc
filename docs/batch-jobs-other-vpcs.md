# Batch Jobs and Workloads in Other VPCs

When you disable public traffic on an Aura instance, any workload that runs outside
the consumer VPC where the PSC endpoint lives will lose connectivity. This covers
data pipelines, scheduled ETL jobs, GKE clusters, Dataflow workers, Cloud Run
services, and anything else running in a VPC that is not the one you originally
configured.

This guide shows how to restore private connectivity for those workloads.

---

## Why it breaks

The Cloud DNS response policy that redirects `<dbid>.<orch>.neo4j.io` to the PSC
endpoint IP is attached to **one VPC network**. VMs in any other VPC resolve the
hostname via public DNS, get Aura's public IP, and are refused.

```
Batch VPC                              Consumer VPC
──────────────────────────────────     ──────────────────────────────────
 Batch job                              Your app servers
   │                                      │
   │ DNS: <dbid>.neo4j.io               │ DNS: <dbid>.neo4j.io → 10.x.x.x ✓
   │ → public DNS: 34.x.x.x ✗           │
   │ Connection refused (public off)      │
```

The fix is to give the batch VPC its own PSC endpoint and DNS override. Multiple
consumer endpoints can point to the same Aura service attachment — you do not need
to re-run the Aura wizard.

---

## The fix: one PSC endpoint per VPC

Each VPC that needs to reach Aura gets its own forwarding rule and Cloud DNS
response policy. The Aura service attachment URI and DNS name are identical
across all of them; only the consumer project and network change.

```
Batch VPC                              Consumer VPC
──────────────────────────────────     ──────────────────────────────────
 PSC endpoint 10.20.0.5                PSC endpoint 10.10.0.50
 DNS override: neo4j.io → 10.20.0.5   DNS override: neo4j.io → 10.10.0.50
     │                                     │
     └──────────────── PSC ────────────────┘
                          │
                    Neo4j Aura VDC
                  (same service attachment)
```

---

## Step 1: Check whether the batch VPC is in the same project

### Same project as the existing PSC endpoint

No Aura wizard change needed. Aura's allowlist is project-scoped: because your
project is already on the allowlist, any new forwarding rule from that project
is accepted automatically.

### Different project

Open the Aura Console, navigate to **Project > Settings > Private endpoints**, and
run the network access wizard again. In **Step 1 of 3**, click **Add project ID**
and add the batch job project's ID. You do not need to go through Step 3 (do not
change the public traffic setting during this wizard run — it is already disabled).

---

## Step 2: Collect the values you need

You will reuse the same two values from the original setup:

| What | Where to find it | Used as |
|------|-----------------|---------|
| Service Attachment URL | Aura Console wizard Step 2 (same as before) | `neo4j_service_attachment` |
| Orchestrator DNS Name | Aura Console wizard Step 2 (same as before) | `neo4j_orch_dns_name` |

The only new value is the batch job project ID and VPC/subnet name.

---

## Step 3: Run Terraform for the batch VPC

Create a new `terraform.tfvars` file (or a new Terraform workspace/directory) for
the batch project. Fill in the three required values and point the network variables
at the batch VPC:

```hcl
# Batch project and region
consumer_project_id = "<your-batch-project-id>"
consumer_region     = "us-central1"   # must match the Aura service attachment region
consumer_zone       = "us-central1-a"

# Same values as your original PSC setup
neo4j_service_attachment = "https://www.googleapis.com/compute/v1/projects/ni-production-rd1p/regions/us-central1/serviceAttachments/db-ingress-private"
neo4j_orch_dns_name      = "production-orch-0792.neo4j.io"

# Use the existing batch VPC instead of creating a new one
create_network        = false
existing_network_name = "<batch-vpc-name>"
existing_subnet_name  = "<batch-subnet-name>"
```

Then apply:

```bash
terraform init
terraform apply
```

Confirm the connection is accepted:

```
psc_connection_status = "ACCEPTED"
```

If it shows `PENDING`, the batch project ID was not added to the Aura allowlist in
Step 1. Re-check that the project ID in the wizard exactly matches
`consumer_project_id` above.

---

## Step 4: Validate from the batch VPC

Run a GCP Connectivity Test from a source inside the batch VPC to the PSC endpoint
IP printed in the Terraform output, on port 7687:

**Network Intelligence > Connectivity Tests > Create**

| Field | Value |
|-------|-------|
| Protocol | tcp |
| Source | Any reachable IP in the batch VPC subnet |
| Destination | `psc_endpoint_ip` from `terraform output` |
| Destination port | 7687 |

A **Reachable** result confirms the forwarding rule and routing are correct.

Then confirm DNS is overriding from inside the batch VPC. SSH into any VM in the
batch VPC and run:

```bash
dig <dbid>.<orch>.neo4j.io +short
```

The response must be the `psc_endpoint_ip` (a `10.x.x.x` address), not Aura's
public IP (`34.x.x.x` or similar). If it returns the public IP, the Cloud DNS
response policy was not attached to the correct network — re-check
`existing_network_name` in your `terraform.tfvars`.

---

## Step 5: Update the connection URI in your batch job

The Aura credentials file you downloaded contains a **public URI**:

```
NEO4J_URI=bolt+s://<dbid>.databases.neo4j.io
```

That hostname uses Aura's public DNS and is not covered by the PSC response policy.
Update the connection string in your batch job to the **private URI**:

```
bolt+s://<dbid>.<orch>.neo4j.io
```

Replace `<orch>` with the orchestrator hostname you collected in Step 2
(for example, `production-orch-0792`). The username and password remain the same.

> **The private URI is the only difference.** Everything else — port, auth, TLS
> settings — is identical to what the batch job used before.

---

## Multiple Aura instances in the same batch VPC

Cloud DNS attaches at most one response policy per VPC. If your batch VPC needs to
reach a second Aura instance, reuse the existing policy instead of creating a new one:

```hcl
create_dns_response_policy        = false
existing_dns_response_policy_name = "neo4j-psc-rpz"   # name from the first run
dns_apex_rule_name                = "neo4j-apex-prod0793"
dns_wildcard_rule_name            = "neo4j-wildcard-prod0793"
```

The `dns_apex_rule_name` and `dns_wildcard_rule_name` overrides prevent collisions
with the rules you added for the first instance.

---

## Workload-specific configuration

### Cloud Dataflow

```bash
gcloud dataflow jobs run my-job \
  --region us-central1 \
  --subnetwork regions/us-central1/subnetworks/<batch-subnet-name> \
  --no-use-public-ips \
  ...
```

`--no-use-public-ips` ensures Dataflow workers launch with internal IPs only and
route DNS through the VPC. The `--subnetwork` flag must point to the subnet in the
batch VPC where the PSC endpoint lives.

### Cloud Batch

```json
{
  "taskGroups": [{ ... }],
  "allocationPolicy": {
    "network": {
      "networkInterfaces": [{
        "network": "projects/<batch-project>/global/networks/<batch-vpc-name>",
        "subnetwork": "projects/<batch-project>/regions/us-central1/subnetworks/<batch-subnet-name>",
        "noExternalIpAddress": true
      }]
    }
  }
}
```

### GKE

If the GKE cluster is already in the batch VPC, Pods on node-pool nodes in that VPC
use the VPC's DNS and will resolve the private hostname automatically once the PSC
endpoint and response policy are applied. Confirm with:

```bash
kubectl run dns-test --image=busybox --restart=Never -- \
  nslookup <dbid>.<orch>.neo4j.io
kubectl logs dns-test
```

Expect the PSC IP (`10.x.x.x`), not a public IP.

### Cloud Run

Cloud Run services need a VPC connector or direct VPC egress configured for the
batch VPC to use the PSC DNS override:

```yaml
# service.yaml
spec:
  template:
    metadata:
      annotations:
        run.googleapis.com/vpc-access-connector: projects/<batch-project>/locations/us-central1/connectors/<connector-name>
        run.googleapis.com/vpc-access-egress: all-traffic
```

The VPC connector must be in the same VPC and region as the PSC endpoint.

### Cloud Build private worker pools

Standard Cloud Build runs in Google-managed infrastructure and cannot reach private
PSC endpoints. Use a **private worker pool** peered to the batch VPC:

```bash
gcloud builds worker-pools create neo4j-pool \
  --region us-central1 \
  --worker-machine-type e2-standard-4 \
  --worker-disk-size 100 \
  --peered-network projects/<batch-project>/global/networks/<batch-vpc-name>
```

Then reference the pool in your build trigger or `cloudbuild.yaml`:

```yaml
options:
  pool:
    name: projects/<batch-project>/locations/us-central1/workerPools/neo4j-pool
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `psc_connection_status = PENDING` | Batch project not allowlisted in Aura | Add batch project ID to the Aura wizard allowlist (Step 1 above) |
| `dig` returns public IP from batch VM | Response policy attached to wrong network | Re-check `existing_network_name` in tfvars matches the actual VPC name |
| Connectivity Test fails at forwarding rule | Region mismatch | `consumer_region` must match the region in the `neo4j_service_attachment` URI |
| Connection refused from batch job | Still using public URI | Update `NEO4J_URI` from `databases.neo4j.io` to `<orch>.neo4j.io` (Step 5 above) |
| `409 already exists` on Terraform apply | Prior partial run left orphaned resources | Set `create_psc_ip = false` / `existing_psc_ip_name = "neo4j-psc-ip"` for the resource that already exists |
