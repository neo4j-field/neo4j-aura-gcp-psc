output "instance_name" {
  description = "Name of the Linux test VM."
  value       = google_compute_instance.linux.name
}

output "instance_self_link" {
  description = "Self link of the Linux test VM."
  value       = google_compute_instance.linux.self_link
}

output "zone" {
  description = "Zone where the Linux test VM is deployed."
  value       = google_compute_instance.linux.zone
}

output "internal_ip" {
  description = "Internal IP of the Linux test VM."
  value       = google_compute_instance.linux.network_interface[0].network_ip
}

output "public_ip" {
  description = "External IP of the Linux test VM (null when enable_public_ip is false)."
  value       = try(google_compute_instance.linux.network_interface[0].access_config[0].nat_ip, null)
}
