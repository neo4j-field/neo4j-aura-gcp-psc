output "psc_ip_address" {
  description = "Static internal IP bound to the PSC endpoint. Used as the answer for the apex and wildcard A records."
  value       = local.psc_ip_value
}

output "psc_ip_self_link" {
  description = "Self link of the reserved PSC internal IP."
  value       = local.psc_ip_self_link
}

output "forwarding_rule_id" {
  description = "Fully qualified ID of the PSC forwarding rule."
  value       = local.forwarding_rule_id
}

output "forwarding_rule_self_link" {
  description = "Self link of the PSC forwarding rule."
  value       = local.forwarding_rule_self_link
}

output "psc_connection_id" {
  description = "PSC connection ID reported by the producer service (present once the producer accepts the connection)."
  value       = local.psc_connection_id
}

output "psc_connection_status" {
  description = "PSC connection status (ACCEPTED, PENDING, REJECTED, CLOSED)."
  value       = local.psc_connection_status
}
