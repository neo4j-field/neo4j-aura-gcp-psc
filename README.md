# Neo4j Aura on GCP over Private Service Connect (PSC)

Production-grade Terraform that connects a consumer VPC in `us-west1` to a
Neo4j Aura VDC instance hosted in `us-central1`, entirely over Google's private
backbone. No public internet traversal, no NAT, no VPN.

Based on the official Neo4j Aura guidance at
<https://neo4j.com/docs/aura/security/secure-connections/>. Aura refers to the
GCP PSC service attachment URI as the **Private Link service name** in the
console; the two terms are equivalent.

## Architecture

```
          Consumer project (us-west1)                     Producer project (us-central1)
          +---------------------------------+             +------------------------------+
          | VPC: consumer-vpc               |             | Neo4j Aura VDC               |
          |  +---------------------------+  |   PSC       |  +------------------------+  |
          |  | Subnet 10.10.1.0/24       |  | connection  |  | Service attachment     |  |
          |  |                           |  | <=========> |  | neo4j-<id>-psc         |  |
          |  |  PSC endpoint IP (static) |  |             |  |                        |  |
          |  |  Windows test VM          |  |             |  +------------------------+  |
          |  +---------------------------+  |             +------------------------------+
          |                                 |
          |  Cloud DNS response policy      |
          |  *.production-orch-0042.neo4j.io|
          |     -> PSC endpoint IP          |
          +---------------------------------+
```

Traffic from the Windows VM to `<instance>.production-orch-0042.neo4j.io`
is resolved by the VPC-scoped DNS response policy to the internal PSC IP,
then carried over the Google backbone to the Aura service attachment in
`us-central1`.

## What this deploys

| Module           | Resources                                                          |
| ---------------- | ------------------------------------------------------------------ |
| `networking`     | Custom VPC, subnet, firewall rules (IAP RDP, internal, Neo4j egress on 443/7687/7474/8491) |
| `psc_endpoint`   | Reserved internal IP (`GCE_ENDPOINT`) and PSC forwarding rule       |
| `dns`            | Cloud DNS response policy and wildcard A record                    |
| `test_vm`        | Windows Server 2022 VM, no public IP, Shielded VM, IAP-accessible  |

Port 8491 is included because Aura's Graph Analytics (GDS) workloads use it.
Drop it from `modules/networking/variables.tf` if you do not run GDS.

## Prerequisites

### Tooling

- `terraform` >= 1.5.0
- `gcloud` CLI, authenticated via `gcloud auth application-default login`
- Windows RDP client (Microsoft Remote Desktop on macOS, `mstsc` on Windows)

### GCP IAM (on the consumer project)

The identity running Terraform needs at minimum:

- `roles/compute.networkAdmin` (VPC, subnet, firewall, IP, forwarding rule)
- `roles/compute.instanceAdmin.v1` (test VM)
- `roles/dns.admin` (response policy)
- `roles/iam.serviceAccountUser` (to attach the default compute SA to the VM)
- `roles/iap.tunnelResourceAccessor` (for the user who will RDP via IAP)

### Networking tier

Cross-region PSC (producer in `us-central1`, consumer in `us-west1`) requires
**Premium Tier** networking. Confirm it is the project default:

```bash
gcloud compute project-info describe \
  --project="$PROJECT_ID" \
  --format='value(defaultNetworkTier)'
```

If it returns `STANDARD`, set it to Premium before applying:

```bash
gcloud compute project-info update \
  --default-network-tier=PREMIUM \
  --project="$PROJECT_ID"
```

### Division of work: Aura Console vs Terraform

The setup is split across two sides and two operators:

| Side              | Who does it                 | What it does                                                                  |
| ----------------- | --------------------------- | ----------------------------------------------------------------------------- |
| Producer (Aura)   | Operator, in the Aura Console | Exposes the service attachment, allowlists consumer projects, disables public access |
| Consumer (GCP)    | Terraform in this repo      | Creates VPC, PSC endpoint, DNS override, optional test VM                     |

### Values to collect from the Neo4j Aura Console (before apply)

From **Instance > Network access > Private link** (the Aura Console):

1. **Private Link service name** - goes into `neo4j_service_attachment`. This
   is the underlying GCP service attachment URI and looks like
   `projects/neo4j-aura-prod/regions/us-central1/serviceAttachments/neo4j-abc123-psc`.
2. **Orchestrator subdomain** - goes into `neo4j_orch_subdomain`. Looks like
   `production-orch-0042`. The instance FQDN is
   `<dbid>.production-orch-<orch>.neo4j.io`, and Aura requires a wildcard
   DNS override for `*.production-orch-<orch>.neo4j.io`.
3. **Private URI** - the instance FQDN shown on the instance tile. Use this
   later as the `-Neo4jHost` argument to `validate.ps1`.

### Actions taken in the Aura Console (by the operator, not Terraform)

1. **Before apply:** note down the service attachment URI and orchestrator
   subdomain above.
2. **After apply (accept the connection):** add the consumer project ID
   (value of `consumer_project_id`) to **Target GCP Project IDs** in the Aura
   Console. The producer will not accept the PSC connection until this
   allowlist entry exists, even if Terraform has already created the endpoint.
3. **After validation passes:** toggle **Disable Public Access** on the Aura
   instance. Only do this after the validation script on the Windows VM
   reports all checks passing, or you will lose access to the instance.

## Quick start

```bash
cd neo4j-psc-gcp
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and fill in the required values.

terraform init
terraform plan
terraform apply
```

After apply, Terraform prints a `next_steps` block that walks through the
manual steps below.

## Post-apply manual steps

### 1. Accept the connection on the producer side (Aura Console)

In the Aura Console, add the consumer project ID to **Target GCP Project
IDs** under the instance's private connection settings. The PSC connection
starts in `PENDING` and transitions to `ACCEPTED` once the allowlist entry
matches the project that created the forwarding rule.

Poll the status from your side:

```bash
gcloud compute forwarding-rules describe "$(terraform output -raw psc_forwarding_rule_id | awk -F/ '{print $NF}')" \
  --region="$(terraform output -raw consumer_region 2>/dev/null || echo us-west1)" \
  --format='value(pscConnectionStatus)'
```

It should transition `PENDING` -> `ACCEPTED`.

### 2. Validate connectivity from the Windows test VM

Generate a Windows password:

```bash
terraform output -raw windows_password_reset_command | bash
```

Start the IAP tunnel:

```bash
terraform output -raw iap_rdp_command | bash
# or, from the scripts directory:
./scripts/iap_rdp.sh
```

RDP to `localhost:13389`, then open PowerShell on the VM and run:

```powershell
# Replace with your actual instance hostname from the Aura Console.
.\validate.ps1 `
  -Neo4jHost "abc1.production-orch-0042.neo4j.io" `
  -ExpectedPscIp "10.10.1.5"
```

The script checks DNS resolution and TCP reachability on 7687, 443, 7474.
Exit code 0 means all checks passed.

### 3. Disable public access on the Aura instance (Aura Console)

Only do this after step 2 passes. Toggle **Disable Public Access** on the
instance in the Aura Console. If you disable public access before
validating private connectivity, you will lose access to the Aura instance
from anywhere outside the consumer VPC and will have to re-enable it from
the console to recover.

## How to clean up

```bash
terraform destroy
```

Notes:

- The Neo4j side of the connection must also be removed (delete the private
  endpoint entry in the Aura Console, or ask the Neo4j team to remove it).
- Cloud DNS response policies do not incur data-plane cost on destroy, but
  any in-flight traffic will fail DNS resolution once the policy is gone.

## File layout

```
neo4j-psc-gcp/
|-- main.tf                      # wires modules together
|-- variables.tf                 # root input variables
|-- outputs.tf                   # root outputs (including next_steps)
|-- terraform.tfvars.example     # copy to terraform.tfvars and fill in
|-- modules/
|   |-- networking/              # VPC, subnet, firewall
|   |-- psc_endpoint/            # static IP + PSC forwarding rule
|   |-- dns/                     # response policy + wildcard A record
|   `-- test_vm/                 # Windows Server 2022 VM (no public IP)
`-- scripts/
    |-- validate.ps1             # run on the Windows VM to verify connectivity
    `-- iap_rdp.sh               # start an IAP RDP tunnel to the test VM
```

## Design choices

- **Custom-mode VPC.** Auto-mode creates subnets in every region, which is
  wasteful and makes CIDR planning harder. Custom mode keeps the attack
  surface and routing table minimal.
- **Static internal IP for the PSC endpoint.** The IP is the DNS answer. A
  reserved static IP keeps the DNS record stable across forwarding rule
  recreations.
- **Wildcard A record via Cloud DNS response policy.** A response policy
  attached to the consumer VPC overrides public DNS for `*.<orch>.neo4j.io`
  without hijacking any other lookups. The trailing dot on the `dns_name` is
  required; without it the rule silently fails to match.
- **IAP for RDP instead of a bastion or public IP.** No inbound internet
  exposure, no bastion to patch, and IAM-gated access using
  `roles/iap.tunnelResourceAccessor`.
- **Shielded VM on the test instance.** Secure boot, vTPM, and integrity
  monitoring are on by default because they cost nothing and are table
  stakes for a production baseline.
- **`enable_test_vm` flag.** Lets you keep the test VM in non-prod and
  disable it entirely in prod where it is not needed.

## Common failure modes

| Symptom                                            | Likely cause                                                                                           |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `psc_connection_status` stuck on `PENDING`         | Consumer project ID not added to **Target GCP Project IDs** in the Aura Console.                       |
| DNS resolves to a public IP on the Windows VM      | Response policy not attached to the VPC, or trailing dot missing on `dns_name`.                        |
| `Test-NetConnection` on 7687 fails, DNS is correct | Connection not yet `ACCEPTED`, or Premium Tier not enabled on consumer project.                        |
| `terraform apply` fails on the forwarding rule     | Service attachment URI is wrong, region mismatched, or consumer project not yet on the Aura allowlist. |
| RDP tunnel fails with `permission denied`          | Missing `roles/iap.tunnelResourceAccessor` on the user.                                                |
| Lost access after disabling public access          | Enable it again from the Aura Console, validate private path, then disable.                            |
