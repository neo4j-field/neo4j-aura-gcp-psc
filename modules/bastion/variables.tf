variable "project_id" {
  description = "GCP project ID where the bastion VM is created."
  type        = string
}

variable "zone" {
  description = "Zone for the bastion VM. Must be in the same region as the PSC endpoint."
  type        = string
}

variable "network_self_link" {
  description = "Self-link of the consumer VPC network."
  type        = string
}

variable "subnet_self_link" {
  description = "Self-link of the consumer subnet. The bastion receives an internal IP from this range."
  type        = string
}

variable "neo4j_psc_ip" {
  description = "Static internal IP of the PSC consumer endpoint (from module.psc_endpoint.psc_ip_address). The bastion's socat proxies forward to this address."
  type        = string
}

variable "bastion_name" {
  description = "Name of the bastion VM."
  type        = string
  default     = "neo4j-bastion"
}

variable "machine_type" {
  description = "Machine type for the bastion VM. e2-micro is sufficient for a developer tunnel."
  type        = string
  default     = "e2-micro"
}

variable "neo4j_ports" {
  description = "TCP ports the bastion proxies to the PSC endpoint."
  type        = list(number)
  default     = [7687, 7474, 7473, 8491]
}

variable "common_labels" {
  description = "Labels applied to all resources in this module."
  type        = map(string)
  default     = {}
}
