---
title: "Private Networking for Neo4j Aura on GCP, Step by Step with Private Service Connect"
slug: neo4j-aura-gcp-private-service-connect
excerpt: "A practical, end-to-end walkthrough of connecting Neo4j Aura VDC to a GCP consumer VPC over Private Service Connect, with Terraform and live validation."
author: Guhan Sivaji
categories: [Aura, GCP, Networking]
tags: [neo4j-aura, gcp, private-service-connect, psc, terraform, cloud-dns]
featured_image: screenshots/12-neo4j-browser-show-databases.png
---

# Private Networking for Neo4j Aura on GCP, Step by Step with Private Service Connect

A few days ago I was walking through deployment options with a team that
runs Neo4j Aura on GCP, and they asked the question I keep hearing from
security-conscious customers: can we get our Aura traffic off the public
internet entirely, and keep it on Google's private backbone?

The answer is yes, and the mechanism is Private Service Connect. If you
are coming from AWS, PSC is GCP's equivalent of PrivateLink. The shape
of the solution is familiar: the producer (Aura) exposes a service
attachment, the consumer (your VPC) creates an endpoint that targets
it, and both sides agree over a tunnel that rides Google's private
network.

The mechanics are simple. The details are where you lose a weekend if
you are not careful. This post walks through the whole flow and the
places where I have seen most people stumble. The companion repository
has the Terraform and scripts that go with it:

> <https://github.com/neo4j-field/neo4j-aura-gcp-psc>

## The picture

![PSC architecture: App Client in a Customer VPC subnet, Interface Endpoint, Private Service Connect tunnel, AuraDB VPC, and three DB nodes](../screenshots/00-architecture.png)

Two sides, two people. On the Aura side, the operator adds the consumer
project to an allowlist, grabs a couple of identifiers from the Aura
wizard, and later disables public traffic. On the consumer side,
Terraform creates a PSC endpoint, a static internal IP, and a Cloud DNS
response policy that rewrites Aura's hostnames to that internal IP.
Once both halves are in place, a driver inside the consumer VPC
resolves the Aura FQDN to a `10.x` address and the Bolt connection
flows over Google's backbone.

Five resources land in the consumer project. A reserved internal IP, a
forwarding rule, a response policy, and two response policy rules (one
for the wildcard, one for the apex). Plus a small test VM so you can
prove the path works end to end.

## Before you begin

- A running Neo4j Aura VDC instance on GCP. Note which region it is in;
  same-region deployments are simpler and do not require Premium Tier
  networking.
- A consumer GCP project where you will create the endpoint.
- `gcloud` authenticated with application-default credentials on that
  project, and Terraform 1.5 or newer.
- IAM on the consumer project: `roles/compute.networkAdmin`,
  `roles/compute.instanceAdmin.v1`, `roles/dns.admin`,
  `roles/iam.serviceAccountUser`, and
  `roles/iap.tunnelResourceAccessor` for users who will RDP via IAP.

## Step 1: Allowlist your consumer project and collect the two Terraform inputs

This all happens in the Aura Console's three-step **network access
configuration** wizard. Step 1 of the wizard allowlists your consumer
project, step 2 hands you the two values Terraform will need, and
step 3 disables public traffic. We will only do steps 1 and 2 now, and
come back to step 3 at the very end, after we have validated the
private path.

### Wizard Step 1: Target GCP Project ID's

In the Aura Console, open the network access wizard from
**Project > Settings > Private endpoints**, and on wizard Step 1 of 3,
click **Add project ID** under **Target GCP Project ID's**. Paste the
consumer project ID you will run Terraform in, exactly as it appears
in the GCP Console's **ID** column (not the friendly project name):

![Aura wizard Step 1 of 3 with the consumer GCP project ID added](../screenshots/03-aura-wizard-step1-target-projects.jpg)

This string is the gate. Aura compares it to the `projects/<id>/...`
path on the inbound PSC connection. If they do not match exactly, the
connection stays in `PENDING` forever. Click **Next**.

### Wizard Step 2: copy the Service Attachment URL and the DNS Name

Wizard Step 2 is where Aura surfaces the two identifiers you need in
`terraform.tfvars`. The Service Attachment URL is at the top of the
page with a **Copy** button:

![Aura wizard Step 2 of 3 showing the Service Attachment URL with a Copy button](../screenshots/05-aura-wizard-step2-service-attachment.png)

That URL, copied verbatim, is your `neo4j_service_attachment`.

Scroll down on the same page and Aura prints the GCP-side setup steps
that Terraform will perform for you. Inside those steps, the **DNS
Name** field is highlighted. The middle segment of that DNS name
(`production-orch-NNNN`) is your `neo4j_orch_subdomain`. Ignore the
leading wildcard and trailing dot; Terraform adds those.

For now, click **Finish later** to save the wizard state and exit. You
will return to Step 3 of the wizard in the final step of this guide.

## Step 2: Provision the consumer side with Terraform

### Install Terraform

If you do not already have it, grab the official binary from
<https://releases.hashicorp.com/terraform/1.14.9/>. HashiCorp ships
signed zips for macOS (arm64 and amd64), Linux, and Windows. On
macOS Apple Silicon, that is:

```bash
VERSION=1.14.9
cd /tmp
curl -fsSL -O https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_darwin_arm64.zip
unzip -q terraform_${VERSION}_darwin_arm64.zip
mkdir -p ~/.local/bin && mv terraform ~/.local/bin/
terraform version
```

Linux users: swap `darwin_arm64` for `linux_amd64` and install to
`/usr/local/bin`. Windows users: `winget install HashiCorp.Terraform`.
The companion repository README has the full per-platform recipe and a
checksum step for anyone who wants extra confidence in the download.

### Clone the template

```bash
git clone https://github.com/neo4j-field/neo4j-aura-gcp-psc.git
cd neo4j-aura-gcp-psc
```

The root of the repo has `main.tf`, `variables.tf`, and `outputs.tf`
that wire together four reusable modules under `modules/`. You will
not normally edit those; you edit `terraform.tfvars`. Copy the
example file, which is already shaped with comments explaining each
knob:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Three values are required:

```hcl
consumer_project_id      = "<your-consumer-project>"
neo4j_service_attachment = "<Service Attachment URL from wizard Step 2>"
neo4j_orch_subdomain     = "<orchestrator subdomain from wizard Step 2>"
```

The networking module has two modes. By default it creates a new VPC,
subnet, and firewall rules. For a first deployment it is often simpler
to reuse the project's existing `default` VPC:

```hcl
create_network        = false
existing_network_name = "default"
existing_subnet_name  = "default"
```

Under the hood, Terraform splits the work across four modules.
`networking` either creates new VPC resources or looks up existing ones
by name. `psc_endpoint` reserves a static internal IP with
`purpose = GCE_ENDPOINT` and then a forwarding rule with
`load_balancing_scheme = ""` targeting the Aura service attachment.
`dns` attaches a response policy to the VPC and creates two local-data
rules, one for the wildcard and one for the apex. `test_vm` optionally
creates a Windows Server 2022 Shielded VM for validation.

## Step 3: Apply and confirm the connection

```bash
terraform init
terraform plan -out=tfplan.binary
terraform apply tfplan.binary
```

A clean apply against a pre-allowlisted project lands in about 30
seconds, and the key signal in the outputs is:

```
psc_connection_status = "ACCEPTED"
```

`ACCEPTED` means Aura has matched your inbound connection against the
allowlist entry from wizard Step 1 and is carrying traffic. `PENDING`
means the strings did not match; go back and compare character by
character.

You can confirm the same thing from the GCP Console side under
**Network services > Private Service Connect > Connected endpoints**:

![GCP Console showing the PSC endpoint as Accepted](../screenshots/08-gcp-psc-accepted.png)

## Step 4: Validate the path without touching the VM

Before logging into the test VM, you can prove the PSC path is
reachable from the GCP side using a Connectivity Test. Open
**Network Intelligence > Connectivity Tests > Create** and set the
source to your test VM, the destination to the PSC endpoint, and the
port to 7687 (or 443). GCP walks the path hop by hop and returns a
reachability report with per-hop traces through the egress firewall,
the subnet route, and the PSC forwarding rule.

This is my favorite sanity check when something is not working. It
either tells you the packet is delivered at the forwarding rule, or
it points at the exact hop that blocked it, before you burn any time
chasing down DNS inside a VM.

## Step 5: Validate from inside the VPC

A Cloud DNS response policy only applies to queries that originate
from the VPC it is attached to. That means your laptop cannot test
this; a VM inside the VPC has to. The Terraform project spins up a
Windows Server 2022 VM for exactly this reason. Connect over RDP
(using the ephemeral external IP, or via IAP tunnel), and run this
PowerShell one-liner:

```powershell
$h="<dbid>.production-orch-NNNN.neo4j.io"
$ip="<psc_endpoint_ip from terraform output>"
$dns=(Resolve-DnsName $h -Type A -ErrorAction SilentlyContinue).IPAddress
Write-Host "DNS answer : $dns"
443,7687,7474,8491 | ForEach-Object {
  $r = Test-NetConnection -ComputerName $h -Port $_ -WarningAction SilentlyContinue
  $s = if ($r.TcpTestSucceeded) { "PASS" } else { "FAIL" }
  Write-Host ("TCP {0,-5}: {1}" -f $_, $s)
}
```

What you want to see is DNS returning the PSC internal IP (not a
public address) and TCP reachability on 443, 7687, and 7474. Port
8491 is only used by Graph Analytics, so a failure there is fine
unless you use GDS.

## Step 6: Prove it with Neo4j Browser

Open a browser on the Windows VM and go to the instance's private
URI, not the public one that ships in the downloadable credentials
file. In the Connect to instance dialog, use `neo4j+s://` and the
same private hostname.

![Neo4j Browser connecting to Aura over the private URI](../screenshots/11-neo4j-browser-connect.png)

Once you are in, the test that makes the whole thing tangible is:

```cypher
SHOW DATABASES YIELD name, address, role;
```

Every address in the result set points at an internal cluster node
under the same wildcard:

![SHOW DATABASES results with cluster node addresses resolved via the wildcard DNS rule](../screenshots/12-neo4j-browser-show-databases.png)

This is the moment I like. It is not just that one connection works.
Bolt routing is looking up several cluster member hostnames, all of
the form `p-<dbid>-<shard>.production-orch-NNNN.neo4j.io:7687`, and
every one of those lookups is being rewritten by the Cloud DNS
response policy to the PSC endpoint IP. Every driver session, every
routing refresh, every one of those cluster addresses rides the PSC
tunnel.

## Step 7: Finish the Aura wizard

Now go back to the Aura Console, reopen the same wizard from
**Project > Settings > Private endpoints**, and click through to
**Step 3 of 3**. Check **Disable public traffic**, tick the VPN
acknowledgment, and click **Save**. From this point on, every client
on the internet will be refused and the only way into the instance is
through the PSC path you just built.

If you flip the toggle before step 6 passes, you lose all access to
the instance from anywhere outside the consumer VPC. Uncheck it and
save to recover.

## Lessons I would save you if we were pair-programming

**Two DNS rules, not one.** The Aura public documentation specifies a
wildcard record, and in-console instructions show the apex. Cloud DNS
response policy rules do not do subtree matching, so the rule for
`*.production-orch-NNNN.neo4j.io.` will not catch a query for the apex
`production-orch-NNNN.neo4j.io.` and vice versa. Create both. The
Terraform module does this automatically.

**The credentials file gives you the public URI.** When you download
credentials from the Aura Console, the `NEO4J_URI` is
`<dbid>.databases.neo4j.io`. That hostname resolves via public DNS
and routes over the public internet, which bypasses PSC entirely. For
private connectivity you use the private URI,
`<dbid>.production-orch-NNNN.neo4j.io`. Same username and password,
different hostname.

**Aura calls the service attachment "Private Link service name" in
the console.** It is the same thing as the GCP service attachment
URI; the labeling throws people off when they first look for it.

**Same region avoids a whole class of bugs.** Cross-region PSC
(producer and consumer in different GCP regions) works, but requires
Premium Tier networking. Same-region deployments avoid that
requirement and have lower latency. If you have the choice, match the
regions.

**Do not flip Disable public traffic first.** The Aura wizard is
tempting because it is right there in front of you. Validate the
private path from inside the VPC before you check that box, or you
will be recovering from the Aura Console instead of celebrating.

## Get the code

Terraform, scripts, architecture notes, and the design history are
all in the repository:

> **<https://github.com/neo4j-field/neo4j-aura-gcp-psc>**

The README walks through the same seven steps with the full commands
and every screenshot. The `prompts/` folder preserves how the design
evolved. If you find a gotcha I missed, open an issue or a PR.
