output "instance_name" {
  description = "Name of the Windows test VM."
  value       = google_compute_instance.windows.name
}

output "instance_self_link" {
  description = "Self link of the Windows test VM."
  value       = google_compute_instance.windows.self_link
}

output "zone" {
  description = "Zone where the Windows test VM is deployed."
  value       = google_compute_instance.windows.zone
}

output "internal_ip" {
  description = "Internal IP of the Windows test VM."
  value       = google_compute_instance.windows.network_interface[0].network_ip
}

output "public_ip" {
  description = "Ephemeral external IP of the Windows test VM (null when enable_public_ip is false)."
  value       = try(google_compute_instance.windows.network_interface[0].access_config[0].nat_ip, null)
}
