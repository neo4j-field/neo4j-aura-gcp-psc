output "response_policy_name" {
  description = "Name of the Cloud DNS response policy attached to the consumer VPC."
  value       = google_dns_response_policy.neo4j.response_policy_name
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
  description = "ID of the Cloud DNS response policy."
  value       = google_dns_response_policy.neo4j.id
}
