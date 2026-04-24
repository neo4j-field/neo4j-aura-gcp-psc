# Iteration notes

What changed between the initial design brief and the shipped code, and why.
Ordered roughly by when each decision was made.

## 1. Producer region is `us-central1`, not `us-east1`

The original brief assumed the Aura producer lived in `us-east1`. The actual
service attachment URI from the Aura Console was in `us-central1`:

```
https://www.googleapis.com/compute/v1/projects/ni-production-rd1p/regions/us-central1/serviceAttachments/db-ingress-private
```

This is a shared Aura ingress pattern (`ni-production-rd1p` / `db-ingress-private`)
used for all Aura GCP private connections in that region. All README examples
were updated accordingly, and the `neo4j_service_attachment` variable
validation regex was relaxed to accept both the short form
(`projects/.../serviceAttachments/...`) and the full
`https://www.googleapis.com/compute/v1/...` URL form.

## 2. Consumer region moved to `us-central1` to match

Once the producer was confirmed in `us-central1`, the consumer region was
moved from `us-west1` to `us-central1` as well. Same-region PSC is lower
latency and does not require Premium Tier networking, which cross-region
does. The `next_steps` output was updated to note Premium Tier is only
required when regions differ.

## 3. Port 8491 added for Graph Analytics

The initial brief called for ports 443, 7687, and 7474. The official Aura
secure-connections guide (`neo4j.com/docs/aura/security/secure-connections/`)
also lists port 8491 for Graph Analytics workloads. Added 8491 to:

- `modules/networking/variables.tf`'s default `neo4j_ports` list
- `scripts/validate.ps1` TCP check loop
- README port callout

## 4. Two DNS rules instead of one

The Aura public docs call out a wildcard record
`*.production-orch-<orch>.neo4j.io`. The in-console setup instructions,
however, use the apex name `production-orch-<orch>.neo4j.io` directly.
Since Cloud DNS response policy rules do not perform subtree matching,
only the exact or wildcard-matched names resolve. To cover both cases
(driver connecting to `<dbid>.production-orch-NNNN.neo4j.io` and any
lookup against the apex itself), the DNS module creates both rules:

- `google_dns_response_policy_rule.neo4j_apex`
- `google_dns_response_policy_rule.neo4j_wildcard`

## 5. Aura terminology: "Private Link service name"

In the Aura Console UI the PSC service attachment URI is called the
**Private Link service name**. The `neo4j_service_attachment` variable
description was updated to reflect this, and the README calls out the
mapping so users looking at the console do not hunt for a field called
"service attachment URI".

## 6. Aura Console responsibilities kept out of Terraform

The Aura side of the connection (adding the consumer project to
"Target GCP Project IDs", and later toggling "Disable Public Access")
is explicitly documented as a console-side operator step rather than
automated via Terraform. This matches the split defined in the Aura
secure-connections guide and keeps the Terraform project scoped to the
consumer side only. The `next_steps` output and README each list the
console-side steps in order.

## 7. Reuse of the existing default VPC

Rather than creating a dedicated `consumer-vpc`, the final deployment
reuses the existing `default` VPC and `default` subnet in the consumer
project. Reasons:

- A pre-existing test VM lived in `default`; keeping the PSC endpoint in
  the same VPC avoids VPC-peering complexity for DNS and routing.
- GCP's default-VPC firewall rules already cover intra-VPC and IAP flows.

The `networking` module was refactored to support both modes via
`create_network`. When false, the module falls back to data-source lookups
of an existing VPC and subnet and skips creating any firewall rules.

## 8. Windows test VM replaced the existing Linux VM

The pre-existing test VM was a Debian 12 instance despite being named
`my-win-test-psc-privatelink-test`. Since the validation workflow
(including `validate.ps1`) assumes Windows, the Debian VM was terminated
and Terraform was allowed to create a Windows Server 2022 VM in the same
default VPC and zone (`us-central1-a`).

## 9. Public IP attached to the test VM

By default the test VM has no public IP and is reached via IAP tunnel
(`scripts/iap_rdp.sh`). A `enable_vm_public_ip` flag was added to allow
attaching an ephemeral external IP for direct RDP access during
validation. This is faster to use but relies on the default VPC's
`default-allow-rdp` (0.0.0.0/0) firewall rule for inbound RDP. That rule
should be tightened to a source CIDR list before leaving the VM
running for any length of time. The flag defaults to false.

## 10. Terraform version landed on 1.14.9

Local install was done by downloading the official HashiCorp
`terraform_1.14.9_darwin_arm64.zip` with SHA256 verification, bypassing
Homebrew and Command Line Tools entirely (the macOS CLT on this machine
did not support the current OS release). The Terraform binary lives in
`~/.local/bin/terraform`, which was already on `$PATH`.
