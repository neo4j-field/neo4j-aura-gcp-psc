variable "project_id" {
  description = "GCP project ID where the Cloud DNS response policy is created."
  type        = string
}

variable "network_self_link" {
  description = "Self link of the consumer VPC that the response policy attaches to."
  type        = string
}

variable "neo4j_orch_subdomain" {
  description = "Orchestrator subdomain from the Neo4j Aura Console, for example production-orch-0042."
  type        = string
}

variable "psc_ip_address" {
  description = "Static internal IP of the PSC endpoint. Used as the A record answer."
  type        = string
}

variable "response_policy_name" {
  description = "Name of the Cloud DNS response policy. Must be RFC1035 compliant."
  type        = string
  default     = "neo4j-psc-rpz"
}

variable "dns_ttl" {
  description = "TTL (seconds) applied to the wildcard A record."
  type        = number
  default     = 300
}
