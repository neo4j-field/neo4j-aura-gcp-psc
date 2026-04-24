variable "consumer_project_id" {
  description = "GCP project ID for the consumer side of the PSC connection."
  type        = string
}

variable "consumer_region" {
  description = "Consumer region for the VPC, subnet, PSC endpoint, and VM."
  type        = string
  default     = "us-west1"
}

variable "consumer_zone" {
  description = "Consumer zone for the Windows test VM."
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

variable "neo4j_orch_subdomain" {
  description = <<-EOT
    Orchestrator subdomain from the Neo4j Aura Console used to build the DNS wildcard.
    Example: production-orch-0042. The wildcard record created will be *.<subdomain>.neo4j.io.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.neo4j_orch_subdomain))
    error_message = "neo4j_orch_subdomain must be lowercase alphanumeric with hyphens."
  }
}

variable "psc_ip_name" {
  description = "Name of the static internal IP reserved for the PSC endpoint."
  type        = string
  default     = "neo4j-psc-ip"
}

variable "psc_endpoint_name" {
  description = "Name of the PSC forwarding rule (the consumer endpoint)."
  type        = string
  default     = "neo4j-psc-endpoint"
}

# ---------------------------------------------------------------------------
# Linux test VM (default). A small Debian 12 client used to validate DNS and
# TCP reachability to the PSC endpoint. e2-micro is free-tier eligible in
# some regions and plenty for a network-test workload.
# ---------------------------------------------------------------------------

variable "enable_linux_test_vm" {
  description = "Whether to provision the Linux test VM. Default true. Turn this off alongside enable_windows_browser_vm = false for a production-only deploy with no VM surface."
  type        = bool
  default     = true
}

variable "linux_vm_name" {
  description = "Name of the Linux test VM."
  type        = string
  default     = "neo4j-test-vm-linux"
}

variable "linux_vm_machine_type" {
  description = "Machine type for the Linux test VM."
  type        = string
  default     = "e2-micro"
}

variable "linux_vm_public_ip" {
  description = "When true, attach an ephemeral external IP to the Linux test VM. SSH is key-based via OS Login so the risk is lower than Windows RDP, but for locked-down VPCs prefer IAP-only (set this false)."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Windows browser VM (optional). Only needed if you want to click through
# the Neo4j Browser UI over the private URI. Adds Microsoft licensing
# cost and boot time; skip unless you actually need the UI.
# ---------------------------------------------------------------------------

variable "enable_windows_browser_vm" {
  description = "Whether to provision a Windows Server 2022 VM for browsing Neo4j via the Browser UI. Default false. Only enable if you need the web UI; the Linux VM covers networking validation."
  type        = bool
  default     = false
}

variable "windows_vm_name" {
  description = "Name of the Windows browser VM."
  type        = string
  default     = "neo4j-test-vm-win"
}

variable "windows_vm_machine_type" {
  description = "Machine type for the Windows browser VM."
  type        = string
  default     = "n2-standard-2"
}

variable "windows_vm_public_ip" {
  description = "When true, attach an ephemeral external IP to the Windows browser VM for direct RDP. The default VPC's default-allow-rdp rule exposes 3389 from 0.0.0.0/0 unless tightened; keep this off and use IAP where possible."
  type        = bool
  default     = false
}

variable "extra_labels" {
  description = "Additional labels merged on top of the default neo4j-psc/managed-by labels."
  type        = map(string)
  default     = {}
}
