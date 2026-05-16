# Cisco Secure Hub example

This example shows the variables to use when the PSC endpoint is deployed in a
customer Secure Hub or common services VPC rather than directly in an
application VPC.

Copy the example to the repository root before running Terraform:

```bash
cp examples/cisco-secure-hub/terraform.tfvars.example terraform.tfvars
terraform init
terraform plan -out=tfplan.binary
terraform apply tfplan.binary
```

The Secure Hub project ID must match the GCP project ID entered in the Aura
network access wizard because that project owns the PSC forwarding rule.

Read the full guide in
[`docs/cisco-secure-hub.md`](../../docs/cisco-secure-hub.md).
