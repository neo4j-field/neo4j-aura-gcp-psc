variable "project_id" {
  description = "GCP project ID where the consumer network is created or referenced."
  type        = string
}

variable "region" {
  description = "GCP region for the consumer subnet."
  type        = string
}

variable "create_network" {
  description = "When true (default), create a new VPC, subnet, and firewall rules. When false, look up an existing VPC and subnet via data sources and skip firewall creation."
  type        = bool
  default     = true
}

variable "vpc_name" {
  description = "Name of the VPC to create (when create_network = true)."
  type        = string
  default     = ""
}

variable "subnet_name" {
  description = "Name of the subnet to create (when create_network = true)."
  type        = string
  default     = ""
}

variable "subnet_cidr" {
  description = "Primary CIDR range of the subnet to create (when create_network = true)."
  type        = string
  default     = ""
}

variable "existing_network_name" {
  description = "Name of an existing VPC to reuse (when create_network = false)."
  type        = string
  default     = ""
}

variable "existing_subnet_name" {
  description = "Name of an existing regional subnet to reuse (when create_network = false)."
  type        = string
  default     = ""
}

variable "iap_source_range" {
  description = "Google IAP source range used for RDP/SSH tunneling."
  type        = string
  default     = "35.235.240.0/20"
}

variable "neo4j_ports" {
  description = <<-EOT
    TCP ports required to reach the Neo4j Aura PSC endpoint.
    443  = HTTPS (Aura APIs)
    7687 = Bolt (drivers)
    7474 = Browser (HTTP)
    8491 = Graph Analytics (remove if you do not use GDS)
  EOT
  type        = list(string)
  default     = ["443", "7687", "7474", "8491"]
}
