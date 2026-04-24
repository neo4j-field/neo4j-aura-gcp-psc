data "google_compute_image" "linux" {
  family  = var.image_family
  project = var.image_project
}

resource "google_compute_instance" "linux" {
  name         = var.vm_name
  project      = var.project_id
  zone         = var.zone
  machine_type = var.machine_type
  description  = "Small Linux client used to validate DNS and TCP reachability to the Neo4j Aura PSC endpoint."

  tags = ["ssh-iap", "internal"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.linux.self_link
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
    enable-oslogin = "TRUE"
  }

  labels = var.common_labels
}
