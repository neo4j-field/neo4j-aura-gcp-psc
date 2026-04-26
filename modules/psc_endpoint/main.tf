locals {
  create_ip_int       = var.create_psc_ip ? 1 : 0
  reuse_ip_int        = var.create_psc_ip ? 0 : 1
  create_endpoint_int = var.create_psc_endpoint ? 1 : 0
  reuse_endpoint_int  = var.create_psc_endpoint ? 0 : 1
}

# ---------------------------------------------------------------------------
# Static internal IP. Created here unless create_psc_ip = false, in which
# case an existing reservation is reused via data lookup.
# ---------------------------------------------------------------------------

resource "google_compute_address" "psc" {
  count        = local.create_ip_int
  name         = var.psc_ip_name
  project      = var.project_id
  region       = var.region
  subnetwork   = var.subnet_self_link
  address_type = "INTERNAL"
  purpose      = "GCE_ENDPOINT"
  description  = "Static internal IP reserved for the Neo4j Aura PSC consumer endpoint."
  labels       = var.common_labels
}

data "google_compute_address" "existing_psc" {
  count   = local.reuse_ip_int
  project = var.project_id
  region  = var.region
  name    = var.existing_psc_ip_name
}

locals {
  psc_ip_self_link = var.create_psc_ip ? google_compute_address.psc[0].self_link : data.google_compute_address.existing_psc[0].self_link
  psc_ip_value     = var.create_psc_ip ? google_compute_address.psc[0].address : data.google_compute_address.existing_psc[0].address
}

# ---------------------------------------------------------------------------
# PSC forwarding rule. Created here unless create_psc_endpoint = false, in
# which case an existing rule is reused via data lookup. Reuse is rare (each
# rule is bound to a single service attachment) but supported for symmetry
# with the IP toggle and for partial-apply recovery.
# ---------------------------------------------------------------------------

resource "google_compute_forwarding_rule" "psc" {
  count                 = local.create_endpoint_int
  name                  = var.psc_endpoint_name
  project               = var.project_id
  region                = var.region
  network               = var.network_self_link
  ip_address            = local.psc_ip_self_link
  target                = var.neo4j_service_attachment
  load_balancing_scheme = ""
  description           = "Private Service Connect consumer endpoint targeting the Neo4j Aura service attachment."
  labels                = var.common_labels
}

data "google_compute_forwarding_rule" "existing_psc" {
  count   = local.reuse_endpoint_int
  project = var.project_id
  region  = var.region
  name    = var.existing_psc_endpoint_name
}

locals {
  forwarding_rule_id        = var.create_psc_endpoint ? google_compute_forwarding_rule.psc[0].id : data.google_compute_forwarding_rule.existing_psc[0].id
  forwarding_rule_self_link = var.create_psc_endpoint ? google_compute_forwarding_rule.psc[0].self_link : data.google_compute_forwarding_rule.existing_psc[0].self_link
  psc_connection_id         = var.create_psc_endpoint ? google_compute_forwarding_rule.psc[0].psc_connection_id : data.google_compute_forwarding_rule.existing_psc[0].psc_connection_id
  psc_connection_status     = var.create_psc_endpoint ? google_compute_forwarding_rule.psc[0].psc_connection_status : data.google_compute_forwarding_rule.existing_psc[0].psc_connection_status
}
