locals {
  apex_dns_name     = "${var.neo4j_orch_subdomain}.neo4j.io."
  wildcard_dns_name = "*.${var.neo4j_orch_subdomain}.neo4j.io."
}

resource "google_dns_response_policy" "neo4j" {
  response_policy_name = var.response_policy_name
  project              = var.project_id
  description          = "Overrides Neo4j Aura orchestrator hostnames to the PSC internal IP for all lookups originating from the consumer VPC."

  networks {
    network_url = var.network_self_link
  }
}

# Apex rule. Matches lookups for the orchestrator hostname itself,
# which is what the Aura console's DNS instructions explicitly call out.
resource "google_dns_response_policy_rule" "neo4j_apex" {
  response_policy = google_dns_response_policy.neo4j.response_policy_name
  project         = var.project_id
  rule_name       = "neo4j-apex"
  dns_name        = local.apex_dns_name

  local_data {
    local_datas {
      name    = local.apex_dns_name
      type    = "A"
      ttl     = var.dns_ttl
      rrdatas = [var.psc_ip_address]
    }
  }
}

# Wildcard rule. Matches <dbid>.production-orch-NNNN.neo4j.io lookups used by
# drivers connecting directly to a specific instance. The Aura public docs
# explicitly call out the wildcard; we create both rules so the override works
# regardless of which form the driver uses.
resource "google_dns_response_policy_rule" "neo4j_wildcard" {
  response_policy = google_dns_response_policy.neo4j.response_policy_name
  project         = var.project_id
  rule_name       = "neo4j-wildcard"
  dns_name        = local.wildcard_dns_name

  local_data {
    local_datas {
      name    = local.wildcard_dns_name
      type    = "A"
      ttl     = var.dns_ttl
      rrdatas = [var.psc_ip_address]
    }
  }
}
