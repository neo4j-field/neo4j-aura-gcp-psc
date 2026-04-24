#!/usr/bin/env bash
# iap_ssh.sh
# Opens an IAP-tunneled SSH session to the Linux test VM.
#
# Usage:
#   ./iap_ssh.sh                                # reads values from terraform output in cwd
#   ./iap_ssh.sh <PROJECT> <ZONE> <VM_NAME>     # explicit overrides
set -euo pipefail

tf_output() {
  terraform output -raw "$1" 2>/dev/null || true
}

PROJECT="${1:-}"
ZONE="${2:-}"
VM_NAME="${3:-}"

if [[ -z "$PROJECT" ]]; then
  PROJECT="$(tf_output psc_forwarding_rule_id | awk -F/ '{print $2}')"
fi
if [[ -z "$ZONE" ]]; then
  ZONE="$(tf_output linux_vm_zone | awk -F/ '{print $NF}')"
fi
if [[ -z "$VM_NAME" ]]; then
  VM_NAME="$(tf_output linux_vm_name)"
fi

if [[ -z "$PROJECT" || -z "$ZONE" || -z "$VM_NAME" ]]; then
  cat >&2 <<USAGE
Could not determine PROJECT, ZONE, or VM_NAME from terraform output.

Usage:
  $0 <PROJECT> <ZONE> <VM_NAME>

Or run from a directory that contains the terraform state for
neo4j-psc-gcp so values can be read from 'terraform output'.
USAGE
  exit 1
fi

echo "IAP SSH: $VM_NAME  (project=$PROJECT zone=$ZONE)"
exec gcloud compute ssh "$VM_NAME" \
  --tunnel-through-iap \
  --zone="$ZONE" \
  --project="$PROJECT"
