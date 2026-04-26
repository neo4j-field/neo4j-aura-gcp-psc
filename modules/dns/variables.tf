variable "project_id" {
  description = "GCP project ID where the Cloud DNS response policy is created or reused."
  type        = string
}

variable "network_self_link" {
  description = "Self link of the consumer VPC that the response policy attaches to (used when create_response_policy = true)."
  type        = string
}

variable "neo4j_orch_dns_name" {
  description = "Full orchestrator DNS name from the Aura Console (e.g. production-orch-0792.neo4j.io). Trailing dot is optional and stripped."
  type        = string
}

variable "psc_ip_address" {
  description = "Static internal IP of the PSC endpoint. Used as the A record answer."
  type        = string
}

variable "create_response_policy" {
  description = "When true (default), create the response policy. When false, attach rules to an existing one named existing_response_policy_name."
  type        = bool
  default     = true
}

variable "response_policy_name" {
  description = "Name of the Cloud DNS response policy to create (used when create_response_policy = true). Must be RFC1035 compliant."
  type        = string
  default     = "neo4j-psc-rpz"
}

variable "existing_response_policy_name" {
  description = "Name of an existing Cloud DNS response policy to reuse (used when create_response_policy = false)."
  type        = string
  default     = ""
}

variable "apex_rule_name" {
  description = "Name of the apex response-policy rule. Override this when attaching multiple Aura instances to a single shared response policy, so rule names stay unique."
  type        = string
  default     = "neo4j-apex"
}

variable "wildcard_rule_name" {
  description = "Name of the wildcard response-policy rule. Override this when attaching multiple Aura instances to a single shared response policy, so rule names stay unique."
  type        = string
  default     = "neo4j-wildcard"
}

variable "dns_ttl" {
  description = "TTL (seconds) applied to the apex and wildcard A records."
  type        = number
  default     = 300
}
