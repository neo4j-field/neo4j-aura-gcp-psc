# Screenshots

Reference images embedded in the walkthrough in the top-level [README.md](../README.md).
Filenames are prefixed with the step number they illustrate.

| File                                       | Step | What it shows                                                                 |
| ------------------------------------------ | ---- | ----------------------------------------------------------------------------- |
| `01-aura-network-access-config.jpg`        | 1    | Aura Console: Edit network access configuration, step 1 of 3, consumer GCP project ID added to "Target GCP Project ID's". |
| `02-neo4j-browser-connect.png`             | 7    | Neo4j Browser on the Windows VM, connecting to the instance via the private URI `neo4j+s://<dbid>.production-orch-NNNN.neo4j.io`. |
| `03-neo4j-browser-show-databases.png`      | 7    | `SHOW DATABASES` results: cluster node addresses resolve through the wildcard DNS rule (`p-<dbid>-<shard>.production-orch-NNNN.neo4j.io:7687`), end-to-end proof that Bolt routing traverses PSC. |
