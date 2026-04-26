variable "project_id" {
  description = "GCP project ID where the PSC consumer endpoint is created."
  type        = string
}

variable "region" {
  description = "Consumer region for the static internal IP and PSC forwarding rule."
  type        = string
}

variable "network_self_link" {
  description = "Self link of the consumer VPC."
  type        = string
}

variable "subnet_self_link" {
  description = "Self link of the consumer subnet that provides the PSC endpoint IP."
  type        = string
}

variable "create_psc_ip" {
  description = "When true (default), reserve a new static internal IP. When false, look up an existing IP via existing_psc_ip_name."
  type        = bool
  default     = true
}

variable "psc_ip_name" {
  description = "Name of the static internal IP to reserve (used when create_psc_ip = true)."
  type        = string
  default     = ""
}

variable "existing_psc_ip_name" {
  description = "Name of an existing reserved internal IP to reuse (used when create_psc_ip = false)."
  type        = string
  default     = ""
}

variable "create_psc_endpoint" {
  description = "When true (default), create the PSC forwarding rule. When false, look up an existing rule via existing_psc_endpoint_name and skip creation."
  type        = bool
  default     = true
}

variable "psc_endpoint_name" {
  description = "Name of the PSC forwarding rule to create (used when create_psc_endpoint = true)."
  type        = string
  default     = ""
}

variable "existing_psc_endpoint_name" {
  description = "Name of an existing PSC forwarding rule to reuse (used when create_psc_endpoint = false)."
  type        = string
  default     = ""
}

variable "neo4j_service_attachment" {
  description = "The producer-side PSC service attachment URI from the Neo4j Aura Console."
  type        = string
}

variable "common_labels" {
  description = "Labels applied to resources that support labels."
  type        = map(string)
  default     = {}
}
