output "response_policy_name" {
  description = "Name of the Cloud DNS response policy carrying the apex and wildcard rules."
  value       = local.effective_policy_name
}

output "wildcard_dns_name" {
  description = "The wildcard DNS name overridden by the response policy."
  value       = local.wildcard_dns_name
}

output "apex_dns_name" {
  description = "The apex orchestrator DNS name overridden by the response policy."
  value       = local.apex_dns_name
}

output "response_policy_id" {
  description = "ID of the Cloud DNS response policy (only populated when this module created it)."
  value       = var.create_response_policy ? google_dns_response_policy.neo4j[0].id : null
}
