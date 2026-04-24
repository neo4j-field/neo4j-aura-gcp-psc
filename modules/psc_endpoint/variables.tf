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

variable "psc_ip_name" {
  description = "Name of the static internal IP reserved for the PSC endpoint."
  type        = string
}

variable "psc_endpoint_name" {
  description = "Name of the PSC forwarding rule (the consumer endpoint)."
  type        = string
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
