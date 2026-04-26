locals {
  apex_host         = trimsuffix(var.neo4j_orch_dns_name, ".")
  apex_dns_name     = "${local.apex_host}."
  wildcard_dns_name = "*.${local.apex_host}."

  effective_policy_name = var.create_response_policy ? var.response_policy_name : var.existing_response_policy_name
}

resource "google_dns_response_policy" "neo4j" {
  count                = var.create_response_policy ? 1 : 0
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
  response_policy = local.effective_policy_name
  project         = var.project_id
  rule_name       = var.apex_rule_name
  dns_name        = local.apex_dns_name

  local_data {
    local_datas {
      name    = local.apex_dns_name
      type    = "A"
      ttl     = var.dns_ttl
      rrdatas = [var.psc_ip_address]
    }
  }

  depends_on = [google_dns_response_policy.neo4j]
}

# Wildcard rule. Matches <dbid>.production-orch-NNNN.neo4j.io lookups used by
# drivers connecting directly to a specific instance. Cloud DNS response
# policy rules do not perform subtree matching, so we create both rules.
resource "google_dns_response_policy_rule" "neo4j_wildcard" {
  response_policy = local.effective_policy_name
  project         = var.project_id
  rule_name       = var.wildcard_rule_name
  dns_name        = local.wildcard_dns_name

  local_data {
    local_datas {
      name    = local.wildcard_dns_name
      type    = "A"
      ttl     = var.dns_ttl
      rrdatas = [var.psc_ip_address]
    }
  }

  depends_on = [google_dns_response_policy.neo4j]
}
