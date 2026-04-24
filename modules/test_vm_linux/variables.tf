variable "project_id" {
  description = "GCP project ID where the Linux test VM is created."
  type        = string
}

variable "zone" {
  description = "GCP zone for the Linux test VM."
  type        = string
}

variable "vm_name" {
  description = "Name of the Linux test VM."
  type        = string
}

variable "machine_type" {
  description = "Machine type for the Linux test VM. Default is e2-micro, which is free-tier eligible in some regions."
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
  description = "Linux image family to boot from."
  type        = string
  default     = "debian-12"
}

variable "image_project" {
  description = "Project that hosts the Linux image family."
  type        = string
  default     = "debian-cloud"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GB."
  type        = number
  default     = 10
}

variable "boot_disk_type" {
  description = "Boot disk type. pd-standard is cheapest and plenty for a network-test client."
  type        = string
  default     = "pd-standard"
}

variable "enable_public_ip" {
  description = "When true, attach an ephemeral external IP so the VM is reachable via public SSH. Default false keeps the VM IAP-only."
  type        = bool
  default     = false
}

variable "common_labels" {
  description = "Labels applied to the VM."
  type        = map(string)
  default     = {}
}
