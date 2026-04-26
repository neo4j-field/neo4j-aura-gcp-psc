#!/usr/bin/env bash
#
# teardown.sh
#
# Deletes the GCP resources that this Terraform module creates.
# Use when Terraform state is lost or you want to force a clean slate
# (for example, between screencast takes or after a partial apply).
#
# Defaults match the module's variable defaults. Override any value
# via env var. Resource names that you customize in terraform.tfvars
# must be passed in here too.
#
# Usage:
#   PROJECT_ID=neo4jeventdemos ./scripts/teardown.sh
#   PROJECT_ID=neo4jeventdemos REGION=us-central1 ./scripts/teardown.sh --yes
#   PROJECT_ID=neo4jeventdemos ./scripts/teardown.sh --include-network
#
# Flags:
#   --yes, -y           Skip the confirmation prompt.
#   --include-network   Also delete the VPC, subnet, and firewall rules
#                       (only if you set create_network = true in tfvars).
#
# The script is idempotent. Resources that do not exist are skipped.
# Deletion order respects GCP dependencies (forwarding rule before IP,
# DNS rules before policy, firewalls and subnet before VPC).

set -euo pipefail

PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"

PSC_IP_NAME="${PSC_IP_NAME:-neo4j-psc-ip}"
PSC_ENDPOINT_NAME="${PSC_ENDPOINT_NAME:-neo4j-psc-endpoint}"

DNS_RESPONSE_POLICY_NAME="${DNS_RESPONSE_POLICY_NAME:-neo4j-psc-rpz}"
DNS_APEX_RULE_NAME="${DNS_APEX_RULE_NAME:-neo4j-apex}"
DNS_WILDCARD_RULE_NAME="${DNS_WILDCARD_RULE_NAME:-neo4j-wildcard}"

VPC_NAME="${VPC_NAME:-consumer-vpc}"
SUBNET_NAME="${SUBNET_NAME:-consumer-subnet}"

ASSUME_YES=false
INCLUDE_NETWORK=false

for arg in "$@"; do
  case "$arg" in
    --yes|-y)          ASSUME_YES=true ;;
    --include-network) INCLUDE_NETWORK=true ;;
    -h|--help)
      sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//;$d'
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Run with --help for usage." >&2
      exit 2
      ;;
  esac
done

if [[ -z "$PROJECT_ID" ]]; then
  echo "PROJECT_ID is required. Example: PROJECT_ID=my-project $0" >&2
  exit 2
fi

if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud not found on PATH. Install the Google Cloud SDK first." >&2
  exit 2
fi

log()  { printf '[teardown] %s\n' "$*"; }
warn() { printf '[teardown] WARN: %s\n' "$*" >&2; }

cat <<EOF
About to delete the following in project '$PROJECT_ID' (region $REGION):
  - PSC forwarding rule:   $PSC_ENDPOINT_NAME
  - PSC internal IP:       $PSC_IP_NAME
  - DNS response policy:   $DNS_RESPONSE_POLICY_NAME
      apex rule:           $DNS_APEX_RULE_NAME
      wildcard rule:       $DNS_WILDCARD_RULE_NAME
EOF

if [[ "$INCLUDE_NETWORK" == "true" ]]; then
  cat <<EOF
  - Firewall rules:        ${VPC_NAME}-egress-neo4j
                           ${VPC_NAME}-ingress-iap-rdp
                           ${VPC_NAME}-ingress-internal
  - Subnet:                $SUBNET_NAME
  - VPC:                   $VPC_NAME
EOF
else
  echo "  (Network resources skipped. Pass --include-network to also delete them.)"
fi

if [[ "$ASSUME_YES" != "true" ]]; then
  read -r -p "Proceed? [y/N] " reply
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    log "aborted by user"
    exit 0
  fi
fi

delete_forwarding_rule() {
  local name="$1"
  if gcloud compute forwarding-rules describe "$name" \
       --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
    log "deleting forwarding rule: $name"
    gcloud compute forwarding-rules delete "$name" \
      --region="$REGION" --project="$PROJECT_ID" --quiet
  else
    log "forwarding rule not found, skipping: $name"
  fi
}

delete_address() {
  local name="$1"
  if gcloud compute addresses describe "$name" \
       --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
    log "deleting address: $name"
    gcloud compute addresses delete "$name" \
      --region="$REGION" --project="$PROJECT_ID" --quiet
  else
    log "address not found, skipping: $name"
  fi
}

delete_dns_rule() {
  local policy="$1" rule="$2"
  if gcloud dns response-policies rules describe "$rule" \
       --response-policy="$policy" --project="$PROJECT_ID" >/dev/null 2>&1; then
    log "deleting DNS response-policy rule: $policy/$rule"
    gcloud dns response-policies rules delete "$rule" \
      --response-policy="$policy" --project="$PROJECT_ID" --quiet
  else
    log "DNS rule not found, skipping: $policy/$rule"
  fi
}

delete_dns_response_policy() {
  local name="$1"
  if gcloud dns response-policies describe "$name" \
       --project="$PROJECT_ID" >/dev/null 2>&1; then
    # GCP refuses to delete a response policy that still has network
    # bindings. Clear them first; ignore failure in case it was already empty.
    log "detaching networks from DNS response policy: $name"
    gcloud dns response-policies update "$name" \
      --networks="" --project="$PROJECT_ID" --quiet \
      || warn "could not clear networks on $name (may already be empty)"
    log "deleting DNS response policy: $name"
    gcloud dns response-policies delete "$name" \
      --project="$PROJECT_ID" --quiet
  else
    log "DNS response policy not found, skipping: $name"
  fi
}

delete_firewall() {
  local name="$1"
  if gcloud compute firewall-rules describe "$name" \
       --project="$PROJECT_ID" >/dev/null 2>&1; then
    log "deleting firewall rule: $name"
    gcloud compute firewall-rules delete "$name" \
      --project="$PROJECT_ID" --quiet
  else
    log "firewall rule not found, skipping: $name"
  fi
}

delete_subnet() {
  local name="$1"
  if gcloud compute networks subnets describe "$name" \
       --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
    log "deleting subnet: $name"
    gcloud compute networks subnets delete "$name" \
      --region="$REGION" --project="$PROJECT_ID" --quiet
  else
    log "subnet not found, skipping: $name"
  fi
}

delete_network() {
  local name="$1"
  if gcloud compute networks describe "$name" \
       --project="$PROJECT_ID" >/dev/null 2>&1; then
    log "deleting VPC: $name"
    gcloud compute networks delete "$name" \
      --project="$PROJECT_ID" --quiet
  else
    log "VPC not found, skipping: $name"
  fi
}

# Dependency order:
# 1. Forwarding rule releases the static IP.
# 2. Static IP can then be deleted.
# 3. DNS rules sit under the response policy, delete them first.
# 4. DNS response policy.
# 5. Firewall rules attached to the VPC.
# 6. Subnet inside the VPC.
# 7. VPC last.

delete_forwarding_rule       "$PSC_ENDPOINT_NAME"
delete_address               "$PSC_IP_NAME"
delete_dns_rule              "$DNS_RESPONSE_POLICY_NAME" "$DNS_APEX_RULE_NAME"
delete_dns_rule              "$DNS_RESPONSE_POLICY_NAME" "$DNS_WILDCARD_RULE_NAME"
delete_dns_response_policy   "$DNS_RESPONSE_POLICY_NAME"

if [[ "$INCLUDE_NETWORK" == "true" ]]; then
  delete_firewall "${VPC_NAME}-egress-neo4j"
  delete_firewall "${VPC_NAME}-ingress-iap-rdp"
  delete_firewall "${VPC_NAME}-ingress-internal"
  delete_subnet   "$SUBNET_NAME"
  delete_network  "$VPC_NAME"
fi

log "teardown complete"
