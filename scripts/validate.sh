#!/usr/bin/env bash
# validate.sh
# Run on a Linux VM inside the consumer VPC to verify DNS override and TCP
# reachability to the Neo4j Aura PSC endpoint. Uses only bash built-ins and
# getent/dig, so no extra packages need to be installed on a minimal Debian
# or Ubuntu image.
#
# Usage:
#   ./validate.sh <neo4j-private-host> <expected-psc-ip>
#
# Example:
#   ./validate.sh abc1.production-orch-0792.neo4j.io 10.128.0.50

set -u

HOST="${1:-}"
EXPECTED_IP="${2:-}"

if [[ -z "$HOST" || -z "$EXPECTED_IP" ]]; then
  cat >&2 <<USAGE
Usage: $0 <neo4j-private-host> <expected-psc-ip>

Example:
  $0 abc1.production-orch-0792.neo4j.io 10.128.0.50
USAGE
  exit 2
fi

printf 'Neo4j PSC connectivity check\n'
printf '============================\n'
printf 'Host       : %s\n' "$HOST"
printf 'Expected IP: %s\n' "$EXPECTED_IP"

# DNS: prefer dig when present, fall back to getent (glibc resolver). Both
# honor the VPC-scoped Cloud DNS response policy.
if command -v dig >/dev/null 2>&1; then
  RESOLVED=$(dig +short +time=3 +tries=1 "$HOST" A | head -n 1)
else
  RESOLVED=$(getent ahostsv4 "$HOST" 2>/dev/null | awk 'NR==1{print $1}')
fi
printf 'DNS answer : %s\n' "${RESOLVED:-<no answer>}"

dns_ok=0
if [[ "$RESOLVED" == "$EXPECTED_IP" ]]; then
  printf 'DNS        : PASS\n'
  dns_ok=1
else
  printf 'DNS        : FAIL\n'
fi

# TCP: use bash's built-in /dev/tcp, wrapped in timeout. No nc required.
check_port() {
  local port="$1"
  if timeout 5 bash -c "exec 3<>/dev/tcp/${HOST}/${port}" 2>/dev/null; then
    exec 3<&- 3>&-
    return 0
  fi
  return 1
}

tcp_fail=0
for PORT in 443 7687 7474 8491; do
  if check_port "$PORT"; then
    printf 'TCP %-5s: PASS\n' "$PORT"
  else
    printf 'TCP %-5s: FAIL\n' "$PORT"
    # 8491 (Graph Analytics) is optional; a miss there is not a failure.
    if [[ "$PORT" != "8491" ]]; then
      tcp_fail=1
    fi
  fi
done

if [[ "$dns_ok" -ne 1 || "$tcp_fail" -ne 0 ]]; then
  printf '\nRESULT: FAIL\n'
  exit 1
fi

printf '\nRESULT: PASS\n'
exit 0
