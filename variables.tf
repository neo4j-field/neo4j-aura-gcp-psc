variable "consumer_project_id" {
  description = "GCP project ID for the consumer side of the PSC connection."
  type        = string
}

variable "consumer_region" {
  description = "Consumer region for the VPC, subnet, and PSC endpoint."
  type        = string
  default     = "us-west1"
}

variable "consumer_zone" {
  description = "Consumer zone. Reserved for future per-zone resources; not currently used by any module."
  type        = string
  default     = "us-west1-a"
}

variable "create_network" {
  description = "When true (default), Terraform creates a new VPC, subnet, and firewall rules. When false, it reuses an existing VPC and subnet and skips firewall creation."
  type        = bool
  default     = true
}

variable "vpc_name" {
  description = "Name of the consumer VPC to create (used when create_network = true)."
  type        = string
  default     = "consumer-vpc"
}

variable "subnet_name" {
  description = "Name of the consumer subnet to create (used when create_network = true)."
  type        = string
  default     = "consumer-subnet"
}

variable "subnet_cidr" {
  description = "Primary CIDR range of the consumer subnet (used when create_network = true)."
  type        = string
  default     = "10.10.1.0/24"
}

variable "existing_network_name" {
  description = "Name of the existing VPC to reuse (used when create_network = false). Example: default."
  type        = string
  default     = ""
}

variable "existing_subnet_name" {
  description = "Name of the existing regional subnet to reuse (used when create_network = false). Example: default."
  type        = string
  default     = ""
}

variable "neo4j_service_attachment" {
  description = <<-EOT
    The PSC service attachment URI from the Aura Console. Aura labels this the
    "Private Link service name" under Instance > Network access > Private link.
    Accepts either the short form or the full compute v1 URL:
      projects/<aura-project>/regions/<region>/serviceAttachments/<name>
      https://www.googleapis.com/compute/v1/projects/<aura-project>/regions/<region>/serviceAttachments/<name>
    Example: https://www.googleapis.com/compute/v1/projects/ni-production-rd1p/regions/us-central1/serviceAttachments/db-ingress-private
  EOT
  type        = string

  validation {
    condition     = can(regex("^(https://www\\.googleapis\\.com/compute/v1/)?projects/[^/]+/regions/[^/]+/serviceAttachments/[^/]+$", var.neo4j_service_attachment))
    error_message = "neo4j_service_attachment must be a PSC service attachment in either short (projects/.../serviceAttachments/...) or full URL form."
  }
}

variable "neo4j_orch_dns_name" {
  description = <<-EOT
    Full orchestrator DNS name from the Neo4j Aura Console (wizard Step 2 of 3 >
    "DNS Name"). Paste the value verbatim, including the .neo4j.io suffix.
    A trailing dot is allowed and stripped automatically.
    Example: production-orch-0792.neo4j.io
    The module creates both an apex A record at this hostname and a wildcard
    A record at *.<this hostname>, both pointing at the PSC endpoint internal IP.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+\\.neo4j\\.io\\.?$", var.neo4j_orch_dns_name))
    error_message = "neo4j_orch_dns_name must be the full hostname from the Aura Console, e.g. production-orch-0792.neo4j.io."
  }
}

# ---------------------------------------------------------------------------
# PSC endpoint resources. Each can be created or reused via an existing name.
# Set create_* = false and existing_*_name = "<name>" to skip creation and
# look up an existing resource (useful for re-runs, partial-apply recovery,
# or shared infrastructure).
# ---------------------------------------------------------------------------

variable "create_psc_ip" {
  description = "When true (default), create the static internal IP for the PSC endpoint. Set to false to reuse an existing reserved IP via existing_psc_ip_name."
  type        = bool
  default     = true
}

variable "psc_ip_name" {
  description = "Name of the static internal IP (used when create_psc_ip = true)."
  type        = string
  default     = "neo4j-psc-ip"
}

variable "existing_psc_ip_name" {
  description = "Name of an existing reserved internal IP to reuse (used when create_psc_ip = false)."
  type        = string
  default     = ""
}

variable "create_psc_endpoint" {
  description = "When true (default), create the PSC forwarding rule. Set to false to reuse an existing forwarding rule via existing_psc_endpoint_name (rare; usually you only reuse the IP, not the endpoint)."
  type        = bool
  default     = true
}

variable "psc_endpoint_name" {
  description = "Name of the PSC forwarding rule (used when create_psc_endpoint = true)."
  type        = string
  default     = "neo4j-psc-endpoint"
}

variable "existing_psc_endpoint_name" {
  description = "Name of an existing PSC forwarding rule to reuse (used when create_psc_endpoint = false)."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Cloud DNS response policy. A single VPC can hold only one response policy
# per network attachment, so when running this module against a VPC that
# already has one (e.g. for another Aura instance), reuse it instead of
# creating a second.
# ---------------------------------------------------------------------------

variable "create_dns_response_policy" {
  description = "When true (default), create the Cloud DNS response policy. Set to false to attach apex/wildcard rules to an existing response policy via existing_dns_response_policy_name."
  type        = bool
  default     = true
}

variable "dns_response_policy_name" {
  description = "Name of the Cloud DNS response policy (used when create_dns_response_policy = true)."
  type        = string
  default     = "neo4j-psc-rpz"
}

variable "existing_dns_response_policy_name" {
  description = "Name of an existing Cloud DNS response policy to reuse (used when create_dns_response_policy = false). The apex and wildcard rules are added under this policy."
  type        = string
  default     = ""
}

variable "dns_apex_rule_name" {
  description = "Name of the apex DNS response-policy rule. Override only when sharing one response policy across multiple Aura instances, so rule names stay unique."
  type        = string
  default     = "neo4j-apex"
}

variable "dns_wildcard_rule_name" {
  description = "Name of the wildcard DNS response-policy rule. Override only when sharing one response policy across multiple Aura instances, so rule names stay unique."
  type        = string
  default     = "neo4j-wildcard"
}

variable "extra_labels" {
  description = "Additional labels merged on top of the default neo4j-psc/managed-by labels."
  type        = map(string)
  default     = {}
}
