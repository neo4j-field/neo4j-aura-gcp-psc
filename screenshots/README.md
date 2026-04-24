# Screenshots

Reference images embedded in the walkthrough in the top-level
[README.md](../README.md) and the blog draft in [../blog/](../blog/).
Filenames are numerically prefixed so they sort in the same order they
appear in the guide.

| File                                          | Step | What it shows                                                                                           |
| --------------------------------------------- | ---- | ------------------------------------------------------------------------------------------------------- |
| `00-architecture.png`                         | Intro | High-level architecture: App Client in a Customer VPC, Interface Endpoint, PSC tunnel, AuraDB VPC, and three DB nodes. |
| `01-aura-settings-menu.png`                   | 1.1  | Aura Console left nav, hovering over **Project > Settings** to open project settings.                    |
| `02-aura-private-endpoints.jpg`               | 1.1  | Aura Project settings page with the **Private endpoints** tile highlighted.                              |
| `03-aura-wizard-step1-target-projects.jpg`    | 1.2  | Wizard Step 1 of 3, consumer GCP project ID added under **Target GCP Project ID's**.                     |
| `04-gcp-project-id.jpg`                       | 1.2  | GCP Console resource picker highlighting the **ID** column, so you know which string to paste into Aura. |
| `05-aura-wizard-step2-service-attachment.png` | 1.3  | Wizard Step 2 of 3 with the **Service Attachment URL** ready to copy.                                    |
| `06-aura-wizard-step2-dns-name.jpg`           | 1.3  | Wizard Step 2 of 3 scrolled to the GCP-side instructions, with the **DNS Name** (`production-orch-NNNN.neo4j.io.`) highlighted. |
| `07-aura-wizard-step3-disable-public.png`     | 1.4 / 8 | Wizard Step 3 of 3 with the **Disable public traffic** checkbox and the VPN acknowledgment.           |
| `08-gcp-psc-accepted.png`                     | 4    | GCP Console > Private Service Connect > Connected endpoints, showing the endpoint status as **Accepted**. |
| `09-gcp-connectivity-test-create.png`         | 6    | GCP Network Intelligence > Connectivity Tests > Create, with source VM and destination PSC endpoint filled in. |
| `10-gcp-connectivity-test-result.jpg`         | 6    | Connectivity Test results: 50/50 packets delivered, reachable forward and return, trace through the PSC forwarding rule. |
| `11-neo4j-browser-connect.png`                | 7    | Neo4j Browser on the Windows VM, connecting to the instance via the private URI `neo4j+s://<dbid>.production-orch-NNNN.neo4j.io`. |
| `12-neo4j-browser-show-databases.png`         | 7    | `SHOW DATABASES` results: cluster node addresses of the form `p-<dbid>-<shard>.production-orch-NNNN.neo4j.io:7687`, end-to-end proof that Bolt routing traverses PSC. |
