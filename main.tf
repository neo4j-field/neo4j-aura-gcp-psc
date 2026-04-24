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

  project_id               = var.consumer_project_id
  region                   = var.consumer_region
  network_self_link        = module.networking.network_self_link
  subnet_self_link         = module.networking.subnetwork_self_link
  psc_ip_name              = var.psc_ip_name
  psc_endpoint_name        = var.psc_endpoint_name
  neo4j_service_attachment = var.neo4j_service_attachment
  common_labels            = local.common_labels
}

module "dns" {
  source = "./modules/dns"

  project_id           = var.consumer_project_id
  network_self_link    = module.networking.network_self_link
  neo4j_orch_subdomain = var.neo4j_orch_subdomain
  psc_ip_address       = module.psc_endpoint.psc_ip_address
}

module "test_vm" {
  count  = var.enable_test_vm ? 1 : 0
  source = "./modules/test_vm"

  project_id        = var.consumer_project_id
  zone              = var.consumer_zone
  vm_name           = var.windows_vm_name
  machine_type      = var.windows_vm_machine_type
  network_self_link = module.networking.network_self_link
  subnet_self_link  = module.networking.subnetwork_self_link
  enable_public_ip  = var.enable_vm_public_ip
  common_labels     = local.common_labels
}
