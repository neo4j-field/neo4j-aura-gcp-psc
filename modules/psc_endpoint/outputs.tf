output "psc_ip_address" {
  description = "Static internal IP bound to the PSC endpoint. Used as the answer for the DNS wildcard."
  value       = google_compute_address.psc.address
}

output "psc_ip_self_link" {
  description = "Self link of the reserved PSC internal IP."
  value       = google_compute_address.psc.self_link
}

output "forwarding_rule_id" {
  description = "Fully qualified ID of the PSC forwarding rule. Share this with the Neo4j Aura team so they can accept the connection."
  value       = google_compute_forwarding_rule.psc.id
}

output "forwarding_rule_self_link" {
  description = "Self link of the PSC forwarding rule."
  value       = google_compute_forwarding_rule.psc.self_link
}

output "psc_connection_id" {
  description = "PSC connection ID reported by the producer service (present once the producer accepts the connection)."
  value       = google_compute_forwarding_rule.psc.psc_connection_id
}

output "psc_connection_status" {
  description = "PSC connection status (ACCEPTED, PENDING, REJECTED, CLOSED)."
  value       = google_compute_forwarding_rule.psc.psc_connection_status
}
