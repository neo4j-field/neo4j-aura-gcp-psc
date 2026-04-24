---
title: "Private Networking for Neo4j Aura on GCP, Step by Step with Private Service Connect"
slug: neo4j-aura-gcp-private-service-connect
excerpt: "A practical, end-to-end walkthrough of connecting Neo4j Aura VDC to a GCP consumer VPC over Private Service Connect, with Terraform and live validation."
author: Guhan Sivaji
categories: [Aura, GCP, Networking]
tags: [neo4j-aura, gcp, private-service-connect, psc, terraform, cloud-dns]
featured_image: screenshots/03-neo4j-browser-show-databases.png
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

```
          Consumer project                             Producer project
          +---------------------------------+          +------------------------------+
          | Consumer VPC                    |   PSC    | Neo4j Aura VDC               |
          |  +---------------------------+  |  (GCP    |  +------------------------+  |
          |  | Consumer subnet           |  | backbone)|  | Service attachment     |  |
          |  |                           |  | <======> |  | db-ingress-private     |  |
          |  |  PSC endpoint             |  |          |  |                        |  |
          |  +---------------------------+  |          |  +------------------------+  |
          |                                 |          +------------------------------+
          |  Cloud DNS response policy      |
          |  *.production-orch-NNNN.neo4j.io|
          |      -> PSC endpoint IP         |
          +---------------------------------+
```

Two sides, two people. On the Aura side, the operator adds the consumer
project to an allowlist and, after validation, disables public access.
On the consumer side, Terraform creates a PSC endpoint, a static
internal IP, and a Cloud DNS response policy that rewrites Aura's
hostnames to that internal IP. Once both halves are in place, a driver
inside the consumer VPC resolves the Aura FQDN to a `10.x` address and
the Bolt connection flows over Google's backbone.

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

## Step 1: Allowlist your consumer project in the Aura Console

Before you run any Terraform, two things happen in the Aura Console.
You give Aura permission to accept a PSC connection from your consumer
project, and you collect the two identifiers Terraform will need in
step 3.

### 1.1 Open the network access wizard

Log into the Aura Console at <https://console.neo4j.io>, click the
instance tile for the database you are securing, and look for
**Network access configuration**. Click **Edit** to open the
three-step wizard.

### 1.2 Step 1 of 3, Instance Type and Target GCP Project ID's

Pick the **Instance Type** that matches the instance you are
securing (for example, AuraDB Professional, Enterprise, or Business
Critical). Under **Target GCP Project ID's**, click **Add project ID**
and type the GCP project ID where Terraform will run. This is the
consumer project ID, not the Aura producer project.

![Aura Console network access configuration with the consumer project ID added](../screenshots/01-aura-network-access-config.jpg)

Aura compares this exact string against the `projects/<id>/...` path
on the inbound PSC connection. A typo or a trailing space here means
the Terraform-created endpoint will sit at `PENDING` indefinitely, so
double-check it. If you see an amber **All regions configured** banner,
that is informational: it means regions were set on a previous pass
and you are in edit mode. Click **Next**.

### 1.3 Step 2 of 3, Region

Confirm the region where your Aura instance lives. Aura displays each
region already configured for the instance type you picked; nothing
usually needs to change here. Click **Next**.

### 1.4 Step 3 of 3, Review and save

Review the summary and click **Save** (or **Finish**). The wizard
closes and you land back on the instance page.

### 1.5 Collect the two Terraform inputs from the instance page

After saving, the instance page shows two PSC-specific values. You
will paste both into `terraform.tfvars` in step 3.

- **Private Link service name**, which is the underlying GCP service
  attachment URI. For GCP Aura, this points at a shared Neo4j ingress
  project in the same region as your instance and looks like this:

  ```
  https://www.googleapis.com/compute/v1/projects/<aura-ingress-project>/regions/<aura-region>/serviceAttachments/<name>
  ```

  A concrete example for `us-central1` is
  `https://www.googleapis.com/compute/v1/projects/ni-production-rd1p/regions/us-central1/serviceAttachments/db-ingress-private`.
  Copy the value the console shows verbatim. The Terraform project
  accepts both the full `https://www.googleapis.com/...` form and the
  shortened `projects/.../serviceAttachments/...` form.

- **Orchestrator subdomain**, which is the middle segment of the
  instance's **Private URI**. The Private URI is a hostname of the
  form:

  ```
  <dbid>.production-orch-NNNN.neo4j.io
  ```

  For example, `c466fb81.production-orch-0792.neo4j.io` breaks into
  three parts: `c466fb81` is your instance ID, `production-orch-0792`
  is the orchestrator subdomain (this is what Terraform needs),
  and `neo4j.io` is the public suffix. Copy only the middle segment.
  Terraform will build the wildcard DNS override
  `*.production-orch-0792.neo4j.io` from it.

  If the console is showing a **Connection URI** that looks like
  `neo4j+s://<dbid>.databases.neo4j.io`, that is the public URI and
  not what you want. The Private URI only appears once Private Link
  is enabled on the instance; if you do not see it, close the
  instance page and reopen it after saving the wizard.

You should now have three things written down:

1. Your consumer GCP project ID (the string you typed into **Target GCP Project ID's**).
2. The Private Link service name (the long `https://www.googleapis.com/...` URL).
3. The orchestrator subdomain (`production-orch-NNNN`).

## Step 2: Provision the consumer side with Terraform

Clone the repo and copy the example variables file.

```bash
git clone https://github.com/neo4j-field/neo4j-aura-gcp-psc.git
cd neo4j-aura-gcp-psc
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`. Three values are required:

```hcl
consumer_project_id      = "<your-consumer-project>"
neo4j_service_attachment = "<Private Link service name from step 1>"
neo4j_orch_subdomain     = "<orchestrator subdomain from step 1>"
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

## Step 3: Apply and watch the connection transition

```bash
terraform init
terraform plan -out=tfplan.binary
terraform apply tfplan.binary
```

A clean apply against a pre-allowlisted project lands in about 30
seconds, and the key signal you are looking for in the outputs is:

```
psc_connection_status = "ACCEPTED"
```

`ACCEPTED` means the producer side (Aura) has matched your inbound
connection against the allowlist entry you created in step 1 and is
ready to carry traffic. `PENDING` means the allowlist entry does not
match. If you see `PENDING`, go back and compare the strings character
by character.

## Step 4: Validate from inside the VPC

A Cloud DNS response policy only applies to queries that originate from
the VPC it is attached to. That means your laptop cannot test this; a
VM inside the VPC has to. The Terraform project spins up a Windows
Server 2022 VM for exactly this reason. Connect to it over RDP, either
via the ephemeral external IP or via an IAP tunnel (the repo README
shows both paths), and from PowerShell run:

```powershell
$h="<dbid>.production-orch-NNNN.neo4j.io"
$ip="10.128.0.50"
$dns=(Resolve-DnsName $h -Type A -ErrorAction SilentlyContinue).IPAddress
Write-Host "DNS answer : $dns"
443,7687,7474,8491 | ForEach-Object {
  $r = Test-NetConnection -ComputerName $h -Port $_ -WarningAction SilentlyContinue
  $s = if ($r.TcpTestSucceeded) { "PASS" } else { "FAIL" }
  Write-Host ("TCP {0,-5}: {1}" -f $_, $s)
}
```

What you want to see is DNS returning `10.128.0.50` (the PSC endpoint
internal IP, not a public address) and TCP reachability on 443, 7687,
and 7474. Port 8491 is only used by Graph Analytics, so a failure there
is fine unless you use GDS.

## Step 5: Prove it with Neo4j Browser

Open a browser on the Windows VM and go to the instance's private URI,
not the public one that ships in the downloadable credentials file. In
the Connect to instance dialog, use `neo4j+s://` and the same private
hostname.

![Neo4j Browser connecting to Aura over the private URI](../screenshots/02-neo4j-browser-connect.png)

Once you are in, the test that makes the whole thing tangible is:

```cypher
SHOW DATABASES YIELD name, address, role;
```

Every address in the result set points at an internal cluster node
under the same wildcard:

![SHOW DATABASES results with cluster node addresses resolved via the wildcard DNS rule](../screenshots/03-neo4j-browser-show-databases.png)

This is the moment I like. It is not just that one connection works.
Bolt routing is looking up several cluster member hostnames, all of
them of the form `p-<dbid>-<shard>.production-orch-NNNN.neo4j.io:7687`,
and every one of those lookups is being rewritten by the Cloud DNS
response policy to `10.128.0.50`. Every driver session, every routing
refresh, every one of those cluster addresses rides the PSC tunnel.

## Lessons I would save you if we were pair-programming

**Two DNS rules, not one.** The Aura public documentation specifies a
wildcard record, and in-console instructions show the apex. Cloud DNS
response policy rules do not do subtree matching, so the rule for
`*.production-orch-NNNN.neo4j.io.` will not catch a query for the apex
`production-orch-NNNN.neo4j.io.` and vice versa. Create both. The
Terraform module does this automatically.

**The credentials file gives you the public URI.** When you download
credentials from the Aura Console, the `NEO4J_URI` is
`<dbid>.databases.neo4j.io`. That hostname resolves via public DNS and
routes over the public internet, which bypasses PSC entirely. For
private connectivity you use the private URI,
`<dbid>.production-orch-NNNN.neo4j.io`. Same username and password,
different hostname.

**Aura calls the service attachment "Private Link service name" in the
console.** It is the same thing as the GCP service attachment URI; the
labeling throws people off when they first look for it.

**Same region avoids a whole class of bugs.** Cross-region PSC
(producer and consumer in different GCP regions) works, but requires
Premium Tier networking. Same-region deployments avoid that requirement
and have lower latency. If you have the choice, match the regions.

**Disable Public Access last, not first.** It is tempting to flip the
"Disable Public Access" toggle in the Aura Console early to prove the
private path works. If you do that before validating the private path
from inside the VPC, you will lose all access to the instance and have
to flip it back from the console to recover. Validate first, harden
second.

## What to do next

Once the private path is working, three follow-ups are worth doing:

1. **Disable Public Access** on the Aura instance. This is the
   hardening step that forces every client onto PSC.
2. **Tighten your RDP surface.** The GCP default VPC ships with a
   `default-allow-rdp` rule that allows port 3389 from `0.0.0.0/0`. If
   you leave the test VM running for any length of time, scope that
   rule to your own source CIDR or move RDP behind IAP only.
3. **Destroy the test VM.** `terraform destroy -target=module.test_vm`
   removes it without touching the PSC endpoint or DNS override. Keep
   the endpoint; lose the test surface.

## Get the code

Terraform, scripts, architecture notes, and the design history are all
in the repository:

> **<https://github.com/neo4j-field/neo4j-aura-gcp-psc>**

The README walks through the same eight steps with the full commands,
and the `prompts/` folder preserves how the design evolved. If you find
a gotcha I missed, open an issue or a PR.
