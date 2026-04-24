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

output "windows_vm_name" {
  description = "Name of the Windows test VM (null when enable_test_vm = false)."
  value       = var.enable_test_vm ? module.test_vm[0].instance_name : null
}

output "windows_vm_zone" {
  description = "Zone of the Windows test VM (null when enable_test_vm = false)."
  value       = var.enable_test_vm ? module.test_vm[0].zone : null
}

output "windows_vm_internal_ip" {
  description = "Internal IP of the Windows test VM (null when enable_test_vm = false)."
  value       = var.enable_test_vm ? module.test_vm[0].internal_ip : null
}

output "windows_vm_public_ip" {
  description = "External IP of the Windows test VM (null when no public IP is attached)."
  value       = var.enable_test_vm ? module.test_vm[0].public_ip : null
}

output "iap_rdp_command" {
  description = "Ready-to-run gcloud command that opens an IAP tunnel for RDP on localhost:13389."
  value = var.enable_test_vm ? format(
    "gcloud compute start-iap-tunnel %s 3389 --local-host-port=localhost:13389 --zone=%s --project=%s",
    module.test_vm[0].instance_name,
    var.consumer_zone,
    var.consumer_project_id,
  ) : null
}

output "windows_password_reset_command" {
  description = "gcloud command to generate an initial Windows password for RDP login."
  value = var.enable_test_vm ? format(
    "gcloud compute reset-windows-password %s --zone=%s --project=%s",
    module.test_vm[0].instance_name,
    var.consumer_zone,
    var.consumer_project_id,
  ) : null
}

output "next_steps" {
  description = "Human-readable checklist of manual steps remaining after terraform apply. Steps 1 and 4 are performed by the operator in the Neo4j Aura Console."
  value       = <<-EOT

    Manual steps after terraform apply (operator performs in the Aura Console):

    1. In the Aura Console > Instance > Network access > Private connection, add the
       consumer project ID to "Target GCP Project IDs":
           ${var.consumer_project_id}
       Without this allowlist entry, the producer will not accept the connection even
       though Terraform has created the endpoint on the consumer side.

    2. Confirm the connection transitions from PENDING to ACCEPTED:
         gcloud compute forwarding-rules describe ${var.psc_endpoint_name} \
           --region=${var.consumer_region} --project=${var.consumer_project_id} \
           --format='value(pscConnectionStatus)'

    3. RDP into the Windows test VM via IAP using the iap_rdp_command output, then run
       scripts\validate.ps1 to verify DNS resolution and port reachability on 443,
       7687, and 7474.

    4. Only after step 3 passes: toggle "Disable Public Access" in the Aura Console to
       force all traffic through PSC. If you disable public access before validating
       private connectivity, you will lose access to the instance.

    5. If producer and consumer regions differ, cross-region PSC requires Premium Tier
       networking. For same-region setups (producer and consumer both in ${var.consumer_region})
       Premium Tier is not required.

  EOT
}
