locals {
  network_self_link    = var.create_network ? google_compute_network.consumer[0].self_link : data.google_compute_network.existing[0].self_link
  subnetwork_self_link = var.create_network ? google_compute_subnetwork.consumer[0].self_link : data.google_compute_subnetwork.existing[0].self_link
  subnet_cidr_out      = var.create_network ? google_compute_subnetwork.consumer[0].ip_cidr_range : data.google_compute_subnetwork.existing[0].ip_cidr_range
  network_id_out       = var.create_network ? google_compute_network.consumer[0].id : data.google_compute_network.existing[0].id
  subnetwork_id_out    = var.create_network ? google_compute_subnetwork.consumer[0].id : data.google_compute_subnetwork.existing[0].id
}

output "network_self_link" {
  description = "Self link of the consumer VPC."
  value       = local.network_self_link
}

output "network_id" {
  description = "ID of the consumer VPC."
  value       = local.network_id_out
}

output "subnetwork_self_link" {
  description = "Self link of the consumer subnet."
  value       = local.subnetwork_self_link
}

output "subnetwork_id" {
  description = "ID of the consumer subnet."
  value       = local.subnetwork_id_out
}

output "subnet_cidr" {
  description = "Primary CIDR of the consumer subnet."
  value       = local.subnet_cidr_out
}
