resource "google_compute_address" "psc" {
  name         = var.psc_ip_name
  project      = var.project_id
  region       = var.region
  subnetwork   = var.subnet_self_link
  address_type = "INTERNAL"
  purpose      = "GCE_ENDPOINT"
  description  = "Static internal IP reserved for the Neo4j Aura PSC consumer endpoint."
  labels       = var.common_labels
}

resource "google_compute_forwarding_rule" "psc" {
  name                  = var.psc_endpoint_name
  project               = var.project_id
  region                = var.region
  network               = var.network_self_link
  ip_address            = google_compute_address.psc.self_link
  target                = var.neo4j_service_attachment
  load_balancing_scheme = ""
  description           = "Private Service Connect consumer endpoint targeting the Neo4j Aura service attachment."
  labels                = var.common_labels
}
