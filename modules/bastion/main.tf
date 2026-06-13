locals {
  # Build the startup script dynamically from the port list so adding a port
  # only requires changing the variable, not editing this file.
  socat_units = [
    for port in var.neo4j_ports : <<-UNIT
      cat > /etc/systemd/system/neo4j-proxy-${port}.service <<EOF
      [Unit]
      Description=Neo4j PSC proxy on port ${port}
      After=network.target

      [Service]
      ExecStart=/usr/bin/socat TCP-LISTEN:${port},fork,reuseaddr TCP:${var.neo4j_psc_ip}:${port}
      Restart=always
      RestartSec=3

      [Install]
      WantedBy=multi-user.target
      EOF
      systemctl enable --now neo4j-proxy-${port}.service
    UNIT
  ]

  startup_script = <<-EOT
    #!/bin/bash
    set -euo pipefail
    apt-get update -qq
    apt-get install -y -qq socat
    ${join("\n", local.socat_units)}
  EOT
}

# ---------------------------------------------------------------------------
# Service account — minimal permissions; bastion needs no GCP API access.
# ---------------------------------------------------------------------------

resource "google_service_account" "bastion" {
  project      = var.project_id
  account_id   = "${var.bastion_name}-sa"
  display_name = "Neo4j bastion service account"
}

# ---------------------------------------------------------------------------
# Bastion VM — no public IP, socat proxies installed via startup script.
# ---------------------------------------------------------------------------

resource "google_compute_instance" "bastion" {
  project      = var.project_id
  name         = var.bastion_name
  machine_type = var.machine_type
  zone         = var.zone
  labels       = var.common_labels

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = var.subnet_self_link
    # No access_config block = no public IP.
  }

  service_account {
    email  = google_service_account.bastion.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    startup-script = local.startup_script
    # Block project-wide SSH keys; users connect only through IAP.
    block-project-ssh-keys = "true"
  }

  tags = ["neo4j-bastion"]

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
}

# ---------------------------------------------------------------------------
# Firewall — allow SSH only from the Google IAP forwarding range.
# ---------------------------------------------------------------------------

resource "google_compute_firewall" "iap_ssh" {
  project     = var.project_id
  name        = "${var.bastion_name}-allow-iap-ssh"
  network     = var.network_self_link
  description = "Allow SSH to the Neo4j bastion only from the Google IAP forwarding range."

  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["neo4j-bastion"]
  priority      = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# ---------------------------------------------------------------------------
# IAM — grant each developer the tunnelResourceAccessor role so they can
# open IAP tunnels to this VM without needing broader project permissions.
# Add individual developer emails to var.iap_members from the root module.
# ---------------------------------------------------------------------------
