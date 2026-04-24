# Initial design brief

This document captures the original brief that seeded the Terraform project.
It is preserved verbatim (with cosmetic edits for Markdown) so reviewers can
see the intended shape before any iteration.

## Goal

Build a production-ready GCP Private Service Connect (PSC) setup that
connects a consumer VPC to a Neo4j Aura VDC instance, entirely over GCP's
private backbone with no public internet traversal.

## Context (original)

- Neo4j Aura VDC (producer) was initially assumed to be in GCP `us-east1`.
- Consumer workloads were initially assumed to be in GCP `us-west1`.
- Mechanism: GCP Private Service Connect (PSC), not AWS PrivateLink.
- After setup, a Windows Server VM in the consumer region must reach Neo4j
  on ports 443, 7687, and 7474 using private IPs only.
- DNS is handled via a Cloud DNS Response Policy Zone (RPZ) with a wildcard
  A record.

Both assumptions changed during iteration; see `iteration_notes.md`.

## Target structure

```
neo4j-psc-gcp/
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars.example
├── modules/
│   ├── networking/        # VPC, subnet, firewall rules
│   ├── psc_endpoint/      # Static IP + PSC forwarding rule
│   ├── dns/               # Cloud DNS RPZ + wildcard A record
│   └── test_vm/           # Windows Server 2022 VM (no public IP, IAP-accessible)
├── scripts/
│   ├── validate.ps1       # PowerShell test script to run ON the Windows VM
│   └── iap_rdp.sh         # Helper to start the IAP RDP tunnel
└── README.md
```

## Terraform requirements (summarized)

- Google provider pinned `~> 5.0`; Terraform `>= 1.5.0`.
- Custom-mode VPC, regional subnet with `private_ip_google_access = true`.
- Firewall: egress to Neo4j ports inside the subnet CIDR, ingress RDP from
  the IAP range `35.235.240.0/20` on tag `rdp-iap`, ingress all-from-VPC
  on tag `internal`.
- PSC endpoint: `google_compute_address` with `purpose = GCE_ENDPOINT`
  plus `google_compute_forwarding_rule` with `load_balancing_scheme = ""`
  targeting the Aura service attachment.
- DNS: `google_dns_response_policy` attached to the consumer VPC with a
  wildcard `*.<orch>.neo4j.io.` A-record rule pointing at the PSC IP.
- Test VM: Windows Server 2022, Shielded VM, no public IP, accessible
  only via IAP tunnel.
- Required inputs: `consumer_project_id`, `consumer_region`, `consumer_zone`,
  `neo4j_service_attachment`, `neo4j_orch_subdomain`.
- Feature flag `enable_test_vm` for prod-only deploys.

## Validation

- PowerShell `validate.ps1` run on the Windows VM: DNS resolution against
  the expected PSC IP, Test-NetConnection on 7687 / 443 / 7474, pass/fail
  summary, exit code 0 on success.
- Bash `iap_rdp.sh` helper wraps `gcloud compute start-iap-tunnel`.

## Quality bar

- `terraform fmt -recursive` clean.
- `terraform validate` green.
- All resources carry labels `neo4j-psc = "true"` and `managed-by = "terraform"`.
- No hardcoded project IDs, regions, or IPs anywhere in module source.
- Every resource has a meaningful `description` where supported.
