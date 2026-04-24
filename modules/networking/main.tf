locals {
  create     = var.create_network
  create_int = var.create_network ? 1 : 0
  reuse_int  = var.create_network ? 0 : 1
}

# ---------------------------------------------------------------------------
# Create mode: new VPC, subnet, and firewall rules.
# ---------------------------------------------------------------------------

resource "google_compute_network" "consumer" {
  count                           = local.create_int
  name                            = var.vpc_name
  project                         = var.project_id
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
  delete_default_routes_on_create = false
  description                     = "Consumer VPC that hosts the Neo4j Aura PSC endpoint and client workloads."
}

resource "google_compute_subnetwork" "consumer" {
  count                    = local.create_int
  name                     = var.subnet_name
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.consumer[0].self_link
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true
  description              = "Subnet that hosts the PSC consumer endpoint IP and any client VMs."
}

resource "google_compute_firewall" "egress_neo4j" {
  count       = local.create_int
  name        = "${var.vpc_name}-egress-neo4j"
  project     = var.project_id
  network     = google_compute_network.consumer[0].self_link
  description = "Allow egress from the consumer subnet to the Neo4j Aura PSC endpoint on HTTPS, Bolt, and HTTP browser ports."

  direction          = "EGRESS"
  destination_ranges = [var.subnet_cidr]
  priority           = 1000

  allow {
    protocol = "tcp"
    ports    = var.neo4j_ports
  }
}

resource "google_compute_firewall" "ingress_iap_rdp" {
  count       = local.create_int
  name        = "${var.vpc_name}-ingress-iap-rdp"
  project     = var.project_id
  network     = google_compute_network.consumer[0].self_link
  description = "Allow RDP (3389) only from the Google IAP range. Targets VMs tagged rdp-iap."

  direction     = "INGRESS"
  source_ranges = [var.iap_source_range]
  target_tags   = ["rdp-iap"]
  priority      = 1000

  allow {
    protocol = "tcp"
    ports    = ["3389"]
  }
}

resource "google_compute_firewall" "ingress_internal" {
  count       = local.create_int
  name        = "${var.vpc_name}-ingress-internal"
  project     = var.project_id
  network     = google_compute_network.consumer[0].self_link
  description = "Allow all internal traffic within the consumer VPC CIDR. Targets VMs tagged internal."

  direction     = "INGRESS"
  source_ranges = [var.subnet_cidr]
  target_tags   = ["internal"]
  priority      = 1000

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }
}

# ---------------------------------------------------------------------------
# Reuse mode: look up an existing VPC and subnet, skip firewall creation.
# The pre-existing VPC is expected to already carry the firewall rules
# required for intra-VPC and IAP access.
# ---------------------------------------------------------------------------

data "google_compute_network" "existing" {
  count   = local.reuse_int
  project = var.project_id
  name    = var.existing_network_name
}

data "google_compute_subnetwork" "existing" {
  count   = local.reuse_int
  project = var.project_id
  region  = var.region
  name    = var.existing_subnet_name
}
