#!/usr/bin/env bash
# local_tunnel.sh
# Forward Bolt (7687) and the Neo4j Browser ports from your laptop, through
# the Linux test VM, to the Neo4j Aura PSC endpoint. Lets you run
# cypher-shell, the Neo4j drivers, or curl from your local machine against
# the Aura private URI without leaving GCP's private backbone end-to-end.
#
# HOW THE TRICK WORKS
#
#   Your laptop       SSH tunnel          Linux VM (in VPC)     Aura PSC
#   ------------      ------------------  -----------------     ----------
#   cypher-shell -a  neo4j+s://<host>:7687
#          |
#          v                                       DNS
#   /etc/hosts  -> 127.0.0.1                       override
#          |                                          |
#          +->  127.0.0.1:7687  ==ssh -L==>  <host>:7687  ==PSC==>  Aura
#
#   The remote end of the -L forward is resolved on the VM. The VM is in
#   the consumer VPC and has the Cloud DNS response policy attached, so
#   <host> resolves to the PSC internal IP. The driver on your laptop
#   sees SNI = <host>, so Aura's wildcard TLS cert validates correctly.
#
# BEFORE YOU RUN
#
#   1. Add this line to your hosts file (one-time, sudo/admin):
#        127.0.0.1  <dbid>.production-orch-NNNN.neo4j.io
#      macOS/Linux:  /etc/hosts
#      Windows:      C:\Windows\System32\drivers\etc\hosts
#
#   2. Remove the line when you are done testing, otherwise you will get
#      weird "connection refused" errors once the tunnel is closed.
#
# USAGE
#
#   ./local_tunnel.sh <neo4j-private-host>
#
# EXAMPLE
#
#   ./local_tunnel.sh abc1.production-orch-0792.neo4j.io
#
# In another terminal, connect with cypher-shell:
#
#   cypher-shell -a neo4j+s://abc1.production-orch-0792.neo4j.io:7687 \
#                -u neo4j -p '<password>'
#
# Or via Neo4j Desktop: point the Bolt URI at neo4j+s://<host>:7687.

set -euo pipefail

HOST="${1:-}"
if [[ -z "$HOST" ]]; then
  cat >&2 <<USAGE
Usage: $0 <neo4j-private-host>

Example:
  $0 abc1.production-orch-0792.neo4j.io
USAGE
  exit 2
fi

tf_output() { terraform output -raw "$1" 2>/dev/null || true; }

PROJECT="$(tf_output psc_forwarding_rule_id | awk -F/ '{print $2}')"
ZONE="$(tf_output linux_vm_zone)"
VM_NAME="$(tf_output linux_vm_name)"

if [[ -z "$PROJECT" || -z "$ZONE" || -z "$VM_NAME" ]]; then
  cat >&2 <<ERR
Could not read PROJECT / ZONE / VM_NAME from 'terraform output'.

Run this script from the repository root (where terraform.tfstate lives),
or pass the three values explicitly:

  PROJECT=<project> ZONE=<zone> VM_NAME=<name> $0 $HOST
ERR
  exit 1
fi

LOCAL_BOLT_PORT="${LOCAL_BOLT_PORT:-7687}"
LOCAL_BROWSER_PORT="${LOCAL_BROWSER_PORT:-7474}"

cat <<INFO
Opening SSH tunnel via $VM_NAME ($PROJECT / $ZONE).

Local forwards:
  localhost:${LOCAL_BOLT_PORT}    -> ${HOST}:7687   (Bolt)
  localhost:${LOCAL_BROWSER_PORT} -> ${HOST}:7474   (Neo4j Browser, HTTP)

Before connecting, confirm your hosts file has:
  127.0.0.1  ${HOST}

Connection URI for cypher-shell / drivers / Neo4j Desktop:
  neo4j+s://${HOST}:${LOCAL_BOLT_PORT}

Press Ctrl+C to close the tunnel.
INFO

exec gcloud compute ssh "$VM_NAME" \
  --tunnel-through-iap \
  --zone="$ZONE" \
  --project="$PROJECT" \
  -- -N \
  -L "${LOCAL_BOLT_PORT}:${HOST}:7687" \
  -L "${LOCAL_BROWSER_PORT}:${HOST}:7474"
