output "bastion_name" {
  description = "Name of the bastion VM. Use this in the gcloud compute ssh command."
  value       = google_compute_instance.bastion.name
}

output "bastion_zone" {
  description = "Zone of the bastion VM. Use this with --zone in the gcloud compute ssh command."
  value       = google_compute_instance.bastion.zone
}

output "bastion_internal_ip" {
  description = "Internal IP of the bastion VM. For diagnostics only — connect via IAP, not directly."
  value       = google_compute_instance.bastion.network_interface[0].network_ip
}

output "iap_tunnel_command" {
  description = "Ready-to-run gcloud command that opens the IAP SSH tunnel with Neo4j ports forwarded. Substitute YOUR_PROJECT_ID."
  value       = <<-EOT
    gcloud compute ssh ${google_compute_instance.bastion.name} \
      --tunnel-through-iap \
      --project YOUR_PROJECT_ID \
      --zone ${google_compute_instance.bastion.zone} \
      -- -L 7687:localhost:7687 \
         -L 7474:localhost:7474 \
         -L 7473:localhost:7473 \
         -N
  EOT
}
