variable "project_id" {
  description = "GCP project ID where the test VM is created."
  type        = string
}

variable "zone" {
  description = "GCP zone for the Windows test VM."
  type        = string
}

variable "vm_name" {
  description = "Name of the Windows test VM."
  type        = string
}

variable "machine_type" {
  description = "Machine type for the Windows test VM."
  type        = string
}

variable "network_self_link" {
  description = "Self link of the consumer VPC."
  type        = string
}

variable "subnet_self_link" {
  description = "Self link of the consumer subnet."
  type        = string
}

variable "image_family" {
  description = "Windows image family to boot from."
  type        = string
  default     = "windows-2022"
}

variable "image_project" {
  description = "Project that hosts the Windows image family."
  type        = string
  default     = "windows-cloud"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GB."
  type        = number
  default     = 50
}

variable "boot_disk_type" {
  description = "Boot disk type."
  type        = string
  default     = "pd-ssd"
}

variable "common_labels" {
  description = "Labels applied to the VM."
  type        = map(string)
  default     = {}
}

variable "enable_public_ip" {
  description = "When true, attach an ephemeral external IP (one-to-one NAT) so the VM is reachable directly from the internet. Default false keeps the VM IAP-only."
  type        = bool
  default     = false
}
