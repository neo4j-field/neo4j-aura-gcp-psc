output "psc_endpoint_ip" {
  description = "Static internal IP of the PSC consumer endpoint. Used to confirm DNS resolution and as the answer for the wildcard A record."
  value       = module.psc_endpoint.psc_ip_address
}

output "psc_forwarding_rule_id" {
  description = "Fully qualified ID of the PSC forwarding rule. Share this with the Neo4j Aura team so they can accept the connection on the producer side."
  value       = module.psc_endpoint.forwarding_rule_id
}

output "psc_connection_status" {
  description = "Current PSC connection status. Will read PENDING until the Neo4j team accepts the connection, then transition to ACCEPTED."
  value       = module.psc_endpoint.psc_connection_status
}

output "dns_rpz_name" {
  description = "Name of the Cloud DNS response policy attached to the consumer VPC."
  value       = module.dns.response_policy_name
}

output "dns_wildcard_name" {
  description = "Wildcard DNS name overridden by the response policy."
  value       = module.dns.wildcard_dns_name
}

# ---------------------------------------------------------------------------
# Windows browser VM (optional)
# ---------------------------------------------------------------------------

output "windows_vm_name" {
  description = "Name of the Windows browser VM (null when enable_windows_browser_vm = false)."
  value       = var.enable_windows_browser_vm ? module.test_vm_windows[0].instance_name : null
}

output "windows_vm_zone" {
  description = "Zone of the Windows browser VM (null when enable_windows_browser_vm = false)."
  value       = var.enable_windows_browser_vm ? module.test_vm_windows[0].zone : null
}

output "windows_vm_internal_ip" {
  description = "Internal IP of the Windows browser VM (null when enable_windows_browser_vm = false)."
  value       = var.enable_windows_browser_vm ? module.test_vm_windows[0].internal_ip : null
}

output "windows_vm_public_ip" {
  description = "External IP of the Windows browser VM (null when no public IP is attached)."
  value       = var.enable_windows_browser_vm ? module.test_vm_windows[0].public_ip : null
}

output "iap_rdp_command" {
  description = "Ready-to-run gcloud command that opens an IAP tunnel for RDP on localhost:13389 (null when enable_windows_browser_vm = false)."
  value = var.enable_windows_browser_vm ? format(
    "gcloud compute start-iap-tunnel %s 3389 --local-host-port=localhost:13389 --zone=%s --project=%s",
    module.test_vm_windows[0].instance_name,
    var.consumer_zone,
    var.consumer_project_id,
  ) : null
}

output "windows_password_reset_command" {
  description = "gcloud command to generate an initial Windows password for RDP login (null when enable_windows_browser_vm = false)."
  value = var.enable_windows_browser_vm ? format(
    "gcloud compute reset-windows-password %s --zone=%s --project=%s",
    module.test_vm_windows[0].instance_name,
    var.consumer_zone,
    var.consumer_project_id,
  ) : null
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

    3. (Optional) Only if you want to exercise the Neo4j Browser UI over the
       private URI: set enable_windows_browser_vm = true in terraform.tfvars and
       re-apply, then RDP into the Windows VM.

    4. After step 2 (and optionally step 3) passes, open the Aura network access
       wizard in the console, walk through to Step 3 of 3, check "Disable public
       traffic", and save. From that point on, only the PSC path reaches the
       instance.

    5. If producer and consumer regions differ, cross-region PSC requires Premium
       Tier networking. For same-region setups (both in ${var.consumer_region})
       Premium Tier is not required.

  EOT
}
