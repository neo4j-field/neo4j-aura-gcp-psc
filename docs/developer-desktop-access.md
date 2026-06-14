# Developer Desktop Access After Disabling Public Traffic

Once you check **Disable public traffic** in the Aura wizard, every connection that
does not arrive through the PSC tunnel is refused — including connections from developer
laptops running Neo4j Desktop or a browser pointed at Neo4j Browser.

This guide shows two ways to restore that access without re-enabling public traffic.

---

## How it works

The Cloud DNS response policy you applied in the main setup rewrites the Neo4j
hostname to the PSC endpoint IP, but only for queries originating inside the consumer
VPC. Your laptop uses public DNS and still resolves to Aura's public IP, which is
now blocked.

The fix is to route your laptop's Neo4j traffic through a machine that *is* inside
the consumer VPC, so it benefits from the response policy and reaches Aura over the
private tunnel.

---

## Option A — IAP SSH Tunnel (recommended)

This option uses Google Cloud IAP to create an encrypted tunnel from your laptop to a
bastion VM inside the consumer VPC, with no public IP on either end. You need `gcloud`
CLI installed and authenticated. No additional software is required.

### What you will build

```
Your laptop
  │
  │  gcloud IAP tunnel (TCP/443 to Google edge)
  ▼
Bastion VM (no public IP, inside consumer VPC)
  │
  │  loopback SSH port-forward to PSC endpoint IP
  ▼
PSC endpoint 10.x.x.x
  │
  │  Private Service Connect tunnel
  ▼
Neo4j Aura VDC
```

### Step 1: Deploy the bastion

This repo includes a `modules/bastion` module. Add it to your root `main.tf`:

```hcl
module "bastion" {
  source = "./modules/bastion"

  project_id        = var.consumer_project_id
  zone              = var.consumer_zone
  subnet_self_link  = module.networking.subnetwork_self_link
  network_self_link = module.networking.network_self_link
  neo4j_psc_ip      = module.psc_endpoint.psc_ip_address
}
```

Then apply:

```bash
terraform init   # picks up the new module
terraform apply
```

The bastion is an `e2-micro` VM with no public IP. The startup script installs `socat`
and starts four proxy listeners (ports 7687, 7474, 7473, 8491) that forward traffic to
the PSC endpoint IP.

The module outputs the instance name and zone you will need below:

```
bastion_name = "neo4j-bastion"
bastion_zone = "us-central1-a"
```

### Step 2: Add the Neo4j hostname to `/etc/hosts`

Neo4j Desktop and browsers verify the TLS certificate against the **hostname** in your
connection URI. If the URI says `<dbid>.<orch>.neo4j.io` the certificate check passes.
If the URI says `localhost` it fails, because the certificate is issued for `*.neo4j.io`.

The trick: tell your OS that the Neo4j hostname lives at `127.0.0.1`. Your laptop
opens the TCP connection to `127.0.0.1` (the tunnel), but the TLS handshake still
sees the correct hostname.

Open `/etc/hosts` (Linux/macOS) or `C:\Windows\System32\drivers\etc\hosts` (Windows)
in a text editor with admin/sudo and add **one line**:

```
127.0.0.1  <dbid>.<orch>.neo4j.io
```

Replace `<dbid>.<orch>.neo4j.io` with the exact hostname from your Aura Console
credentials file — the one labelled **NEO4J_URI** minus the `bolt+s://` prefix
and the `:7687` suffix.

Example:

```
127.0.0.1  0a1b2c3d.production-orch-0099.neo4j.io
```

> **Remove this line when you switch back to public access or when you no longer
> need the tunnel.** While it is present, *all* DNS lookups for that hostname on
> your laptop resolve to `127.0.0.1`.

### Step 3: Open the tunnel

Run this command in a terminal. Replace the placeholders with your project ID, zone,
and bastion name from `terraform output`:

```bash
gcloud compute ssh neo4j-bastion \
  --tunnel-through-iap \
  --project YOUR_PROJECT_ID \
  --zone YOUR_ZONE \
  -- -L 7687:localhost:7687 \
     -L 7474:localhost:7474 \
     -L 7473:localhost:7473 \
     -N
```

The `-N` flag keeps the SSH session open without launching a remote shell. Leave this
terminal running for as long as you need the connection.

On macOS/Linux you can background it with `-f` instead of leaving the terminal open:

```bash
gcloud compute ssh neo4j-bastion \
  --tunnel-through-iap \
  --project YOUR_PROJECT_ID \
  --zone YOUR_ZONE \
  -- -L 7687:localhost:7687 \
     -L 7474:localhost:7474 \
     -L 7473:localhost:7473 \
     -N -f
```

### Step 4: Connect Neo4j Desktop

Open Neo4j Desktop and create a new remote connection:

| Field       | Value                                    |
| ----------- | ---------------------------------------- |
| Connect URL | `bolt+s://<dbid>.<orch>.neo4j.io:7687`   |
| Username    | `neo4j` (or your Aura username)          |
| Password    | your Aura password                       |

Click **Connect**. The connection flows:

1. Desktop looks up `<dbid>.<orch>.neo4j.io` → your `/etc/hosts` returns `127.0.0.1`
2. TCP connects to `127.0.0.1:7687` → SSH tunnel → bastion `localhost:7687`
3. Bastion `socat` proxy → PSC endpoint IP port 7687 → Aura
4. TLS: Aura presents `*.<orch>.neo4j.io` cert, Desktop verifies against
   `<dbid>.<orch>.neo4j.io` — matches ✓

### Step 5: Access Neo4j Browser in Chrome

Navigate to:

```
https://<dbid>.<orch>.neo4j.io:7474
```

Same routing as above, through the `:7474` leg of the tunnel. Chrome will show
a valid certificate because the hostname matches.

### Closing the tunnel

Kill the `gcloud` SSH process when you are done. If you used `-f` (backgrounded):

```bash
# Find the process
ps aux | grep 'gcloud compute ssh'

# Kill it
kill <PID>
```

Remove the `/etc/hosts` line once the tunnel is closed.

---

## Option B — OpenVPN on GCE (when a full VPN is a policy requirement)

**For most deployments, Option A (IAP tunnel) is the right answer.** GCP IAP
authenticates via Google / Workspace identity, produces audit trails in Cloud Audit
Logs, and requires no open inbound ports on any VM.

If your organisation's security policy explicitly requires a client VPN rather than
an SSH tunnel — common in regulated industries such as financial services and
insurance — use **OpenVPN** deployed on a GCE VM. OpenVPN is battle-tested (20+
years), has FIPS 140-2 compliant implementations, and is widely accepted in
regulated-industry approved-software lists.

> **Note on WireGuard:** WireGuard was listed in an earlier version of this guide.
> It has been removed. WireGuard lacks FIPS 140-2 certification, is relatively new
> (mainlined in Linux 5.6, 2020), and is not yet on the approved-software lists of
> most financial or insurance institutions. Use OpenVPN or the IAP tunnel instead.

### Architecture

```
Your laptop (OpenVPN client)
  │
  │  OpenVPN tunnel (TCP/443 or UDP/1194)
  ▼
OpenVPN VM (public IP, consumer VPC)
  │  DNS: 169.254.169.254 (Cloud DNS, response policy applies)
  ▼
PSC endpoint 10.x.x.x  →  Neo4j Aura VDC
```

### High-level steps

For a production-grade setup, use **OpenVPN Access Server** (AS) from the GCP
Marketplace — it provides a management UI, certificate management, and MFA
integration:

1. **Deploy OpenVPN AS** from GCP Marketplace into the consumer VPC. Reserve a
   static external IP and assign it to the instance.
2. **Create a firewall rule** on the consumer VPC allowing UDP 1194 (or TCP 443)
   from developer IP ranges to the OpenVPN VM, tagged `openvpn-server`.
3. **Configure DNS** in the OpenVPN AS admin UI: set DNS server to
   `169.254.169.254` so connected clients resolve via Cloud DNS and the response
   policy override takes effect.
4. **Issue client profiles** through the OpenVPN AS user portal. Developers install
   the OpenVPN Connect client and import the profile.
5. **Connect**: once the VPN is up, `<dbid>.<orch>.neo4j.io` resolves to the PSC
   IP automatically. Neo4j Desktop and Chrome connect without any `/etc/hosts`
   changes.

---

## Comparison

| | Option A — IAP Tunnel | Option B — OpenVPN |
|-|----------------------|--------------------|
| Public IP on VM | No | Yes (one VM) |
| Extra software on laptop | `gcloud` CLI only | OpenVPN Connect client |
| DNS managed automatically | No (`/etc/hosts`) | Yes |
| Survives laptop sleep | Tunnel drops, re-run command | Reconnects automatically |
| MFA support | Via Google identity | Via OpenVPN AS MFA plugins |
| FIPS 140-2 | Not applicable | ✅ Available with OpenVPN AS |
| Regulatory acceptance (finance/insurance) | ✅ (Google IAP, audited) | ✅ (OpenVPN, audited) |
| Suitable for locked-down corp laptops | ✅ Yes (`gcloud` is standard) | Depends on policy |
| Cost | e2-micro (~$7/mo) | e2-micro + OpenVPN AS licence |

**Option A is recommended for most teams.** Option B is the right choice when
security policy explicitly mandates a VPN client and the IAP tunnel pattern has
not been pre-approved.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `gcloud` SSH fails with "permission denied" | IAM role missing | Add `roles/iap.tunnelResourceAccessor` to your Google account on the consumer project |
| Desktop shows "Couldn't connect" immediately | Tunnel not open or wrong port | Confirm the `gcloud` process is still running; check it is listening on 7687 with `lsof -i :7687` |
| TLS certificate error in browser | `/etc/hosts` entry missing or wrong hostname | Confirm the hostname in `/etc/hosts` exactly matches the private URI |
| `socat` not running on bastion | Startup script didn't finish | SSH into the bastion and run `systemctl status neo4j-proxy-*` |
| OpenVPN connected but Neo4j hostname resolves to public IP | DNS server not set to 169.254.169.254 in OpenVPN AS | In OpenVPN AS admin UI → VPN Settings → DNS: set to 169.254.169.254 and push to clients |
