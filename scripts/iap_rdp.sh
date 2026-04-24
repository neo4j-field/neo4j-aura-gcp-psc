#!/usr/bin/env bash
# Opens a GCP IAP tunnel to the Windows test VM for RDP access.
# Usage:
#   ./iap_rdp.sh                           # reads values from terraform output in cwd
#   ./iap_rdp.sh PROJECT ZONE VM_NAME      # overrides from CLI args
set -euo pipefail

LOCAL_PORT="${LOCAL_PORT:-13389}"

tf_output() {
  local key="$1"
  terraform output -raw "$key" 2>/dev/null || true
}

PROJECT="${1:-}"
ZONE="${2:-}"
VM_NAME="${3:-}"

if [[ -z "$PROJECT" ]]; then
  PROJECT="$(tf_output psc_forwarding_rule_id | awk -F/ '{print $2}')"
fi
if [[ -z "$ZONE" ]]; then
  ZONE="$(tf_output windows_vm_zone | awk -F/ '{print $NF}')"
fi
if [[ -z "$VM_NAME" ]]; then
  VM_NAME="$(tf_output windows_vm_name)"
fi

if [[ -z "$PROJECT" || -z "$ZONE" || -z "$VM_NAME" ]]; then
  cat >&2 <<USAGE
Could not determine PROJECT, ZONE, or VM_NAME from terraform state.

Usage:
  $0 <PROJECT> <ZONE> <VM_NAME>

Or run this from a directory that contains the terraform state for
neo4j-psc-gcp so values can be read from 'terraform output'.
USAGE
  exit 1
fi

cat <<INFO
Starting IAP tunnel:
  project : $PROJECT
  zone    : $ZONE
  vm      : $VM_NAME
  local   : localhost:${LOCAL_PORT}

Connect your RDP client to:
  localhost:${LOCAL_PORT}

If you do not yet have a Windows password, generate one with:
  gcloud compute reset-windows-password ${VM_NAME} --zone=${ZONE} --project=${PROJECT}

Press Ctrl+C to close the tunnel.
INFO

exec gcloud compute start-iap-tunnel "$VM_NAME" 3389 \
  --local-host-port="localhost:${LOCAL_PORT}" \
  --zone="$ZONE" \
  --project="$PROJECT"
