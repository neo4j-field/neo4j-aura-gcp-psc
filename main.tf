terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.consumer_project_id
  region  = var.consumer_region
  zone    = var.consumer_zone
}

locals {
  common_labels = merge(
    {
      neo4j-psc  = "true"
      managed-by = "terraform"
    },
    var.extra_labels,
  )
}

module "networking" {
  source = "./modules/networking"

  project_id            = var.consumer_project_id
  region                = var.consumer_region
  create_network        = var.create_network
  vpc_name              = var.vpc_name
  subnet_name           = var.subnet_name
  subnet_cidr           = var.subnet_cidr
  existing_network_name = var.existing_network_name
  existing_subnet_name  = var.existing_subnet_name
}

module "psc_endpoint" {
  source = "./modules/psc_endpoint"

  project_id                 = var.consumer_project_id
  region                     = var.consumer_region
  network_self_link          = module.networking.network_self_link
  subnet_self_link           = module.networking.subnetwork_self_link
  create_psc_ip              = var.create_psc_ip
  existing_psc_ip_name       = var.existing_psc_ip_name
  psc_ip_name                = var.psc_ip_name
  create_psc_endpoint        = var.create_psc_endpoint
  existing_psc_endpoint_name = var.existing_psc_endpoint_name
  psc_endpoint_name          = var.psc_endpoint_name
  neo4j_service_attachment   = var.neo4j_service_attachment
  common_labels              = local.common_labels
}

module "dns" {
  source = "./modules/dns"

  project_id                    = var.consumer_project_id
  network_self_link             = module.networking.network_self_link
  neo4j_orch_dns_name           = var.neo4j_orch_dns_name
  psc_ip_address                = module.psc_endpoint.psc_ip_address
  create_response_policy        = var.create_dns_response_policy
  existing_response_policy_name = var.existing_dns_response_policy_name
  response_policy_name          = var.dns_response_policy_name
  apex_rule_name                = var.dns_apex_rule_name
  wildcard_rule_name            = var.dns_wildcard_rule_name
}

# ---------------------------------------------------------------------------
# State migrations.
#
# Earlier revisions kept several resources without a count meta-argument.
# This release wraps them in count-driven create/reuse toggles, so the
# state addresses gain a `[0]` index. Terraform reconciles state via the
# moved blocks below instead of destroy + recreate.
# ---------------------------------------------------------------------------

moved {
  from = module.psc_endpoint.google_compute_address.psc
  to   = module.psc_endpoint.google_compute_address.psc[0]
}

moved {
  from = module.psc_endpoint.google_compute_forwarding_rule.psc
  to   = module.psc_endpoint.google_compute_forwarding_rule.psc[0]
}

moved {
  from = module.dns.google_dns_response_policy.neo4j
  to   = module.dns.google_dns_response_policy.neo4j[0]
}
