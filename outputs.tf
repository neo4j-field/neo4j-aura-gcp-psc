output "psc_endpoint_ip" {
  description = "Static internal IP of the PSC consumer endpoint. Used to confirm DNS resolution and as the answer for the apex and wildcard A records."
  value       = module.psc_endpoint.psc_ip_address
}

output "psc_forwarding_rule_id" {
  description = "Fully qualified ID of the PSC forwarding rule. Share this with the Neo4j Aura team only if they ask; the consumer project ID allowlist is the primary handshake."
  value       = module.psc_endpoint.forwarding_rule_id
}

output "psc_connection_status" {
  description = "Current PSC connection status. Will read PENDING until the producer accepts the connection, then transition to ACCEPTED."
  value       = module.psc_endpoint.psc_connection_status
}

output "dns_response_policy_name" {
  description = "Name of the Cloud DNS response policy attached to the consumer VPC."
  value       = module.dns.response_policy_name
}

output "dns_apex_name" {
  description = "Apex DNS name overridden by the response policy."
  value       = module.dns.apex_dns_name
}

output "dns_wildcard_name" {
  description = "Wildcard DNS name overridden by the response policy."
  value       = module.dns.wildcard_dns_name
}

output "next_steps" {
  description = "Human-readable checklist of manual steps remaining after terraform apply."
  value       = <<-EOT

    Manual steps after terraform apply:

    1. Verify the connection is ACCEPTED (both in Terraform output and in the GCP
       Console at Network services > Private Service Connect > Connected endpoints).
       If it shows PENDING, re-check the consumer project ID on the Aura side:
           ${var.consumer_project_id}

    2. (Recommended) Run a GCP Connectivity Test to prove the PSC path:
       Network Intelligence > Connectivity Tests > Create. Source = any reachable
       source in the same VPC (a one-off test VM works), destination = the PSC
       endpoint, protocol tcp, port 7687. A "Reachable" result on both the forward
       and return traces confirms the routed path.

    3. After step 2 passes, open the Aura network access wizard in the console,
       walk through to Step 3 of 3, check "Disable public traffic", and save.
       From that point on, only the PSC path reaches the instance.

    4. If producer and consumer regions differ, cross-region PSC requires Premium
       Tier networking. For same-region setups (both in ${var.consumer_region})
       Premium Tier is not required.

  EOT
}
