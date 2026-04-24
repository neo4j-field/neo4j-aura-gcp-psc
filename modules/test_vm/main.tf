data "google_compute_image" "windows" {
  family  = var.image_family
  project = var.image_project
}

resource "google_compute_instance" "windows" {
  name         = var.vm_name
  project      = var.project_id
  zone         = var.zone
  machine_type = var.machine_type
  description  = "Windows Server test client used to validate private connectivity to Neo4j Aura over PSC."

  tags = ["rdp-iap", "internal"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.windows.self_link
      size  = var.boot_disk_size_gb
      type  = var.boot_disk_type
    }
  }

  network_interface {
    network    = var.network_self_link
    subnetwork = var.subnet_self_link

    dynamic "access_config" {
      for_each = var.enable_public_ip ? [1] : []
      content {
        network_tier = "PREMIUM"
      }
    }
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-osconfig = "TRUE"
  }

  labels = var.common_labels

  lifecycle {
    ignore_changes = [
      metadata["windows-keys"],
    ]
  }
}
