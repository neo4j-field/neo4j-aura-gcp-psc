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

## Option B — WireGuard VPN

If you want transparent access (Neo4j Desktop connects normally without managing
a tunnel window), deploy a WireGuard server in the consumer VPC. When your laptop
connects, it joins the VPC's network and uses Cloud DNS, so the response policy
applies automatically and every Neo4j tool works without `/etc/hosts` changes.

WireGuard requires a VM with a public IP and one open UDP port. If your organisation's
security policy prohibits both, use Option A instead.

### Architecture

```
Your laptop (WireGuard client)
  │
  │  WireGuard encrypted tunnel (UDP 51820)
  ▼
WireGuard VM (public IP, inside consumer VPC)
  │  DNS: 169.254.169.254 (Cloud DNS, response policy applies)
  ▼
PSC endpoint 10.x.x.x  →  Neo4j Aura VDC
```

### High-level steps

1. **Deploy WireGuard VM.** A small VM (e2-micro or e2-small) in the consumer VPC
   with a public IP and a firewall rule permitting UDP 51820 from your IP range.
   Install WireGuard: `apt-get install wireguard`.

2. **Generate key pairs** on the server and on your laptop:
   ```bash
   wg genkey | tee server_private.key | wg pubkey > server_public.key
   wg genkey | tee client_private.key | wg pubkey > client_public.key
   ```

3. **Configure the server** (`/etc/wireguard/wg0.conf`):
   ```ini
   [Interface]
   Address    = 10.200.0.1/24
   PrivateKey = <server_private_key>
   ListenPort = 51820
   # NAT so client traffic uses the VM's internal IP
   PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ens4 -j MASQUERADE
   PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ens4 -j MASQUERADE

   [Peer]
   PublicKey  = <client_public_key>
   AllowedIPs = 10.200.0.2/32
   ```
   Start: `systemctl enable --now wg-quick@wg0`

4. **Configure your laptop** (`/etc/wireguard/wg0.conf` or WireGuard app):
   ```ini
   [Interface]
   Address    = 10.200.0.2/24
   PrivateKey = <client_private_key>
   DNS        = 169.254.169.254

   [Peer]
   PublicKey  = <server_public_key>
   Endpoint   = <wireguard_vm_public_ip>:51820
   AllowedIPs = 10.0.0.0/8
   ```
   The `DNS = 169.254.169.254` line routes all DNS through Cloud DNS in the VPC,
   so the response policy rewrites `<dbid>.<orch>.neo4j.io` to the PSC IP.

5. **Connect**: `wg-quick up wg0` (or toggle in the WireGuard app). Open Neo4j
   Desktop and connect with the private URI — no `/etc/hosts`, no tunnel window.

---

## Comparison

| | Option A — IAP Tunnel | Option B — WireGuard |
|-|----------------------|---------------------|
| Public IP on VM | No | Yes (one VM) |
| Extra software on laptop | `gcloud` CLI only | WireGuard client |
| DNS managed automatically | No (`/etc/hosts`) | Yes |
| Survives laptop sleep | Tunnel drops, re-run command | Reconnects automatically |
| Suitable for locked-down corp laptops | Yes | Depends on policy |
| Cost | e2-micro (~$7/mo) | e2-micro (~$7/mo) |

For developer teams that connect frequently, WireGuard is significantly less friction
day-to-day. For occasional use or where no public IPs are permitted, the IAP tunnel
wins on security posture.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `gcloud` SSH fails with "permission denied" | IAM role missing | Add `roles/iap.tunnelResourceAccessor` to your Google account on the consumer project |
| Desktop shows "Couldn't connect" immediately | Tunnel not open or wrong port | Confirm the `gcloud` process is still running; check it is listening on 7687 with `lsof -i :7687` |
| TLS certificate error in browser | `/etc/hosts` entry missing or wrong hostname | Confirm the hostname in `/etc/hosts` exactly matches the private URI |
| `socat` not running on bastion | Startup script didn't finish | SSH into the bastion and run `systemctl status neo4j-proxy-*` |
| WireGuard DNS does not override Neo4j hostname | DNS setting not applied | Run `scutil --dns` (macOS) or `resolvectl status` (Linux) to confirm `169.254.169.254` is the active DNS |
