# Site Setup Guide

This page outlines the software dependencies for a Kubernetes-based install of NCX Infra Controller (NICo). It includes the *validated baseline* of software dependencies,
as well as the *order of operations* for site bringup, including what you must configure if you already operate some of the common services yourself.

**Important Notes**

- All unknown values that you must supply contain explicit placeholders like `<REPLACE_ME>`.

- If you *already run* one of the core services (e.g. PostgreSQL, Vault,
  cert‑manager, Temporal), follow the **If you already have this service**
  checklist for that service.

- If you *don't already have a core service*, deploy the **Reference version** (images
  and versions below) and apply the configuration under **If you deploy the reference version**.

## Validated Baseline

This section lists all software dependencies, including the versions validated for this release of NICo.

### Kubernetes and Node Runtime

- **Control plane**: Kubernetes v1.30.4 (server)

- **Nodes**: kubelet v1.26.15, container runtime containerd 1.7.1

- **CNI**: Calico v3.28.1 (node & controllers)

- **OS**: Ubuntu 24.04.1 LTS

### Networking

- **Ingress**: Project Contour v1.25.2 (controller) + Envoy v1.26.4 (daemonset)

- **Load balancer**: MetalLB v0.14.5 (controller and speaker)

### Secret and Certificate Plumbing

- **External Secret Management System:** External Secrets Operator v0.8.6

- **Certificate Manager**: cert‑manager v1.11.1 (controller/webhook/CA‑injector)

  - Approver‑policy v0.6.3 (Pods present as cert-manager, cainjector, webhook, and policy controller.)

### State and Identity

- **PostgreSQL**: Zalando Postgres Operator v1.10.1 + Spilo‑15 image 3.0‑p1 (Postgres 15)

- **Vault**: Vault server v1.14.0, vault‑k8s injector v1.2.1

### Temporal and Search

- **Temporal server**: Temporal Server v1.22.6 (frontend/history/matching/worker)

  - Admin tools v1.22.4, UI v2.16.2

- **Temporal visibility**: Elasticsearch 7.17.3

### Monitoring and Telemetry (OPTIONAL)

These components are not required for NICo setup, but are recommended site metrics.

- **Monitoring System**:  Prometheus Operator v0.68.0; Prometheus v2.47.0; Alertmanager v0.26.0

- **Monitoring Platform**: Grafana v10.1.2; kube‑state‑metrics v2.10.0

- **Telemetry Processing**: OpenTelemetry Collector v0.102.1

- **Log aggregator**: Loki v2.8.4

- **Host Monitoring** Node exporter v1.6.1

### NICo Components

The following services are installed during the NICo installation process.

- **NICo core (forge‑system)**

  - nvmetal-carbide:v2025.07.04-rc2-0-8-g077781771 (primary carbide-api, plus supporting workloads)

- **cloud‑api**: nvcr.io/nvidian/nvforge-devel/cloud-api:v0.2.72 (two replicas)

- **cloud‑workflow**: nvcr.io/nvidian/nvforge-devel/cloud-workflow:v0.2.30 (cloud‑worker, site‑worker)

- **cloud‑cert‑manager (credsmgr)**: nvcr.io/nvidian/nvforge-devel/cloud-cert-manager:v0.1.16

- **elektra-site-agent**: nvcr.io/nvidian/nvforge-devel/forge-elektra:v2025.06.20-rc1-0

## Order of Operations

This section provides a high-level order of operations for installing components:

1. Cluster and networking ready

   - Kubernetes, containerd, and Calico (or conformant CNI)

   - Ingress controller (Contour/Envoy) + LoadBalancer (MetalLB or cloud LB)

   - DNS recursive resolvers and NTP available

2. Foundation services (in the following order)

   - **External Secrets Operator (ESO) - Optional**

   - **cert‑manager**: Issuers/ClusterIssuers in place

   - **PostgreSQL**: DB/role/extension prerequisites below

   - **Vault**: PKI engine, K8s auth, policies/paths

   - **Temporal**: server up; register namespaces

3.  Carbide core (forge‑system)

   - carbide-api and supporting services (DHCP/PXE/DNS/NTP as required)

4.  Carbide REST components

    - Deploy cloud‑api, cloud‑workflow (cloud‑worker & site‑worker), and cloud‑cert‑manager (credsmgr)

    - Seed DB and register Temporal namespaces (cloud, site, then site UUID)

    - Create OTP and bootstrap secrets for elektra‑site‑agent; roll restart it.

5.  Monitoring

    - Prometheus operator, Grafana, Loki, OTel, node exporter

## Installation Steps

This section provides additional details for each set of components that you need, including additional configuration steps if you already have some of the components.

### External Secrets Operator (ESO)

**Reference version**: `ghcr.io/external-secrets/external-secrets:v0.8.6`

You must provide the following:

- A SecretStore/ClusterSecretStore pointing at **Vault** and, if
  applicable, a Postgres secret namespace.

- ExternalSecret objects similar to these (namespaces vary by
  component):

  - `forge-roots-eso`: Target secret `forge-roots` with keys` site-root`,
    `forge-root`

  -  DB credentials ExternalSecrets per namespace (e.g `clouddb-db-eso : forge.forge-pg-cluster.credentials`)

-   Ensure an image pull secret (e.g. `imagepullsecret`) exists in the
    namespaces that pull from your registry.

### cert‑manager (TLS and Trust)

**Reference versions**:

-   **Controller/Webhook/CAInjector**: `v1.11.1`

-   **Approver‑policy**: `v0.6.3`

-   **ClusterIssuers** present: `self-issuer`, `site-issuer`, `vault-issuer`, `vault-forge-issuer`

**If you already have cert‑manager**:

- Ensure the version is greater than `v1.11.1`.

- Your `ClusterIssuer` objects must be able to issue the following:

    - Cluster internal certs (service DNS SANs)
    - Any externally‑facing FQDNs you choose

- Approver flows should allow your teams to create Certificate resources for the NVCarbide namespaces.

**If you deploy the reference version**:

-   Install cert‑manager `v1.11.1` and `approver‑policy v0.6.3`.

-   Create ClusterIssuers matching your PKI: `<ISSUER_NAME>`.

-   Typical **SANs** for NVFORGE services include the following:

    -   Internal service names (e.g. `carbide-api.<ns>.svc.cluster.local`, `carbide-api.forge`)

    -   Optional external FQDNs (your chosen domains)

### Vault (PKI and Secrets)

**Reference versions**:

-   **Vault server**: `v1.14.0` (HA Raft)

-   **Vault injector (vault‑k8s)**: `v1.2.1`

**If you already have Vault**:

-   Enable PKI engine(s) for the root/intermediate CA chain used by NVFORGE components (where
    your `forge-roots`/`site-root` are derived).

-   Enable K8s auth at path `auth/kubernetes` and create roles that
    map service accounts in the following namespaces: `forge-system`, `cert-manager`, `cloud-api`, `cloud-workflow`, `elektra-site-agent`

-   Ensure the following policies/paths (indicative):

    -   KV v2 for application material: `<VAULT_PATH_PREFIX>/kv/*`

    -   PKI for issuance: `<VAULT_PATH_PREFIX>/pki/*`

**If you deploy the reference version**:

-   Stand up Vault **1.14.0** with TLS (server cert for
    `vault.vault.svc`).

-   Configure the following environment variables:

    - `VAULT_ADDR` (cluster‑internal URL, e.g. `https://vault.vault.svc:8200` or `http://vault.vault.svc:8200` if testing)

    - KV mounts and PKI roles. Components expect the following environment variables:

      - `VAULT_PKI_MOUNT_LOCATION`
      - `VAULT_KV_MOUNT_LOCATION`
      - `VAULT_PKI_ROLE_NAME=forge-cluster`

-   Injector (optional) may be enabled for sidecar‑based secret injection.

```{note}
Vault is used by the following components:

-   **carbide‑api** consumes Vault for PKI and secrets (env VAULT\_\*).

-   **credsmgr** interacts with Vault for CA material exposed to the
    site bootstrap flow.
```

### PostgreSQL (DB)

**Reference versions**:

-   **Zalando Postgres Operator**: `v1.10.1`

-   **Spilo‑15 image**: `3.0‑p1` (Postgres `15`)

**If you already have Postgres**

-   Provide a database `<POSTGRES_DB>` and role `<POSTGRES_USER>` with
    password `<POSTGRES_PASSWORD>`.

-   Enable **TLS** (recommended) or allow secure network policy between
    DB and the NVCarbide namespaces.

-   Create extensions (the apps expect these):

    ```bash
    CREATE EXTENSION IF NOT EXISTS btree_gin;
    CREATE EXTENSION IF NOT EXISTS pg_trgm;
    ```

    This can be done with a call like the following:

    ```bash
    psql "postgres://<POSTGRES_USER>:<POSTGRES_PASSWORD>@<POSTGRES_HOST>:<POSTGRES_PORT>/<POSTGRES_DB>?sslmode=<POSTGRES_SSLMODE>" \
        -c 'CREATE EXTENSION IF NOT EXISTS btree_gin;' \
        -c 'CREATE EXTENSION IF NOT EXISTS pg_trgm;'
    ```

-   Make the DSN available to workloads via ESO targets (per‑namespace
    credentials). These are some examples:

    -   `forge.forge-pg-cluster.credentials`
    -   `forge-system.carbide.forge-pg-cluster.credentials`
    -   `elektra-site-agent.elektra.forge-pg-cluster.credentials`

**If you deploy the reference version**:

-   Deploy the Zalando operator and a Spilo‑15 cluster sized for your
    SLOs.

-   Expose a ClusterIP service on `5432` and surface credentials
    through ExternalSecrets to each namespace that needs them.

### Temporal

**Reference versions**:

-   **Temporal server**: `v1.22.6` (frontend/history/matching/worker)

-   **UI**: `v2.16.2`

-   **Admin tools**: `v1.22.4`

-   **Frontend service endpoint (cluster‑internal)**: `temporal-frontend.temporal.svc:7233`

**Required namespaces**:

-   Base: `cloud`, `site`

-   Per‑site: The `<SITE_UUID>`

**If you already have Temporal**

-   Ensure the `frontend gRPC endpoint` is reachable from NVCarbide
    workloads and present the proper `mTLS`/CA if you require TLS.

-   Register the namespaces as follows:

    ```bash
    tctl --ns cloud namespace register
    tctl --ns site  namespace register
    tctl --ns <SITE_UUID> namespace register (once you know the site UUID)
    ```

**If you deploy the reference version**:

-   Deploy Temporal as described above and expose port `7233`.
-   Register the same namespaces as described above.

## Carbide Component Configuration

This section documents what each Carbide workload expects, including the exact image versions used in the
reference environment and the resources that need to be applied in the correct order.

### Site CA Secrets for cloud‑cert‑manager

Before deploying `cloud-cert-manager` (`credsmgr`), two Secrets must exist in the `cert-manager`
to serve as the root CA that Vault uses to issue per-site certificates:

-   **vault-root-ca-certificate**: `data.certificate`; the PEM-encoded root CA certificate
-   **vault-root-ca-private-key**: `data.privatekey`; the PEM-encoded root CA private key

You can create these using your preferred method: PKI, HSM, or a self-signed CA.

#### Creating the Secrets in the Kubernetes cluster

If you already have a root CA, create the secrets directly:

```bash
kubectl -n cert-manager create secret generic vault-root-ca-certificate \
  --from-file=certificate=./cacert.pem
kubectl -n cert-manager create secret generic vault-root-ca-private-key \
  --from-file=privatekey=./ca.key
```

This results in the following:

-   `vault-root-ca-certificate` (in namespace `cert-manager`)
-   `vault-root-ca-private-key` (in namespace `cert-manager`)

As long as the secret names (`vault-root-ca-certificate`, `vault-root-ca-private-key`) and key
names (`certificate`, `privatekey`) match, the rest of this guide (`cloud‑cert‑manager`/`credsmgr,`
ClusterIssuer `vault-issuer`, etc.) will work as described.

### cloud‑cert‑manager ("credsmgr")

**Reference version**: `nvcr.io/nvidian/nvforge-devel/cloud-cert-manager:v0.1.16`

cloud-cert-manager (the **credsmgr** deployment and related RBAC/issuers) is responsible for
issuing mTLS certificates for Temporal access. It performs the following tasks:

- Runs an embedded Vault process that acts as a self-contained certificate issuer.
- Exposes a service (`credsmgr`) that can issue certificates.
- Applies a `CertificateRequestPolicy` and RBAC so only certain namespaces (`temporal`, `cloud-db`, `cloud-workflow`, `cloud-api`) can obtain certs through the service.

#### Kustomize layout

The `cloud-cert-manager` repository contains the following files:

```
deploy/kustomize/
  cert-approval-policy.yaml    # CertificateRequestPolicy (credsmgr-policy-approver)
  cluster-issuer.yaml          # ClusterIssuer "vault-issuer"
  cluster-role.yaml            # ClusterRole "credsmgr-cluster-role"
  cluster-role-binding.yaml    # ClusterRoleBinding "credsmgr-cluster-role-binding"
  deployment.yaml              # credsmgr + embedded Vault containers
  service.yaml                 # Service on ports 8000 (credsmgr) & 8200 (vault)
  namespace.yaml               # namespace definition (cert-manager)
  sa.yaml                      # credsmgr ServiceAccount
  sa-role.yaml                 # Role for secrets in namespace
  sa-rolebinding.yaml          # binds SA to Role
  vault-config-configmap.yaml  # Vault server configuration
  kustomization.yaml           # Kustomize entrypoint
```

#### Reference Environment Behavior

-   **Namespace**: `cert-manager`
-   **ClusterIssuer**: `vault-issuer`
    -   `spec.vault.server` = `http://credsmgr:8200`
    -   `spec.vault.path` = `pki/sign/cloud-cert`
    -   Token for this Issuer is read from K8s Secret `vault-token` (key `token`) in `cert-manager`.
-   **CertificateRequestPolicy**: `credsmgr-policy-approver`
    -   Allows requests using `issuerRef` (ClusterIssuer `vault-issuer`) originating from the
        `temporal`, `cloud-db`, `cloud-workflow`, `cloud-api` namespaces.
    -   RBAC binds the `cert-manager` ServiceAccount to a ClusterRole that can use that policy
        and manage relevant `Certificate`/`CertificateRequest` resources.
-   **credsmgr Deployment**:
    -   Container `credsmgr`:
        -   Env: `FORGE_CERT_MANAGER_SECRET_NAME` -> `"vault-token"`,
            `CERT_MANAGER_NS` -> `"cert-manager"`
        -   Probes on port **8001** (`/healthz`); the service port for credsmgr is **8000**
        -   Mounts: `/vault/secrets/token` (emptyDir), `/vault/secrets/vault-root-ca-certificate`
            (Secret), `/vault/secrets/vault-root-ca-private-key` (Secret)
    -   Container `vault`:
        -   Uses `vault-server-config` ConfigMap as Vault config (file storage, UI, telemetry).
        -   Serves HTTP on ports `8200`/`8201`/`8202` with TLS disabled in the sample config.
-   **Service**: `credsmgr` (ClusterIP) in `cert-manager`
    -   Port `8000` named `credsmgr` -> used by clients for CA functions
    -   Port `8200` named `vault` -> used by ClusterIssuer `vault-issuer` as `spec.vault.server`

#### User Adjustments

This section outlines what you must adjust, and where.

#### Images and Registry

**File:** `deploy/kustomize/kustomization.yaml`

1. Build the `credsmgr` image from source and push it to your registry:

```bash
docker build -t <REGISTRY>/<PROJECT>/cloud-cert-manager:<TAG> .
docker push <REGISTRY>/<PROJECT>/cloud-cert-manager:<TAG>
```

2. If you are using an embedded Vault container, you must also build/push a Vault image.

3. Update the `kustomization.yaml` file:

```yaml
images:
  - name: credsmgr
    newName: <REGISTRY>/<PROJECT>/cloud-cert-manager
    newTag: <TAG>
  - name: vault
    newName: <REGISTRY>/<PROJECT>/vault
    newTag: <VAULT_TAG>
```

4. Ensure registry auth is wired by adding or adjusting `imagePullSecrets` in `deployment.yaml` if needed.

#### Vault Path and Server (ClusterIssuer)

**File:** `deploy/kustomize/cluster-issuer.yaml`

-   `spec.vault.server`: This must point at the Vault endpoint that `vault-issuer` uses. If you are keeping the
    embedded Vault sidecar, the default URL (`http://credsmgr:8200`) is correct. Otherwise, update the URL to that of the external Vault cluster.
-   `spec.vault.path`: This must match the PKI role path in your Vault setup (e.g. `pki_int/sign/<role>`).
-   `tokenSecretRef.name` and `tokenSecretRef.key`: These must match the Secret name and key where the Vault token is stored.

#### Vault Configuration

**File:** `deploy/kustomize/vault-config-configmap.yaml`

The reference config has the following settings:

- A `listener "tcp"` block with the following parameters:
  - `tls_disable = 1`
  - `address = "[::]:8200"`
  - `cluster_address = "[::]:8201"`
- A storage "file" with the path `/vault/data`

You can adjust the configuration as follows:

-   If you want *TLS on Vault*: Adjust the listener to enable TLS and mount certs appropriately.
-   If you want a different *storage backend* (e.g. Raft or cloud KMS auto-unseal): Replace the
    storage "file" block with your chosen storage stanza.
-   You may also tune telemetry or remove `ui = true` according to security requirements.

#### CertificateRequestPolicy and RBAC

**Files:** `cert-approval-policy.yaml`, `cluster-role.yaml`, `cluster-role-binding.yaml`

The `CertificateRequestPolicy`, named `credsmgr-policy-approver`, applies to the ClusterIssuer
`vault-issuer` and restricts usage to the namespaces `temporal`, `cloud-db`, `cloud-workflow`,
`cloud-api`. ClusterRole/Binding gives the cert-manager ServiceAccount the `policy.cert-manager.io/certificaterequestpolicies`
"use" verb and allows it to manage `Certificate`/`CertificateRequest` resources.

You can adjust the configuration as follows:

- Confirm that `subject.organizations`, `ipAddresses`, and `usages` are aligned with
  your PKI policies.
- Retain the ClusterRole/Binding mapping to the `cert-manager` ServiceAccount unless you have a different trust model.

#### Vault token and root CA secrets

**Files:** `cluster-issuer.yaml`, `deployment.yaml`

The `cluster-issuer.yaml` file references the `vault-token` secret, while the `deployment.yaml` file references
the `vault-root-ca-certificate` and `vault-root-ca-private-key` secrets.

Ensure the following are in place:

- A secret named `vault-token` must exist, with `data.token` containing a token with the
  capabilities required for the PKI path.
- The `vault-root-ca-certificate` and `vault-root-ca-private-key` secrets must exist.

#### How to Apply cloud-cert-manager (credsmgr)

First, ensure the following:

- The images for `credsmgr` and `vault` are built and pushed.
- The vault PKI roles/paths and token secrets are configured.
- The `CertificateRequestPolicy` namespaces are adjusted.

Then, use the following command to apply the changes:

```bash
kubectl apply -k ./deploy/kustomize
```

This creates the following:
- The `credsmgr` ServiceAccount/Role/RoleBinding
- The Vault configuration ConfigMap
- The `credsmgr` and `vault` Deployment and Service
- The Vault-backed ClusterIssuer (`vault-issuer`)
- The `CertificateRequestPolicy` and its RBAC bindings

The `cert-manager` should now be able to issue certificates for the designated namespaces by
communicating with Vault through the `credsmgr` service.

### Install Temporal Certificates

```{note}
This reference implementation uses hostnames in the form `<service>.server.temporal.<YOUR_DOMAIN>`. Replace these with hostnames appropriate for your environment.
```

This step pre-provisions the TLS certs that Temporal and the cloud workloads use for mTLS:

-   **Client certs**: Used by cloud-api and cloud-workflow when calling Temporal
-   **Server certs**: Used by Temporal for its cloud, site, and inter-service endpoints

All certs are issued by the `vault-issuer` ClusterIssuer created in the **Vault Path and Server (ClusterIssuer)** section above, and these certs ultimately
chain back to the site root CA secrets from the **Site CA Secrets for cloud‑cert‑manager** section above.

#### Kustomize layout

```
client-cloud-api.yaml         # client cert for cloud-api
client-cloud-workflow.yaml    # client cert for cloud-workflow
server-cloud.yaml             # server cert for "cloud" Temporal endpoint
server-interservice.yaml      # server cert for Temporal inter-service traffic
server-site.yaml              # server cert for "site" Temporal endpoint
kustomization.yaml            # references all of the above
```

`kustomization.yaml` lists these five Certificate resources as resources.

#### Certificate Descriptions

##### Client Certificates

-   `client-cloud-api.yaml`:
    -   **Namespace**: `cloud-api`
    -   **Resource**: `Certificate temporal-client-cloud-certs`
    -   **Produces Secret**: `temporal-client-cloud-certs`
    -   **CN/DNS**: `cloud.client.temporal.<YOUR_DOMAIN>`
    -   **Intended use**: mTLS client cert for the cloud‑api deployment to call Temporal
-   `client-cloud-workflow.yaml`:
    -   **Namespace**: `cloud-workflow`
    -   **Resource**: `Certificate temporal-client-cloud-certs`
    -   **Produces Secret**: `temporal-client-cloud-certs`
    -   **CN/DNS**: `cloud.client.temporal.<YOUR_DOMAIN>`
    -   **Intended use**: mTLS client cert for cloud-worker and site-worker to call Temporal

Both of these client certificates share the following characteristics:

-   `issuerRef`: `name: vault-issuer`, `kind: ClusterIssuer`, `group: cert-manager.io`
-   `usages`: `server auth`, `client auth`
-   Duration: 2160h (90 days), `renewBefore`: 360h (15 days)

Cloud‑side deployments mount these secrets in the following locations:

- `/var/secrets/temporal/certs/client-cloud/` in `cloud-api`
- `/var/secrets/temporal/certs/client-cloud/` in `cloud-workflow`

##### Server Certificates (Temporal Namespace)

All three server certificates live in the `temporal` namespace and are issued by `vault-issuer` with `usages: [server auth, client auth]`.

-   `server-cloud.yaml`:
    -   **Certificate**: `server-cloud-certs`
    -   **Secret**: `server-cloud-certs`
    -   **CN/DNS**: `cloud.server.temporal.<YOUR_DOMAIN>`
    -   **Duration**: 2h, `renewBefore`: 1h
-   `server-interservice.yaml`:
    -   **Certificate**: `server-interservice-certs`
    -   **Secret**: `server-interservice-certs`
    -   **CN/DNS**: `interservice.server.temporal.<YOUR_DOMAIN>`
    -   **Duration**: 2160h / `renewBefore`: 360h
-   `server-site.yaml`:
    -   **Certificate**: `server-site-certs`
    -   **Secret**: `server-site-certs`
    -   **CN/DNS**: `site.server.temporal.<YOUR_DOMAIN>`
    -   **Duration**: 2160h / `renewBefore`: 360h

These Secrets are consumed by your Temporal deployment (frontends, gateways, etc.) according to your Helm values or manifests.

#### Applying the Cloud Certificates

First, ensure that the following prerequisites are met:

- The root CA secrets (`vault-root-ca-certificate`, `vault-root-ca-private-key`) exist in `cert-manager`
- The `cloud-cert-manager` (credsmgr) and the `vault-issuer` ClusterIssuer are healthy.

Then, use the following command to apply the changes:

```bash
kubectl apply -k <path-to-cloud-certs-kustomize>
```

This creates the following resources:

-   `temporal-client-cloud-certs` in namespaces `cloud-api` and `cloud-workflow`
-   `server-cloud-certs`, `server-interservice-certs`, and `server-site-certs` in namespace `temporal`

Verify issuance using the following commands:

```bash
kubectl -n cloud-api      get certificate,secret temporal-client-cloud-certs
kubectl -n cloud-workflow get certificate,secret temporal-client-cloud-certs
kubectl -n temporal       get certificate,secret server-*-certs
```

### cloud‑db (namespace cloud-db)

**Reference version**: `nvcr.io/nvidian/nvforge-devel/cloud-db:v0.1.45`

cloud-db is a *migration job* that initializes or upgrades the cloud database schema. It's *not*
a long-running service: It runs once with a given version, applies migrations to Postgres, and exits.

**Namespace:** `cloud-db`

#### Reference Environment Behavior

* **Namespace**: `cloud-db`
* **Workload type**: one-off Job (e.g., `cloud-db-migration-0-1-45`)  
* **Image / version**:  `nvcr.io/nvidian/nvforge-devel/cloud-db:v0.1.45` (You must replace this with the image from the GitHub repo and push to it to your own registry.  
* **Config source**: A ConfigMap with the following keys:  
  * `dbHost`: hostname/FQDN of the Postgres service  
  * `dbPort`: Postgres port (typically `5432`)  
  * `dbName`: name of the application database (e.g., `forge` or `cloud`)  
  * `dbUser`: logical Postgres user (e.g., `forge`)  
* **Credentials source**: A single DB credential Secret (in our reference: `forge.forge-pg-cluster.credentials`) with the following keys:  
  * `username`
  * `password`
* **Runtime behavior**:  
  * On start, the Job logs the following:
    * `PGUSER`, `DBNAME` and a masked DB URL: `postgres://PGUSER:****@PGHOST:PGPORT/DBNAME`
  * If `PGUSER`, `PGPASSWORD`, or `DBNAME` are missing, the Job fails immediately.  
  * Otherwise, it executes a migration entrypoint (e.g., `/usr/local/bin/migrate.sh`).

#### Configurations that you Must Change

1. **Postgres host and port**:

   - Set `dbHost` to your Postgres service FQDN or hostname.
   - Set `dbPort` to match your DB port (typically `5432`).
2. **Database name and user**:

   - Set `dbName` to the name of the database where cloud schemas live.
   - Set `dbUser` to the Postgres user provisioned for cloud components.

3. **Database credential Secret**:

   - The Job reads `PGUSER` and `PGPASSWORD` from a K8s Secret. In the reference, this is `forge.forge-pg-cluster.credentials` with keys `username` and `password`.
   - Either reuse this name or change the Job environment to point at your Secret name while preserving the key names.

4.  **Image and registry**: Build the image from source and push to your registry:

    ```bash
    docker build -t <REGISTRY>/<PROJECT>/cloud-db:<TAG> .
    docker push <REGISTRY>/<PROJECT>/cloud-db:<TAG>
    ```

    Update the deployment to use `image: <REGISTRY>/<PROJECT>/cloud-db:<TAG>`.

5.  **Image pull details**: If the registry is private, ensure `imagePullSecrets` matches your
    Docker registry secret name.

6.  **Migration job naming and versioning**: The Job name encodes a migration version (e.g.
    `cloud-db-migration-0-1-17`). For new releases, bump both the Job name (e.g. `cloud-db-migration-0-1-18`)
    and the image tag (e.g. `v0.1.18`) so operators can determine which migration ran.

#### How to Apply cloud-db

First, determine if the following Postgres extensions are set up:

```bash
-c 'CREATE EXTENSION IF NOT EXISTS btree_gin;' \
-c 'CREATE EXTENSION IF NOT EXISTS pg_trgm;'
```

If they are not set up, run [create-postgres-extensions.sh](http://create-postgres-extensions.sh) while pointing to the cluster:

```bash
~/go/src/cloud-db/deploy🌴git:(sa-enablement-distroless) ⌚ 21:40:53 » ./create-postgres-extensions.sh

📦 Using database name: forge

⏳  Waiting for StatefulSet postgres/forge-pg-cluster replicas to be Ready...

✅  Postgres StatefulSet is Ready (3/3)
🔑  Running extension SQL inside pod forge-pg-cluster-0
Defaulted container "postgres" out of: postgres, postgres-exporter
CREATE EXTENSION
CREATE EXTENSION
✅  Postgres extensions ensured.
```

Once fields that are specific to your deployment have been updated in the cloud-api Kustomize base (image, registry auth, config, DB secret name, service type),
apply the changes with the following command:

```bash
kubectl apply -k deploy/kustomize/base
```

### cloud‑workflow (namespace cloud-workflow)

**Reference version**: `nvcr.io/nvidian/nvforge-devel/cloud-workflow:v0.2.33`

cloud-workflow provides the *cloud-side Temporal workers*. It has two deployments:

- `cloud-worker`: Processes workflows in the *cloud* Temporal namespace and queue.
- `site-worker`: Processes workflows in the *site* Temporal namespace and queue.

Both deployments read a shared config file and differ only in `TEMPORAL_NAMESPACE`/`TEMPORAL_QUEUE`.

#### Dependencies

Before deploying cloud-workflow, the following must already be in place:

1. **PostgreSQL + schema**
   - The Postgres endpoint is reachable.
   - The database has been created (e.g. `forge` or `cloud`).
   - The cloud-db migration Job has succeeded.
   - The credential Secret (reference: `forge.forge-pg-cluster.credentials`) has been created with `username`/`password`.
2. **Temporal**
   - The frontend gRPC endpoint is reachable from this namespace (reference: `temporal-frontend-headless.temporal.svc.cluster.local:7233`).
   - The temporal namespaces `cloud` and `site` are registered.
3. **Temporal client TLS Secret**: The secret `temporal-client-cloud-certs` containing `tls.crt`, `tls.key`, `ca.crt`has been implemented and mounted at `/var/secrets/temporal/certs/client-cloud/`.
4. **Image registry**: A registry where you will build and push the cloud-workflow image.

#### Reference Environment Behavior

- **Namespace**: `cloud-workflow`
- **Workload type**:
  - Deployment `cloud-worker` (3 replicas)
  - Deployment `site-worker` (3 replicas)
- **Container port**: 8899 (HTTP health/ready); metrics on 9360
- **Liveness/Readiness probes**: `GET /healthz` and `GET /readyz` on port 8899
- **Config file**: `/etc/cloud-workflow/config.yaml` (env `CONFIG_FILE_PATH`)
- **Volumes (both deployments)**:
  - `forge-pg-cluster-auth` -> Secret `forge.forge-pg-cluster.credentials` -> `/var/secrets/db/auth/`
  - `cloud-workflow-config` -> ConfigMap `cloud-workflow-config` -> `/etc/cloud-workflow/`
  - `temporal-client-cloud-certs` -> Secret `temporal-client-cloud-certs` -> `/var/secrets/temporal/certs/client-cloud/`
- **Temporal env per deployment**:
  - `cloud-worker`: `TEMPORAL_NAMESPACE=cloud`, `TEMPORAL_QUEUE=cloud`
  - `site-worker`: `TEMPORAL_NAMESPACE=site`, `TEMPORAL_QUEUE=site`

#### Kustomize layout

```bash
deploy/kustomize/base/cloud-workflow/
  secrets/
    temporal-client-cloud-certs.yaml  # placeholder TLS secret, empty values
  configmap.yaml                      # cloud-workflow-config (config.yaml)
  deployment.yaml                     # cloud-worker + site-worker
  service.yaml                        # Services for each worker deployment
  imagepullsecret.yaml
  namespace.yaml
  kustomization.yaml
```

#### Configurations that you Must Change

**File:** `deploy/kustomize/base/cloud-workflow/configmap.yaml`

The following fields are specific to your environment within the `config.yaml` key:

-   `log.level`: e.g. `debug`, `info`, `warn`
-   `db.*`:
    -   `db.host`: The Postgres host/FQDN
    -   `db.port`: The port (usually `5432`)
    -   `db.name`: The name of the DB
    -   `db.user`: The DB User name
    -   `db.passwordPath`: The path under `/var/secrets/db/auth/` that the app expects
-   `temporal.*`:
    -   `temporal.host`: The Temporal frontend DNS name (e.g.
        `temporal-frontend-headless.temporal.svc.cluster.local`)
    -   `temporal.port`: The port number (typically, `7233`)
    -   `temporal.serverName`: The server name used for TLS validation
    -   `temporal.namespace`: This should match the worker `TEMPORAL_NAMESPACE` env.
    -   `temporal.queue`: This should match the worker `TEMPORAL_QUEUE` env.
    -   `temporal.tls.certPath`, `keyPath`, `caPath`: These must align with the location where
        `temporal-client-cloud-certs` is mounted
-   `siteManager.svcEndpoint`: The full URL for the site API (e.g. `https://sitemgr.cloud-site-manager:8100/v1/site`)

#### Secrets (Placeholders vs. Real Values)

**File:** `deploy/kustomize/base/cloud-workflow/secrets/temporal-client-cloud-certs.yaml`

This file contains empty `tls.crt`, `tls.key`, `ca.crt` values. This is a placeholder and can be applied as-is.

**DB credentials:** `forge.forge-pg-cluster.credentials` must exist in the cluster (via ESO or
manually). If you use a different Secret, update `volumes[].secret.secretName` in
`deployment.yaml` accordingly.

#### Image and registry

The containers in the repository `deployment.yaml` file reference an internal image. For your deployment, you must
do the following:

1. Build from source:

   ```bash
   docker build -t <REGISTRY>/<PROJECT>/cloud-workflow:<TAG> .
   docker push <REGISTRY>/<PROJECT>/cloud-workflow:<TAG>
   ```

2. Update the image reference in the manifests to use your registry URL. There are two ways to accomplish this:

   - Modify the Kustomization file at `deploy/kustomize/base/cloud-workflow/kustomization.yaml`.
     
     ```yaml
     images:
       - name: cloud-workflow
         newName: <REGISTRY>/<PROJECT>/cloud-workflow
         newTag: <TAG>
     ```

   - Modify the `deployment.yaml` directly if you are not using the `images: transform` feature.

3.  Ensure `imagePullSecrets` points at your registry secret when the registry is private.

#### Services

The repository defines internal Services for each worker:

- The `cloud-worker` Service uses port `8899` (HTTP/health) and port `9360` (metrics).
- The `site-worker` Service uses the same ports as the `cloud-worker` Service.

These Services are for internal use (probes/metrics scraping), not direct external traffic.

### How to Apply cloud-workflow

First, ensure the following prerequisites are met:

- cloud-db has completed its migrations.
- DB credentials exist in the expected Secret.
- Temporal is reachable and `cloud`/`site` namespaces exits.
- temporal-client-cloud-certs and any OTEL secrets are populated appropriately.

Then, use the the following command to deploy cloud-workflow:

```bash
kubectl apply -k deploy/kustomize
```

This creates the following resources:

- namespace `cloud-workflow`
- ConfigMap `cloud-workflow-config`
- Secrets in `cloud-workflow/secrets` (as provided/overridden)
- Deployments `cloud-worker` and `site-worker`
- Services for `cloud-worker` and `site-worker`

### cloud‑api (namespace cloud-api)

**Reference version**: `nvcr.io/nvidian/nvforge-devel/cloud-api:v0.2.76`

cloud-api is the **front-end API** for cloud-side operations. It exposes HTTP endpoints and
(optionally) metrics; it reads configuration from a YAML file, connects to the cloud DB, and
integrates with Temporal, site-manager, and optional telemetry backends.

#### Reference Environment Behavior

-   **Namespace:** `cloud-api`
-   **Workload type:** Deployment (2 replicas)
-   **Port/probes:** Container port **8388** (named `api`); liveness: `GET /healthz` on 8388;
    readiness: `GET /readyz` on 8388
-   **Service:** `LoadBalancer` with port **80** → targetPort **8388** (http) and port **9360** →
    targetPort **9360** (metrics)
-   **Config file:** `CONFIG_FILE_PATH=/etc/cloud-api/config.yaml`
-   **Secrets/volumes expected:**
    -   `forge.forge-pg-cluster.credentials` → mounted at `/var/secrets/db/auth/`
    -   `temporal-client-cloud-certs` → mounted at `/var/secrets/temporal/certs/client-cloud/`

#### Kustomize layout

```bash
deploy/kustomize/base/cloud-api/
  secrets/
    ssa-client-secret.yaml              # placeholder
    temporal-client-cloud-certs.yaml    # placeholder
  configmap.yaml                        # cloud-api-config (config.yaml)
  deployment.yaml
  imagepullsecret.yaml                  # replace the secret value
  service.yaml
  namespace.yaml
  kustomization.yaml
```

#### Application Configuration

**File:** `deploy/kustomize/base/cloud-api/configmap.yaml`

The following are important fields inside `config.yaml`:

- `log.level`: log level (e.g. `debug`, `info`)
- `kas.legacyJwksUrl`, `kas.ssaJwksUrl`, `kas.starfleetJwksUrl`: JWKS endpoints for your IdPs
- `db.host`, `db.port`, `db.name`, `db.user`, `db.passwordPath`: DB connection; host and port
   must match your Postgres service; `passwordPath` must match the path under
  `/var/secrets/db/auth/`.
- `temporal.host`, `temporal.port`, `temporal.serverName`, `temporal.namespace`,
  `temporal.queue`:
   - `host`: Must be the Temporal frontend service (e.g. `temporal-frontend-headless.temporal.svc.cluster.local`).
   - `namespace`/`queue`: Must match the Temporal namespace/task queue used by cloud workers (e.g. `cloud`).
   - `tls.certPath`, `keyPath`, `caPath`: Must match how `temporal-client-cloud-certs` is mounted.
- `siteManager.enabled`, `siteManager.svcEndpoint`: URL for site-manager's `v1/site` endpoint

Perform the following actions:

- Update all URLs, hostnames, and ports to match you auth, Temporal, DB, site-manager, and ZincSearch endpoints.
- Update `db.*` to align with your Postgres configuration.
- Confirm TLS paths line up with the volume mount paths in `deployment.yaml`.

#### Deployment and Container image

**File:** `deploy/kustomize/base/cloud-api/deployment.yaml`

This file contains the following key elements:

- `spec.replicas`: default 2; customize for your environment.
- Container:
  - Name: `cloud-api`
  - Image (reference): `nvcr.io/nvidian/nvforge-devel/cloud-api:v0.2.76`
  - Env: `CONFIG_FILE_PATH=/etc/cloud-api/config.yaml`
  - Ports: `8388` named api
- Volume mounts:
  - `/var/secrets/db/auth/` -> `forge.forge-pg-cluster.credentials`
  - `/var/secrets/ssa/` -> `ssa-client-secret`
  - `/etc/cloud-api/` -> `cloud-api-config`
  - `/var/secrets/temporal/certs/client-cloud/` -> `temporal-client-cloud-certs`

Perform the following actions:

1. Replace the image with your own build:
   - **Build**: `docker build -t <REGISTRY>/<PROJECT>/cloud-api:<TAG>`
   - **Push**:  `docker push <REGISTRY>/<PROJECT>/cloud-api:<TAG>`
2. Update the Kustomize images mapping:
   - **File**: `deploy/kustomize/base/cloud-api/kustomization.yaml`
   - **Images**: `set newName: <REGISTRY>/<PROJECT>/cloud-api, newTag: <TAG>`
3. Determine if you want to use `imagePullSecrets`:
   - For private registries, ensure `imagePullSecrets` is present in the Deployment:
     ```yaml
     imagePullSecrets:
       - name: <IMAGEPULLSECRET>
     ```

#### Database Credentials Secret

The deployment mounts a secret named `forge.forge-pg-cluster.credentials` at `/var/secrets/db/auth/`.
This secret is expected to have `username` and `password` keys.

To set up the database credentials secret, perform one of the following actions:

- Keep the secret name `forge.forge-pg-cluster.credentials` and create/populate the secret (ideally, via ESO).
- Change the `volumes[].secret.secretName` value, and any `env.valueFrom.secretKeyRef.name` values, in `deployment.yaml` to the new secret name (e.g. `cloud-db-credentials`).

#### SSA Client Secret (ssa-client-secret)

The SSA client secret consists of two related files:

- `deploy/kustomize/base/cloud-api/secrets/ssa-client-secret.yaml`: A placeholder secret with an empty value (`client-secret: ""`). This value can be either empy or base64. It is safe for non-SSA environments.
- `deploy/kustomize/base/cloud-api/ssa-placeholder-secret.yaml`: A secret with the placeholder value `c3NhLXJlcGxhY2U=` (base64 for "ssa-replace"). You must replace this placeholder value with either a
   real SSA client secret or an empty value (for non-SSA deployments).

#### Temporal Client TLS Certs (temporal-client-cloud-certs)

**File:** `secrets/temporal-client-cloud-certs.yaml`

This file contains empty `tls.crt`, `tls.key`, `ca.crt` parameters.

- **If Temporal requires mTLS**: Fill in `tls.crt`, `tls.key`, and `ca.crt` with base64-encoded values.
- **If Temporal does not use mTLS**: Leave `tls.crt`, `tls.key`, and `ca.crt` blank. Also, ensure the `config.yaml` TLS paths and your Temporal deployment tolerate non-TLS,
  or remove TLS configuration from `config.yaml`.

#### Service Exposure

**File:** `deploy/kustomize/base/cloud-api/service.yaml`

**Reference Behavior**

- `type: LoadBalancer`
- port **80/TCP** -> targetPort `8388`
- port **9360/TCP** -> targetPort `9360`

**Selector:**

- `app: cloud-api`

**Setup Actions:**

1. Decide how cloud-api should be exposed:
  - **Internal only**: Set `type` to `ClusterIP` and front it with Ingress/HTTPProxy.
  - **External**: keep or adjust `LoadBalancer` via your LB/Ingress.
2. Adjust ports if you need different external port numbers, but keep `targetPort` aligned with container ports `8388` for API and `9360` for metrics.

#### How to Apply cloud-api

First, ensure all environment-specific values have been updated:
- `configmap.yaml` (app config)
- `deployment.yaml` (image, registry, secrets, volumes)
- `service.yaml` (type/ports)
- `secrets/` and `ssa-placeholder-secret.yaml` (for secrets, as needed)
- `otel.env` (if telemetry is used)

Then, use the following command to deploy cloud-api:

```bash
kubectl apply -k deploy/kustomize/base/cloud-api
```

### cloud‑site‑manager (namespace cloud-site-manager)

cloud-site-manager (sitemgr) is the "site registry" service. It performs the following tasks:

- Owns the Site CRD and stores per-site metadata as Site objects.
- Talks to `credsmgr` to mint per-site credentials and CA material.
- Exposes an HTTPS API on port `8100`.
  - The bootstrap flow calls this API to create a new site (`/v1/site`).
  - Later, this allows the site agent to fetch its OTP credentials.

#### Dependencies

Before deploying cloud-site-manager, you should already have the following:

- **cert-manager + cloud-cert-manager (credsmgr)**
  - `vault-issuer` ClusterIssuer configured and working
  - `credsmgr` Service reachable at `https://credsmgr.cert-manager:8000` (or an equivalent URL)
- **Vault root CA secrets**: `vault-root-ca-certificate` and `vault-root-ca-private-key` in the
  `cert-manager` namespace (refer to the **Site CA Secrets for cloud‑cert‑manager** section for more details)
- **Kubernetes CRD support**: Standard; no extra setup

There is no direct Postgres or Temporal dependency in this manifest. These dependencies are exercised by other components via the site bootstrap workflows later in the setup process.

#### Reference Environment Behavior

**Namespace:** `cloud-site-manager`

**Workloads:**

- **CRD:** `sites.forge.nvidia.io`
  - Kind: Site
  - Scope: Namespaced
  - `spec` and `status` are both "free-form" (`x-kubernetes-preserve-unknown-fields: true`), so the CRD doesn't constrain your schema.
- **Deployment:** `csm`
  - Replicas: 3
  - Container: `sitemgr`
  - Arguments:
    - `--listen-port=8100`
    - `--creds-manager-url=https://credsmgr.cert-manager:8000`
    - `--ingress-host=sitemgr.cloud-site-manager.svc.cluster.local`
  - Environment
    - `SITE_MANAGER_NS` from `metadata.namespace`
    - `envFrom: secretRef: otel-lightstep` (optional telemetry; can be stubbed or removed)
  -   Probes: Liveness/Readiness/Startup via HTTPS `GET /healthz` on port `8100`
- **RBAC:**
  - Role `site-manager` grants full access to `sites` and `sites/status` in API group `forge.nvidia.io`.
  - RoleBinding binds `site-manager` binds the Role to the `site-manager` ServiceAccount in `cloud-site-manager`.
- **Service:** `sitemgr`
  - Type: ClusterIP
  - Port `8100` -> targetPort `8100`
  - Selector: `app.kubernetes.io/name: csm`
  - Bootstrap flow cURL target: `https://sitemgr.cloud-site-manager:8100/v1/site`

#### Kustomize layout

This is the base Kustomize tree for the cloud‑site‑manager component in the cloud-site-manager repo (`sa‑enablement` branch):

```bash
deploy/kustomize/
  namespace.yaml               # cloud-site-manager namespace
  crd-site.yaml                # Site CRD (sites.forge.nvidia.io)
  deployment.yaml              # csm Deployment (sitemgr container)
  serviceaccount.yaml          # site-manager ServiceAccount
  serviceaccount-role.yaml     # Role for CRD access
  serviceaccount-rolebinding.yaml  # binds Role to site-manager SA
  sitemgr-service.yaml         # ClusterIP Service on port 8100
  kustomization.yaml           # includes the above and overrides the image
```

The `kustomization.yaml` file sets the reference image to the following:

```yaml
images:
  - name: sitemgr
    newName: nvcr.io/nvidian/nvforge-devel/cloud-site-manager
    newTag: v0.1.16
```

#### User Adjustments

##### Image and Registry

First, build the `cloud-site-manager` image from source and push it to your registry:

```bash
docker build -t <REGISTRY>/<PROJECT>/cloud-site-manager:<TAG> .
docker push <REGISTRY>/<PROJECT>/cloud-site-manager:<TAG>
```

Then, update the image mapping in `kustomization.yaml`:

```yaml
images:
  - name: sitemgr
    newName: <REGISTRY>/<PROJECT>/cloud-site-manager
    newTag: <TAG>
```

If the registry is private, ensure `imagePullSecrets` is present in the Deployment; otherwise, it
can be removed.

#### credsmgr URL

The deployment uses this flag by default `--creds-manager-url=https://credsmgr.cert-manager:8000`. If you
rename the credsmgr Service or run it in a different namespace, you must update this flag.

The CA service at this URL must have the following properties:

* It trusts the same root CA that site agents will trust.
* It is able to issue the per‑site certs/OTP material that your bootstrap flow expects.

#### Ingress and Internal Host

The deployment uses this flag by default: `--ingress-host=sitemgr.cloud-site-manager.svc.cluster.local`. This is the
hostname that `sitemgr` uses when constructing URLs and, in some flows, may be placed into certificates or responses.

You have the following options:

- Keep the hostname as the internal DNS name if the service will only ever be called within the cluster.
- Change the hostname to an internal or external FQDN (e.g.` sitemgr.<customer-domain>`). You will also need to esnure the following:
  - The DNS/ingress routes the hostname to the sitemgr Service.
  - Any TLS certs used for sitemgr include this hostname in their SANs.

### How to Apply cloud-site-manager

First, ensure the following are in place:

- `cloud-cert-manager`/`credsmgr` is running and reachable at the URL you specified.
- The Vault root CA secrets (`vault-root-ca-certificate`, `vault-root-ca-private-key`) exist in `cert-manager`.
- The image reference has been updated in your registry.
- You've decided how handle to telemetry Secrets (if applicable).

Then, use the following command to deploy cloud-site-manager:

```bash
kubectl apply -k deploy/kustomize
```

You should see the following output:
```bash
namespace/cloud-site-manager created
customresourcedefinition.apiextensions.k8s.io/sites.forge.nvidia.io created
serviceaccount/site-manager created
role.rbac.authorization.k8s.io/site-manager created
rolebinding.rbac.authorization.k8s.io/site-manager created
service/sitemgr created
deployment.apps/csm created
```

This creates the following:
- The namespace `cloud-site-manager`
- The Site CRD
- The ServiceAccount, Role, and RoleBinding for `site-manager`
- The `csm` Deployment and `sitemgr` Service

### Carbide Core

The following sections document each Carbide core component. All components run in the
`forge-system` namespace and use the `nvmetal-carbide` image unless otherwise noted. For
deployment commands and site bring-up steps, refer to the [Forge System](#forge-system) section below.

#### Carbide API

The Carbide API deployment has the following directory structure:

```
deploy/carbide-base/api/
  api-service.yaml
  certificate.yaml
  config-files/
    carbide-api-config.toml
    casbin-policy.csv
  deployment.yaml
  kustomization.yaml
  metrics-service.yaml
  migration.yaml
  profiler-service.yaml
  role.yaml
  rolebinding.yaml
  service-account.yaml
```

##### High-Level Overview

-   **Primary workload**: `Deployment/carbide-api`
-   **Database migration hook**: `Job/carbide-api-migrate`
-   **Services**:
    -   `Service/carbide-api` (gRPC, port `1079`)
    -   `Service/carbide-api-metrics` (metrics, port `1080`)
    -   `Service/carbide-api-profiler` (profiler, port `1081`)
-   **Config**:
    -   `ConfigMap/carbide-api-config-files` (from `config-files/`; mounted at
        `/etc/forge/carbide-api`)
    -   `ConfigMap/carbide-api-site-config-files` (site-specific overlay; mounted at
        `/etc/forge/carbide-api/site`)
-   **TLS and identity:** `Certificate/carbide-api-certificate` -> `Secret/carbide-api-certificate`
-   **RBAC:** `ServiceAccount/carbide-api`, `Role/carbide-api`, `RoleBinding/carbide-api`

##### External Dependencies You Must Provide

**Secrets**

-   `carbide-vault-token` (key: `token`): Vault root token
-   `carbide-vault-approle-tokens` (optional; keys: `VAULT_ROLE_ID`, `VAULT_SECRET_ID`): AppRole
    auth
-   `forge-system.carbide.forge-pg-cluster.credentials` (keys: `username`, `password`): Postgres
    credentials
-   `forge-roots`: CA bundle for validating peer certificates

**ConfigMaps**

-   `vault-cluster-info` (keys: `VAULT_SERVICE`, `FORGE_VAULT_MOUNT`, `FORGE_VAULT_PKI_MOUNT`)
-   `forge-system-carbide-database-config` (keys: `DB_HOST`, `DB_PORT`, `DB_NAME`)

#### Kustomization Entrypoint (kustomization.yaml)

The `kustomization.yaml` file is the entrypoint that wires all manifests together and applies common labels.
It performs the following steps:

- Adds labels to all resources and their selectors/templates:
  - `app.kubernetes.io/name: carbide-api`
  - `app.kubernetes.io/component: api`
- Declares the resources:
  - `api-service.yaml`
  - `certificate.yaml`
  - `deployment.yaml`
  - `metrics-service.yaml`
  - `profiler-service.yaml`
  - `role.yaml`
  - `rolebinding.yaml`
  - `service-account.yaml`
  - `migration.yaml`
- Generates config maps:
  - `ConfigMap/carbide-api-config-files`
  - From:
    - `config-files/carbide-api-config.toml` (described below)
    - `config-files/casbin-policy.csv` (described below)
    - Mounted into the deployment at `/etc/forge/carbide-api`.
  - `ConfigMap/carbide-api-site-config-files`
    - `files: []` in base
    - Overlays are expected to add site-specific config files
      (e.g. `carbide-api-site-config.toml`).
    - Mounted into the deployment at `/etc/forge/carbide-api/site`.
- `generatorOptions.disableNameSuffixHash: true`
   - Keeps mounts and paths stable
   - Ensures config map names stay exactly:
    - `carbide-api-config-files`
    - `carbide-api-site-config-files`

#### Configuration files (config-files/)

The `config-files/carbide-api-config.toml` file is the shared runtime configuration for carbide-api.

Create a `carbide-api-site-config.toml` file in your site overlay to override keys that are environment
specific, including `dhcp_servers`, `route_servers`, and `admin_root_cafile_path`.

The following are the key values and defaults:

**Core endpoints**

- `listen = "[::]:1079"`
- `metrics_endpoint = "[::]:1080"`
- `profiler_endpoint = "[::]:1081"`

**Database**

- `database_url = "postgres://replaced-by-env-var"`: This is overridden at runtime by the `CARBIDE_API_DATABASE_URL`
  environment variable in the `deployment.yaml` file.

**Firmware/DPU**

- `asn = 4294967000`
- `initial_dpu_agent_upgrade_policy = "up_only"`
- `dpu_nic_firmware_intial_update_enabled = false`
- `dpu_nic_firmware_reprovision_update_enabled = true`
- `dpu_nic_firmware_update_version = { "BlueField SoC" = "24.42.1000", "BlueField-3 SmartNIC Main Card" = "32.42.1000" }`
- `max_concurrent_machine_updates = 10`
- `nvue_enabled = true`
- `dhcp_servers = []` (expected to be filled per site via site config)
- `route_servers = []` (for FNN; currently not used)
- `attestation_enabled = true`
- `bypass_rbac = true`

**Host health**

```toml
[host_health]
hardware_health_reports = "MonitorOnly"
```

**Site explorer**

```toml
[site_explorer]
enabled = true
create_machines = true
```

**Firmware global**

```toml
[firmware_global]
autoupdate = true
```

**TLS**

```toml
[tls]
identity_pemfile_path = "/var/run/secrets/spiffe.io/tls.crt"
identity_keyfile_path = "/var/run/secrets/spiffe.io/tls.key"
root_cafile_path = "/var/run/secrets/spiffe.io/ca.crt"
admin_root_cafile_path = "/etc/forge/carbide-api/site/admin_root_cert_pem"
```

**Auth**

```toml
[auth]
permissive_mode = false
casbin_policy_file = "/etc/forge/carbide-api/casbin-policy.csv"
```

**Machine state controller**

```toml
[machine_state_controller]
failure_retry_time = "45m"
```

**Network security group**

```toml

```toml
[network_security_group]
stateful_acls_enabled = false
max_network_security_group_size = 200
```

**Machine validation**

```toml
[machine_validation_config]
enabled = true
test_selection_mode = "EnableAll"
```

##### Casbin Policy Configuration

**File**: `config-files/casbin-policy.csv`

The Casbin RBAC policy for carbide-api has the following characteristics:

- `g` rules bind principals (SPIFFE IDs or machine IDs) to roles.
- `p` rules grant actions (Forge RPC methods) to roles or principals.
- Example existing rules:
  - Map SPIFFE IDs to roles:
    - `g, spiffe-service-id/carbide-dhcp, carbide-dhcp`
    - `g, spiffe-service-id/carbide-dns, carbide-dns`
    - `g, spiffe-machine-id, machine`
  - Allow carbide-dhcp to call forge/DiscoverDhcp.
  - Allow carbide-dns to call forge/LookupRecord.
  - `p, trusted-certificate, forge/*`: Broad access for trusted certificates (intended to be tightened over time)).
  - `p, anonymous, forge/Version, forge/DiscoverMachine, forge/ReportForgeScoutError, forge/AttestQuote`, and multiple machine-related methods.

To customize the the Casbin RBAC policy, update or add `g` and `p` rules as new services/methods are introduced. Then, carefully tighten or
replace the `trusted-certificate, forge/*` rule as enforcement becomes stricter.

#### Deployment (deployment.yaml)

##### Basic API Spec

- **Kind**: Deployment
- **Name**: `carbide-api`
- **Namespace**: default
- **Replicas**: 1
- **Strategy**: RollingUpdate
- **Selector**: `app.kubernetes.io/name: carbide-api`
- **Pod annotations**:
  - `kubectl.kubernetes.io/default-container: carbide-api`

##### Container

- **Name**: `carbide-api`
- **Image**: `nvcr.io/nvidian/nvforge/nvmetal-carbide:latest`
  - Typically pinned via overlay in real deployments.
- **Command**:
  ```bash
  /opt/carbide/carbide-api run \
  --config-path /etc/forge/carbide-api/carbide-api-config.toml \
  --site-config-path /etc/forge/carbide-api/site/carbide-api-site-config.toml
  ```
- **Security context**:
  - Adds the `SYS_PTRACE` capability.
- **Ports**:
  - `grpc`: `containerPort: 1079`
  - `metrics`: `containerPort: 1080`
  - `profiler`: `containerPort: 1081`
- **Health checks**:
  - `livenessProbe`:
    - `HTTP GET on port 1080` (metrics port)
    - `initialDelaySeconds: 20`
    - `periodSeconds: 20`
    - `timeoutSeconds: 20`
    - `failureThreshold: 3`
- **ServiceAccount**:
  - `serviceAccountName: carbide-api`

##### Volume Mounts and Volumes

**Pod Volumes**

- `carbide-api-config-files`:
  - Type: `ConfigMap`
  - Name: `carbide-api-config-files`
  - Mounted at: `/etc/forge/carbide-api`
- `carbide-api-site-config-files`:
  - Type: `ConfigMap`
  - Name: `carbide-api-site-config-files`
  - Mounted at: `/etc/forge/carbide-api/site`
- `persistence`:
  - Type: `emptyDir: {}`
  - Mounted at: `/mnt/persistence`
- `spiffe`:
  - Type: `Secret`
  - secretName: `carbide-api-certificate`
  - Mounted at: `/var/run/secrets/spiffe.io` (readOnly)
- `forge-roots`:
  - Type: `Secret`
  - secretName: `forge-roots`
  - Mounted at: `/var/run/secrets/forge-roots` (readOnly)
- `firmware`:
  - Type: `emptyDir: {}`
  - Mounted at: `/opt/carbide/firmware` (readOnly in container)

##### Deployment Environment Variables

The following are the environment variables for the carbide-api deployment.

**Vault Integration**

* `VAULT_ROLE_ID`
  - **Source**: `Secret/carbide-vault-approle-tokens`, key `VAULT_ROLE_ID`
  - **Optional**: true
  - **Purpose**: AppRole auth to Vault (if used)
- `VAULT_SECRET_ID`
  - **Source**: `Secret/carbide-vault-approle-tokens`, key `VAULT_SECRET_ID`
  - **Optional**: true
  - **Purpose**: AppRole secret part
- `VAULT_TOKEN`
  - **Source**: `Secret/carbide-vault-token`, key `token`
  - **Purpose**: Direct Vault token used by the service
- `VAULT_ADDR`
  - **Source**: `ConfigMap/vault-cluster-info`, key `VAULT_SERVICE`
  - **Value example**: `https://vault.forge.svc.cluster.local:8200` (cluster-specific example)
  - **Purpose**: Vault base URL
- `VAULT_MOUNT_LOCATION`
  - **Source**: `ConfigMap/vault-cluster-info`, key `FORGE_VAULT_MOUNT`
  - **Purpose**: Path where NICo secrets are mounted
- `VAULT_KV_MOUNT_LOCATION`
  - **Source**: `ConfigMap/vault-cluster-info`, key `FORGE_VAULT_MOUNT`
  - **Purpose**: Path where NICo secrets are mounted
- `VAULT_PKI_MOUNT_LOCATION`
  - **Source**: `ConfigMap/vault-cluster-info`, key `FORGE_VAULT_PKI_MOUNT`
  - **Purpose**: Path for Vault PKI backend
- `VAULT_PKI_ROLE_NAME`
  - **Value**: `forge-cluster`
  - **Purpose**: PKI role used for certificate issuance

**Database Configuration**

These variables are shared between the deployment and the migration job.

- `DATASTORE_USER`
  - **Source**: `Secret/forge-system.carbide.forge-pg-cluster.credentials`, key `username`
  - **Purpose**: PostgreSQL username
- `DATASTORE_PASSWORD`
  - **Source**: `Secret/forge-system.carbide.forge-pg-cluster.credentials`, key `password`
  - **Purpose**: PostgreSQL password
- `DATASTORE_HOST`
  - **Source**: `ConfigMap/forge-system-carbide-database-config`, key `DB_HOST`
  - **Purpose**: PostgreSQL host (e.g. `forge-pg-cluster.default.svc`)
- `DATASTORE_PORT`
  - **Source**: `ConfigMap/forge-system-carbide-database-config`, key `DB_PORT`
  - **Purpose**: PostgreSQL port (e.g. `5432`)
- `DATASTORE_NAME`
  - **Source**: `ConfigMap/forge-system-carbide-database-config`, key `DB_NAME`
  - **Purpose**: PostgreSQL database name
- `CARBIDE_API_DATABASE_URL`
  - **Value (computed)**: `postgres://$(DATASTORE_USER):$(DATASTORE_PASSWORD)@$(DATASTORE_HOST):$(DATASTORE_PORT)/$(DATASTORE_NAME)`
  - **Purpose**: Final database URL that overrides `database_url` in `carbide-api-config.toml`

**Web/Auth**

- `CARBIDE_WEB_PRIVATE_COOKIEJAR_KEY`
  - **Value (current)**: `$(DATASTORE_PASSWORD)` (i.e. the database password)
  - **Purpose**: Key for encrypting cookie jar data
  - **Note**: In a hardened environment, you may want to use a dedicated secret instead of reusing the database password.

The following enviornment variables are commented out because they are placeholders for SSO integration:

- `CARBIDE_WEB_OAUTH2_CLIENT_SECRET`: This value would come from `Secret/azure-sso-carbide-web-client-secret`, key `client_secret`.
- `CARBIDE_WEB_HOSTNAME`: This value would come from `ConfigMap/carbide-web-api-hostname`, key `hostname`.
- `CARBIDE_WEB_AUTH_TYPE`: This value would be set to `oauth2` for SSO.

**Debugging/Runtime**

- `BITNAMI_DEBUG`:
  - **Value**: "false"
  - **Purpose**: Standard debug toggle for Bitnami images; likely unused but set to false.
- `RUST_BACKTRACE`:
  - **Value**: "full"
  - **Purpose**: Enables full Rust stack traces on panic.
- `RUST_LIB_BACKTRACE`:
  - **Value**: "0"
  - **Purpose**: Controls backtrace behavior for Rust libraries (refer to the Rust documentation for more details).

#### Migration Job (migration.yaml)

This file runs database migrations for the carbide-api database before applying other changes.

- **Kind**: Job
- **Name**: carbide-api-migrate
- **Namespace**: forge-system
- **Pod spec**:
  - **restartPolicy**: OnFailure
  - **Container**:
    - **Name**: carbide-api-migrate
    - **Image**: nvcr.io/nvidian/nvforge/nvmetal-carbide:latest
    - **Command**:
      ```bash
      Namespace: forge-system
      Pod spec:
      restartPolicy: OnFailure
      ```
    - **Environment variables**: The same `DATASTORE_*` variables are used as in the main deployment, with identical sources.

**Configuration impact**

Any changes to DB host, port, name, user, or password must be reflected in the following:
- `Secret/forge-system.carbide.forge-pg-cluster.credentials`
- `ConfigMap/forge-system-carbide-database-config`

#### Services (api-service.yaml)

- **Kind**: Service
- **Name**: carbide-api
- **Namespace**: forge-system
- **Labels**:
  - `app: carbide-api`
- **Spec**:
  - **Ports**:
    - **port**: 1079
    - **name**: grpc
    - **protocol**: TCP

#### Services (metrics-service.yaml)

- **Kind**: Service
- **Name**: carbide-api-metrics
- **Labels**:
  - `app: carbide-api`
  - `app.kubernetes.io/metrics: carbide-api`
- **Spec**:
  - **Ports**:
    - **port**: 1080
    - **name**: http
    - **protocol**: TCP
    - **targetPort**: 1080

#### Services (profiler-service.yaml)

- **Kind**: Service
- **Name**: carbide-api-profiler
- **Labels**:
  - `app: carbide-api`
  - `app.kubernetes.io/metrics: carbide-api`
- **Spec**:
  - **Ports**:
    - **port**: 1081
    - **name**: http
    - **protocol**: TCP
    - **targetPort**: 1081
- **Selector**: Also absent in base; add via overlay as needed.

#### TLS Certificate (certificate.yaml)

Requests a TLS certificate via cert-manager for the carbide-api service; this is used for SPIFFE-aligned identities.

**Spec**

- **Kind**: Certificate
- **Name**: carbide-api-certificate
- **Namespace**: default
- **Spec**:
  - **duration**: 720h0m0s (30 days)
  - **renewBefore**: 360h0m0s (15 days before expiration)
  - **dnsNames**:
    - `carbide-api.default.svc.cluster.local`
  - **uris**:
    - `spiffe://forge.local/default/sa/carbide-api`
    - **Note**: SPIFFE trust domain "forge.local" is currently hard-coded; it should be updated if your environment uses a different domain.
  - **privateKey**:
      - **algorithm**: ECDSA
      - **size**: 384
  - **issuerRef**:
      - **kind**: ClusterIssuer
      - **Name**: `vault-forge-issuer`
      - **Note**: Must have a trusted issuer
      - **group**: cert-manager.io
  - **secretName**: carbide-api-certificate

**Resulting secret**

- **Secret name**: `carbide-api-certificate`
- **Used by**:
  - Deployment volume `spiffe`, mounted at `/var/run/secrets/spiffe.io`.
  - `carbide-api-config.toml` TLS section expects:
    - `/var/run/secrets/spiffe.io/tls.crt`
    - `/var/run/secrets/spiffe.io/tls.key`
    - `/var/run/secrets/spiffe.io/ca.crt`

#### Service Account and RBAC (service-account.yaml)

- **Kind**: ServiceAccount
- **Name**: carbide-api
- **Namespace**: default
- **Used by**:
  - Deployment/carbide-api via `serviceAccountName: carbide-api`

#### Service Account and RBAC (role.yaml)

- **Kind**: Role
- **Name**: carbide-api
- **Namespace**: default
- **Rules**:
  - **apiGroups**: ["cert-manager.io"]
  - **resources**: ["certificaterequests"]
  - **verbs**: ["create"]

This allows the service (via cert-manager flows) to create CertificateRequest resources in the namespace.

#### Service Account and RBAC (rolebinding.yaml)

- **Kind**: RoleBinding
- **Name**: carbide-api
- **Namespace**: default (implicitly)
- **roleRef**:
  - **apiGroup**: `rbac.authorization.k8s.io`
  - **kind**: Role
  - **name**: carbide-api
- **subjects**:
  - **Kind**: ServiceAccount
  - **Name**: carbide-api
  - **Namespace**: default

This binds the local Role to the carbide-api service account.


#### Carbide API Configuration and Dependency Matrix

This section summarizes what you must provide and how it is used.

##### Secrets

- **Secret/carbide-vault-token**
  - **Keys**:
    - **token**: Vault token value
  - **Used by**:  Deployment (env `VAULT_TOKEN`).
  - **Purpose**: uthenticate carbide-api to Vault if not using AppRole.
- **Secret/carbide-vault-approle-tokens** (optional)
  - **Keys**:
    - `VAULT_ROLE_ID`
    - `VAULT_SECRET_ID`
  - **Used by**: Deployment (env `VAULT_ROLE_ID`, `VAULT_SECRET_ID`)
  - **Purpose**: AppRole authentication to Vault
- **Secret/forge-system.carbide.forge-pg-cluster.credentials**
  - **Keys**:
    - `username`
    - `password`
  - **Used by**: Deployment (env `DATASTORE_USER`, `DATASTORE_PASSWORD`)
  - **Purpose**: PostgreSQL credentials for both application and migrations
- **Secret/forge-roots**
  - **Keys**:
    - `ca.crt`
    - `etc.`
  - **Used by**: Deployment volume mount at `/var/run/secrets/forge-roots`
  - **Purpose**: Additional root CA bundle for validating peer certificates
- **Secret/carbide-api-certificate**
  - **Created by**: `Certificate/carbide-api-certificate` (via cert-manager)
  - **Expected keys**:
    - `tls.crt`
    - `tls.key`
    - `ca.crt`
  - **Used by**:
    - Deployment volume `spiffe`
    - TLS paths in `carbide-api-config.toml`

##### ConfigMaps

- **ConfigMap/vault-cluster-info**
  - **Required keys**:
    - `VAULT_SERVICE` -> used as `VAULT_ADDR`
    - `FORGE_VAULT_MOUNT` -> used as `VAULT_MOUNT_LOCATION`, `VAULT_KV_MOUNT_LOCATION`
    - `FORGE_VAULT_PKI_MOUNT` -> used as `VAULT_PKI_MOUNT_LOCATION`
  - **Used by**: Deployment env vars
  - **Purpose**: Central configuration for Vault endpoints and mount paths
- **ConfigMap/forge-system-carbide-database-config**
  - **Required keys**:
    - `DB_HOST` -> used as `DATASTORE_HOST`
    - `DB_PORT` -> used as `DATASTORE_PORT`
    - `DB_NAME` -> used as `DATASTORE_NAME`
  - **Used by**: Deployment and Job/carbide-api-migrate
  - **Purpose**: Central configuration for database endpoint information
- **ConfigMap/carbide-api-config-files**
  - **Generated from**:
    - `config-files/carbide-api-config.toml`
    - `config-files/casbin-policy.csv`
  - **Used by**: Deployment (mounted at `/etc/forge/carbide-api`)
- **ConfigMap/carbide-api-site-config-files**
  - **Generated with files**: `[]` in base; overlays should add site-specific files
  - **Used by**: Deployment (mounted at `/etc/forge/carbide-api/site`)

#### Carbide DHCP

The `deploy/carbide-base/dhcp` path contains Kubernetes manifests for the carbide-dhcp service and all its configuration surfaces: environment variables, secrets, config maps, TLS certificates, RBAC, and a specification for how the components fit together at runtime.

```bash
dhcp/
├── certificate.yaml
├── deployment.yaml
├── kustomization.yaml
├── metrics-service.yaml
├── role.yaml
├── rolebinding.yaml
├── service-account.yaml
└── service.yaml
```

carbide-dhcp is a DHCP service (using Kea DHCPv4) that integrates with Forge via mTLS SPIFFE
certificates. It exposes the following:

- DHCP traffic on **UDP port 67**
- Metrics on **TCP port 1089**

**Primary resources**

- **Workload**: `Deployment/carbide-dhcp`
- **Networking**:
  - `Service/carbide-dhcp` (DHCP UDP 67)
  - `Service/carbide-dhcp-metrics` (HTTP metrics on 1089)
- **Identity / TLS**:
  - `Certificate/carbide-dhcp-certificate` -> `Secret/carbide-dhcp-certificate`
- **Config**:
  - `External ConfigMap/carbide-dhcp-config` (Kea config JSON)
- **RBAC**:
  - `ServiceAccount/carbide-dhcp`
  - `Role/carbide-dhcp`
  - `RoleBinding/carbide-dhcp`
- **Kustomize wiring**: `kustomization.yaml`

**External dependencies you must provide**

- `ConfigMap/carbide-dhcp-config` (Kea DHCP config, including `kea_config.json` key or similar)
- `ClusterIssuer/vault-forge-issuer` (for cert-manager)
- `cert-manager` itself (to reconcile Certificate into Secret)

#### Kustomization Entrypoint (kustomization.yaml)

The `kustomization.yaml` file is the entrypoint that connects all the carbide-dhcp manifests together and applies common labels so everything is consistently addressable.

**Labels**

The following add labels to resources, selectors, and templates:

- `app.kubernetes.io/name: carbide-dhcp`
- `app.kubernetes.io/component: dhcp`

Both `includeSelectors: true` and `includeTemplates: true` are set, so these labels propagate to the following:

- Pod templates
- Service selectors (if present)
- Other labeled fields

**Resources Included**

The following resources are included in the kustomization:

- `certificate.yaml`
- `deployment.yaml`
- `metrics-service.yaml`
- `role.yaml`
- `rolebinding.yaml`
- `service-account.yaml`
- `service.yaml`

**Note**: The `carbide-dhcp-config` config map should be defined elsewhere (e.g. an overlay or another base).
For instance, for SA-Enablement, it is defined under `deploy/kustomization.yaml` in the BMM repo.

#### Deployment (deployment.yaml)

##### Basic Spec

- **Kind**: Deployment
- **Name**: `carbide-dhcp`
- **Namespace**: `forge-system`
- **Spec**:
  - **replicas**: 1
  - **strategy.type**: RollingUpdate
  - **selector.matchLabels**: `app.kubernetes.io/name: carbide-dhcp`

**Container**

- **Name**: `carbide-dhcp`
- **Image**: `nvcr.io/nvidian/nvforge/nvmetal-carbide:latest` (This is typically overridden with a pinned version in an overlay.)
- **ImagePullPolicy**: `IfNotPresent`
- **Command**:
  ```bash
  sh -c 'mkdir -vp /var/run/kea /var/lib/kea && /sbin/kea-dhcp4 -c /tmp/kea_config.json'
  ```
  - The following runtime directories are created for Kea:
    - `/var/run/kea`
    - `/var/lib/kea`
  - Kea DHCPv4 is started:
    - Binary: `/sbin/kea-dhcp4`
    - Config file: `/tmp/kea_config.json` (This file must be provided by the `carbide-dhcp-config` ConfigMap mounted at `/tmp`.)

**Ports**

- **udp**: containerPort: 67
- **metrics**: containerPort: 1089

**Security context**

- `capabilities.add: [ "SYS_PTRACE" ]` (Allows debugging (e.g., gdb/strace) inside the container.)

##### Volume mounts

The following is mounted inside the container:

- **SPIFFE certs**:
  - `name: spiffe`
  - `mountPath: /var/run/secrets/spiffe.io`
  - `readOnly: true`
- **Used by env vars**:
  - `FORGE_ROOT_CAFILE_PATH = /var/run/secrets/spiffe.io/ca.crt`
  - `FORGE_CLIENT_CERT_PATH = /var/run/secrets/spiffe.io/tls.crt`
  - `FORGE_CLIENT_KEY_PATH = /var/run/secrets/spiffe.io/tls.key`
- **Config**:
  - `name: config`
  - `mountPath: /tmp`
- The carbide-dhcp-config ConfigMap is mounted here. It must include the Kea config file as `/tmp/kea_config.json`.

##### Volumes
- **SPIFFE**:
  - **Type**: Secret
  - **secret.secretName**: `carbide-dhcp-certificate`
  - **Contents**: TLS keypair and CA roots created by cert-manager from the Certificate resource
- **Config**:
  - **Type**: ConfigMap
  - **configMap.name**: `carbide-dhcp-config`
  - **defaultMode**: 420 (octal 0644)

##### Environment Variables

- `FORGE_ROOT_CAFILE_PATH`
  - **Value**: `/var/run/secrets/spiffe.io/ca.crt`
  - **Purpose**: Path to CA certificate used to validate Forge/peer TLS endpoints
- `FORGE_CLIENT_CERT_PATH`
  - **Value**: `/var/run/secrets/spiffe.io/tls.crt`
  - **Purpose**: Client certificate used by DHCP component to authenticate as carbide-dhcp to Forge or other services
- `FORGE_CLIENT_KEY_PATH`
  - **Value**: `/var/run/secrets/spiffe.io/tls.key`
  - **Purpose**: Private key corresponding to `FORGE_CLIENT_CERT_PATH`
- `RUST_BACKTRACE`
  - **Value**: `"full"`
  - **Purpose**: Produces full stack traces when Rust code panics inside the image.
- `RUST_LIB_BACKTRACE`
  - **Value**: `"0"`
  - **Purpose**: Controls backtrace behavior for Rust libraries (per Rust standard library docs).

Customize enviornment variables as follows:

- For different cert paths or mounting locations: Adjust the volume mount path and update these env vars accordingly.
- For debugging:
  - Set `RUST_BACKTRACE` to `1` or `full` (already full).
  - Adjust `RUST_LIB_BACKTRACE` to enable library backtraces if needed.

#### Carbide DNS

The Kubernetes manifests for the carbide-dns service and all its configurations are located in the `deploy/carbide-base/dns` directory, which has the following structure:

```
deploy/carbide-base/dns/
  certificate.yaml
  kustomization.yaml
  role.yaml
  rolebinding.yaml
  service-account.yaml
  service.yaml
  statefulset.yaml
```

carbide-dns handles DNS queries from site-controller services and managed hosts and is authoritative
for them. It works in tandem with the Unbound recursive resolver.

-   DNS on **UDP/TCP port 53**

**External dependencies you must provide:**

-   `ConfigMap/carbide-dns` — must include key `CARBIDE_API` with the carbide-api service URL
    (default: `https://carbide-api.forge-system.svc.cluster.local:1079`)

**Environment variables:**

| Variable | Source | Purpose |
| --- | --- | --- |
| `CARBIDE_API` | ConfigMap `carbide-dns` | carbide-api service URL |
| `FORGE_ROOT_CA_PATH` | (inline) `/var/run/secrets/spiffe.io/ca.crt` | CA cert for validating Forge TLS endpoints |

**TLS Certificate:** `Certificate/carbide-dns-certificate` (SPIFFE URI:
`spiffe://forge.local/forge-system/sa/carbide-dns`)

#### Carbide Hardware Health

Path in carbide repo: `deploy/carbide-base/hardware-health`

```
deploy/carbide-base/hardware-health/
  certificate.yaml
  deployment.yaml
  kustomization.yaml
  role.yaml
  rolebinding.yaml
  service-account.yaml
  service.yaml
```

carbide-hardware-health scrapes all host and DPU BMCs for system health information (fan speeds,
temperatures, leak indicators). Measurements are emitted as Prometheus metrics on port **9009** at
`/metrics`. The service also calls the Carbide API to set health alerts.

**TLS Certificate:** `Certificate/carbide-hardware-health-certificate`

#### Nginx

Path in carbide repo: `deploy/carbide-base/nginx`

```
deploy/carbide-base/nginx/
  certificate.yaml
  deployment.yaml
  files/
    nginx.conf
  kustomization.yaml
  service-account.yaml
  service.yaml
```

Nginx serves boot artifacts to managed hosts and DPUs when they network boot using iPXE. It works
in tandem with the carbide-pxe service.

-   HTTP on **TCP port 80**

A `ConfigMap/nginx-config` is generated from `files/nginx.conf`.

**TLS Certificate:** `Certificate/nginx-certificate`

#### Carbide NTP

Path in carbide repo: `deploy/carbide-base/ntp`

```
deploy/carbide-base/ntp/
  kustomization.yaml
  service.yaml
  statefulset.yaml
```

carbide-ntp handles NTP queries from site-controller services and managed hosts. Uses the
`dockurr/chrony` image (pin to a specific tag in your overlay).

-   NTP on **UDP port 123**
-   Pod anti-affinity ensures replicas are spread across Kubernetes nodes

**Environment variables:**

| Variable | Purpose |
| --- | --- |
| `NTP_SERVERS` | List of upstream NTP servers (local or public, must be network-accessible) |
| `NTP_DIRECTIVES` | Additional Chrony configuration directives |

#### Carbide PXE

Path in carbide repo: `deploy/carbide-base/pxe`

```
deploy/carbide-base/pxe/
  certificate.yaml
  deployment.yaml
  kustomization.yaml
  metrics-service.yaml
  role.yaml
  rolebinding.yaml
  service-account.yaml
  service.yaml
```

carbide-pxe provides boot artifacts (iPXE scripts, user-data, OS images) to managed hosts over
HTTP. It determines which OS data to serve for each host by requesting data from Carbide core, and
works in tandem with Nginx.

-   HTTP on **TCP port 8080**

**External dependencies you must provide:**

-   `ConfigMap/carbide-pxe-env-config` — environment variables for the PXE service

**Environment variables:**

| Variable | Purpose |
| --- | --- |
| `ROCKET_CONFIG` | Path to the Rocket configuration file |
| `ROCKET_TEMPLATE_DIR` | Path to Rocket templates |
| `ROCKET_ENV` | Environment type (`production` for production) |
| `FORGE_ROOT_CAFILE_PATH` | `/var/run/secrets/spiffe.io/ca.crt` |
| `FORGE_CLIENT_CERT_PATH` | `/var/run/secrets/spiffe.io/tls.crt` |
| `FORGE_CLIENT_KEY_PATH` | `/var/run/secrets/spiffe.io/tls.key` |

**TLS Certificate:** `Certificate/carbide-pxe-certificate`

#### SSH Console RS

Path in carbide repo: `deploy/carbide-base/ssh-console-rs`

```
deploy/carbide-base/ssh-console-rs/
  certificate.yaml
  config-files/
    config.toml
    otelcol-config.yaml
  deployment.yaml
  kustomization.yaml
  metrics-service.yaml
  role.yaml
  rolebinding.yaml
  secrets/
    ssh_host_key.enc.yaml
  service-account.yaml
  service.yaml
  ssh-host-key-secret-generator.yaml
```

carbide-ssh-console-rs exposes an SSH endpoint that proxies to machine consoles (DPUs),
authenticates using SSH certs, and talks to carbide-api over mTLS using SPIFFE identities. A
sidecar (`loki-log-collector`) ships console logs to Loki via an OTel Collector.

-   SSH on **TCP port 22**
-   Metrics on **TCP port 9009**

**External dependencies:**

-   Loki endpoint reachable (reference:
    `http://loki.loki.svc.cluster.local:3100/loki/api/v1/push`)
-   `Secret/ssh-host-key` with keys `ssh_host_ed25519_key` and `ssh_host_ed25519_key_pub`

**Generating the SSH host key Secret:**

```bash
mkdir -p host_keys/etc/ssh
ssh-keygen -A -f ./host_keys
kubectl -n forge-system create secret generic ssh-host-key \
  --from-file=ssh_host_ed25519_key=./host_keys/etc/ssh/ssh_host_ed25519_key \
  --from-file=ssh_host_ed25519_key_pub=./host_keys/etc/ssh/ssh_host_ed25519_key.pub
```

**Configuration (`config-files/config.toml`):**

| Key | Default | Description |
| --- | --- | --- |
| `listen_address` | `[::]:22` | SSH listen address |
| `metrics_address` | `[::]:9009` | HTTP metrics address |
| `carbide_url` | `https://carbide-api.forge-system.svc.cluster.local:1079` | carbide-api endpoint |
| `forge_root_ca_path` | `/var/run/secrets/spiffe.io/ca.crt` | Root CA cert for carbide-api |
| `client_cert_path` | `/var/run/secrets/spiffe.io/tls.crt` | Client cert for mTLS to carbide-api |
| `client_key_path` | `/var/run/secrets/spiffe.io/tls.key` | Client key |
| `host_key` | `/etc/ssh/ssh_host_ed25519_key` | Path to SSH host private key |
| `insecure` | `false` | Must be `false` in production |
| `openssh_certificate_ca_fingerprints` | _(production CA fingerprints)_ | Allowed CA fingerprints for SSH certs |
| `admin_certificate_role` | _(role string)_ | Role in SSH cert Key ID granting admin-level access |
| `dpus` | `true` | Enables SSH access to DPU consoles |

**OTel sidecar (`config-files/otelcol-config.yaml`)** — key configurable knobs:

-   `exporters.loki.endpoint` — Loki push endpoint
-   `exporters.loki.headers["X-Scope-OrgID"]` — Loki tenant label (default: `forge`)
-   `receivers.filelog.include` — log file patterns (default: `/var/log/consoles/*.log`)
-   Memory limits (`memory_limiter` processor)

**TLS Certificate:** `Certificate/carbide-ssh-console-rs-certificate` (SPIFFE URI:
`spiffe://forge.local/forge-system/sa/carbide-ssh-console-rs`)

### Carbide Unbound (recursive DNS)

Path in carbide repo: `deploy/carbide-unbound-base`

carbide-unbound runs an Unbound recursive DNS resolver inside the cluster. It:

-   Answers DNS for Carbide and other internal workloads
-   Forwards queries to your chosen upstream resolvers
-   Exposes Prometheus metrics via an `unbound_exporter` sidecar (port 9167)

**Reference images** (build or mirror to your registry):

-   `nvcr.io/nvidian/nvforge/unbound:3b089e6`
-   `nvcr.io/nvidian/nvforge/unbound_exporter:7561033`

**Kustomize layout:**

```
carbide-unbound-base/
  local.conf.d/
    access_control.conf
    extended_statistics.conf
    forge_local_unknowndomain.conf
    patchme.conf
    verbosity.conf
  deployment.yaml
  service.yaml
  kustomization.yaml
  unbound.env
```

`kustomization.yaml` generates two ConfigMaps: `unbound-envvars` (from `unbound.env`) and
`unbound-local-config` (from `local.conf.d/`).

**Reference environment behavior:**

-   **Deployment:** `carbide-unbound`; containers: `unbound` (DNS on UDP/53 and TCP/53) +
    `unbound-metrics` (Prometheus exporter on port 9167)
-   **Service:** `carbide-unbound` (ClusterIP); ports UDP/53, TCP/53

**Config knobs you must review:**

**1. DNS access control**

**File:** `local.conf.d/access_control.conf`

The reference allows queries from all sources (`access-control: 0.0.0.0/0 allow`). Tighten to
your cluster/site CIDRs:

```conf
server:
    access-control: <YOUR_CLUSTER_CIDR> allow
    access-control: 0.0.0.0/0 refuse
```

**2. Extended statistics and verbosity**

Leave `extended-statistics: yes` for richer metrics, or set to `no`. Adjust `verbosity` in
`verbosity.conf` per your logging policy.

**3. Upstream forwarders (critical)**

**File:** `local.conf.d/patchme.conf`

The base `patchme.conf` is intentionally broken — it includes a non-existent file. Replace it with
real Unbound configuration for your upstream DNS:

```conf
forward-zone:
    name: "."
    forward-addr: <YOUR_DNS_RESOLVER_1>
    forward-addr: <YOUR_DNS_RESOLVER_2>
```

Or override it via your own Kustomize overlay.

**4. Environment defaults**

**File:** `unbound.env`

-   `LOCAL_CONFIG_DIR` — should match the volume mount path; no change needed normally
-   `BROKEN_DNSSEC=1` — set to `0` if you use correct DNSSEC upstream and want strict validation
-   `UNBOUND_CONTROL_DIR` — where control keys and sockets live; leave as default normally

**Images and registry:**

Update `deployment.yaml` (or an `images:` block in a higher-level `kustomization.yaml`) to use
images from your registry.

**How to apply:**

After setting access controls, upstream forwarders, and image references:

```bash
kubectl apply -k <path-to>/carbide-unbound-base
```

This creates: `unbound-envvars` and `unbound-local-config` ConfigMaps, the `carbide-unbound`
Deployment, and the internal DNS Service.

### FRR Routing

Path in carbide repo: `deploy/frrouting-base`

frrouting runs FRR BGP speakers inside the cluster. It is used when Carbide needs to peer with
ToR/upstream routers over BGP and export/learn routes for management and bare-metal networks.

```{note}
This component is **optional** — skip it if your environment does not require in-cluster BGP.
```

**Kustomize layout:**

```
frrouting-base/
  files/
    daemons          # which FRR daemons run
    extra-init.sh    # entry helper: picks per-pod config
    vtysh.conf       # vtysh CLI config (empty by default)
  kustomization.yaml
  service.yaml
  statefulset.yaml
```

`kustomization.yaml` creates: `ConfigMap/frrouting-config` (mounted at `/etc/frr_pre`) and
`ConfigMap/frrouting-extra-init` (the init script).

**Reference environment behavior:**

-   **StatefulSet:** `frrouting`; replicas: 3; pod anti-affinity spreads replicas across nodes
-   **Containers:**
    -   `frr` (routing daemon): image `nvcr.io/nvidian/nvforge/frr:latest`; runs privileged
        (`privileged: true` required for managing routing tables); BGP on TCP/179
    -   `frr-exporter` (metrics): image `ghcr.io/tynany/frr_exporter`; metrics on TCP/9342
-   **Service:** `frrouting` (headless, TCP/179)
-   **Init logic:** `extra-init.sh` derives the StatefulSet index from the pod hostname; copies
    `frr.conf-<INDEX>` to `/etc/frr/frr.conf` if it exists, then execs FRR's entrypoint. This
    allows per-instance configs.

**Reference images** (build or mirror to your registry):

-   `nvcr.io/nvidian/nvforge/frr:latest`
-   `ghcr.io/tynany/frr_exporter`

**Config knobs you must adjust:**

**1. FRR daemons**

**File:** `files/daemons`

By default only BGP (`bgpd=yes`) is enabled. Enable other daemons (e.g., `ospfd`, `isisd`) only
if explicitly needed.

**2. BGP configuration (critical)**

The base ships **no BGP neighbors or networks**. Provide valid FRR config via your overlay:

-   Shared config for all pods: mount a `frr.conf` file into `/etc/frr_pre`
-   Per-pod configs: create `frr.conf-0`, `frr.conf-1`, `frr.conf-2` in the ConfigMap so
    `extra-init.sh` picks the correct one by StatefulSet index

BGP config must include: local AS number(s), BGP neighbor addresses (ToRs, upstream routers),
address families (IPv4/IPv6), and prefixes to advertise.

**3. Replica count and placement**

`spec.replicas: 3`. Ensure there are at least as many nodes as replicas for anti-affinity to
succeed.

**4. Routing integration and security**

-   The `frr` container runs **privileged**. Review cluster policies around privileged pods.
-   By default BGP runs on pod IPs (not `hostNetwork`). Ensure NetworkPolicies allow TCP/179
    between FRR pods and their peers.

**5. Images and registry**

Update the StatefulSet container `image:` fields (or add an `images:` block in a higher-level
`kustomization.yaml`) to use images from your registry.

**How to apply:**

After preparing BGP configuration files and updating image references:

```bash
kubectl apply -k <path-to>/frrouting-base
```

This creates: `frrouting-config` and `frrouting-extra-init` ConfigMaps, the `frrouting` headless
Service, and the `frrouting` StatefulSet.

### Forge System

Path in carbide repo: `deploy/forge-system`

The `forge-system` directory defines the Forge control-plane namespace and the core wiring for
services that need:

-   A shared system namespace (`forge-system`)
-   Standard config for: carbide-api URL, Carbide database connection, Vault endpoint and mounts
-   Cluster-internal SPIFFE identities for key services
-   **External access** via LoadBalancer services for DHCP, DNS, NTP, PXE, carbide-api, SSH
    console, FRR (BGP), and Nginx

```
forge-system/
  external-services.yaml
  kustomization.yaml
  namespace.yaml
```

**Kustomization:**

-   **namespace: `forge-system`** — all resources are defaulted into this namespace
-   **`generatorOptions.disableNameSuffixHash: true`** — ensures ConfigMap names stay stable
    since they are referenced by fixed names in deployments

**Included resources:**

-   `namespace.yaml` → creates `Namespace/forge-system`
-   `external-services.yaml` → defines all the LoadBalancer services
-   `../carbide-base` → base Carbide component manifests
-   `../frrouting-base` → FRR routing stack
-   `../carbide-unbound-base` → Unbound DNS infrastructure

**ConfigMap generators:**

**`ConfigMap/carbide-dns`:**

| Key | Default | Notes |
| --- | --- | --- |
| `CARBIDE_API` | `https://carbide-api.forge-system.svc.cluster.local:1079` | Update if carbide-api is hosted elsewhere |

**`ConfigMap/forge-system-carbide-database-config`:**

| Key | Default | Notes |
| --- | --- | --- |
| `DB_HOST` | `forge-pg-cluster.postgres.svc.cluster.local` | Update if Postgres is in a different namespace/cluster |
| `DB_PORT` | `5432` | |
| `DB_NAME` | `forge_system_carbide` | Change if you want a different DB name |
| `SECRET_REF` | `forge-system.carbide.forge-pg-cluster.credentials.postgresql.acid.zalan.do` | Update if your Postgres operator uses a different naming pattern |

**`ConfigMap/vault-cluster-info`:**

| Key | Default | Notes |
| --- | --- | --- |
| `VAULT_SERVICE` | `https://vault.vault.svc.cluster.local:8200` | Point to your Vault service DNS/port |
| `FORGE_VAULT_MOUNT` | `secrets` | Change if your KV mount uses a different path |
| `FORGE_VAULT_PKI_MOUNT` | `forgeca` | Change if PKI is mounted under a different path |

**Certificate patches:**

For each Carbide component certificate, the kustomization patches `spec.dnsNames` and `spec.uris`
to match the `forge-system` namespace and `forge.local` SPIFFE trust domain. Certificates patched:
`carbide-dns-certificate`, `carbide-pxe-certificate`, `nginx-certificate`,
`carbide-dhcp-certificate`, `carbide-api-certificate`, `carbide-hardware-health-certificate`,
`carbide-ssh-console-rs-certificate`.

Update these patches if:

-   Your SPIFFE trust domain differs from `forge.local`
-   You deploy these components in a namespace other than `forge-system`
-   You need additional DNS SANs

**External Services (`external-services.yaml`):**

This file defines all northbound LoadBalancer services. Assign IP addresses from your load balancer
pool for each:

| Service | Protocol/Port | Description |
| --- | --- | --- |
| `carbide-dhcp` | UDP/67 | DHCP |
| `carbide-ntp-external-0/1/2` | UDP/123 | NTP (one per StatefulSet pod) |
| `carbide-dns-external-udp-0/1` | UDP/53 | DNS UDP (shared IP via MetalLB `allow-shared-ip`) |
| `carbide-dns-external-tcp-0/1` | TCP/53 | DNS TCP (shared IP via MetalLB `allow-shared-ip`) |
| `carbide-pxe-external` | TCP/8080 | PXE HTTP boot |
| `carbide-pxe-external-80` | TCP/80 → 8080 | PXE HTTP boot (alternate port) |
| `carbide-api-external` | TCP/443 → 1079 | Carbide API (gRPC over TLS) |
| `carbide-ssh-console-rs-external` | TCP/22 | SSH console |
| `frrouting-0/1/2` | TCP/179 | BGP (one per FRR pod) |
| `nginx-external` | TCP/80 | Nginx |

#### How to Customize Carbide

To customize Carbide for your site, edit the following files in the `deploy/` directory:

-   `deploy/kustomization.yaml`
-   `deploy/files/carbide-api/admin_root_cert_pem`
-   `deploy/files/carbide-api/carbide-api-site-config.toml`
-   `deploy/files/unbound/forwarders.conf`
-   `deploy/files/unbound/local_data.conf`
-   `deploy/files/frr.conf-0`
-   `deploy/files/frr.conf-1`
-   `deploy/files/frr.conf-2`
-   `deploy/files/kea_config.json`

**Site and domain names:**

| Variable | Description |
| --- | --- |
| `ENVIRONMENT_NAME` | Site name (e.g., `site1`) |
| `SITE_DOMAIN_NAME` | Site domain name. The admin interface is accessible at `https://api-<ENVIRONMENT_NAME>.<SITE_DOMAIN_NAME>`. |
| `ADMIN_ROOT_CERT_PEM` | CA chain for authenticating forge-admin-cli. Place the cert at `files/carbide-api/admin_root_cert_pem`. |

**Assign IP addresses for services:**

The following variables are IP addresses derived from your Service VIP pool (typically a `/27`
segment):

| Variable | Description |
| --- | --- |
| `CARBIDE_API_EXTERNAL` | IP for the carbide-api service. Add a DNS entry `api-<ENVIRONMENT_NAME>.<SITE_DOMAIN_NAME>` for this address. |
| `CARBIDE_DHCP_EXTERNAL` | IP for the DHCP service |
| `CARBIDE_DNS_INSTANCE_0` / `CARBIDE_DNS_INSTANCE_1` | Two IPs for DNS HA instances (allocate two contiguous addresses) |
| `CARBIDE_NGINX` | IP for the Nginx service |
| `FORGE_UNBOUND_EXTERNAL_IP` | IP for the Unbound service |
| `CARBIDE_NTP_SERVERS_0` / `_1` / `_2` | Three IPs for NTP instances |
| `CARBIDE_PXE` | IP for the PXE service |
| `CARBIDE_SSH_CONSOLE_EXTERNAL` | IP for the SSH console service |
| `ENVOY_EXTERNAL_SERVICE` | IP for the Envoy proxy |
| `FRR_ROUTING_0_EXTERNAL` / `_1` / `_2` | Three IPs for FRR BGP speakers |

**Variables in `carbide-api-site-config.toml`:**

| Variable | Description |
| --- | --- |
| `ADMIN_NETWORK_IP_POOL` | Admin network CIDR (e.g., `10.x.x.x/25`) |
| `ADMIN_NETWORK_GATEWAY_IP` | Gateway IP of the admin network pool |
| `SITE_FABRIC_PREFIX_1` | First tenant overlay network pool. Add `_2`, `_3`, etc. for additional. |
| `CONTROL_PLANE_IPMI_POOL_1` | First IPMI pool for site controller nodes. Add `_2`, `_3`, etc. for additional. |
| `MANAGED_HOST_IPMI_POOL_1` | First IPMI pool for managed hosts. Add `_2`, `_3`, etc. for additional. |
| `MANAGED_HOST_IPMI_NETWORK_1` | Unique network name for the first managed host IPMI pool. Add `_2`, `_3`, etc. for additional. |
| `MANAGED_HOST_IPMI_POOL_1_GATEWAY_IP` | Gateway IP for the first managed host IPMI pool |

**Carbide component image tags:**

| Variable | Component | Description |
| --- | --- | --- |
| `CARBIDE_REGISTRY_PATH` | All components | Registry URL hosting Carbide images (e.g., `<YOUR_REGISTRY>/carbide/`) |
| `CARBIDE_TAG` | `nvmetal-carbide` | Image version tag |
| `BOOT_ARTIFACTS_AARCH64_TAG` | `boot-artifacts-aarch64` | Image version tag |
| `BOOT_ARTIFACTS_X86_TAG` | `boot-artifacts-x86_64` | Image version tag |
| `MACHINE_VALIDATION_TAG` | `machine_validation` | Image version tag |
| `FRR_TAG` | `frr` | Image version tag (e.g., `8.5.0`) |

### Elektra Site Agent (namespace elektra-site-agent)

#### Role and lifecycle

Elektra is the **site-side agent** that:

-   Connects to Temporal (cloud and site workers) and runs "site" workflows
-   Talks to **Carbide** over mTLS gRPC to orchestrate hardware operations
-   Reads/writes to a **site-local PostgreSQL** database for persistent state
-   Uses **cert-manager + Vault** to obtain a SPIFFE-style client cert
-   Is bootstrapped **per site** using an OTP + CA bundle + credentials delivered by the cloud
    side (cloud-site-manager)

**Workload shape:**

-   `StatefulSet/elektra-site-agent` (replicas: 3; serviceAccount: `site-agent`)
-   **Services:** `elektra-headless` (headless), `elektra` (ClusterIP); metrics on port **2112**

#### Prerequisites

**PostgreSQL:**

-   A database reachable from the `elektra-site-agent` namespace with `DB_HOST`, `DB_PORT`,
    `DB_NAME` encoded in `ConfigMap/elektra-database-config`
-   A Secret with keys `username` and `password` (reference:
    `elektra-site-agent.elektra.forge-pg-cluster.credentials`)

**Temporal:**

-   A reachable frontend endpoint (e.g.,
    `temporal-frontend-headless.temporal.svc.cluster.local:7233`)
-   Namespaces `cloud`, `site`, and a **per-site namespace** equal to `<SITE_UUID>` (created
    during the site bootstrap workflow below)

**Carbide core:**

-   A working carbide-api endpoint (e.g.,
    `carbide-api.forge-system.svc.cluster.local:1079`)

**Vault + cert-manager:**

-   A `ClusterIssuer` for site-agent mTLS (e.g., `vault-forge-issuer`)
-   A `CertificateRequestPolicy` that allows the `elektra-site-agent` namespace to request a
    client cert with SPIFFE URI `spiffe://forge.local/elektra-site-agent/sa/<SA_NAME>`

#### Configuration

The base config lives in `base/files/config.properties` and is turned into
`ConfigMap/elektra-config-map`.

**Temporal and TLS:**

| Key | Description |
| --- | --- |
| `temporal_server` | Hostname of the Temporal gateway Elektra connects to |
| `temporal_cert_path` | Filesystem path where the Temporal mTLS Secret is mounted (e.g., `/var/secrets/temporal/certs`) |
| `enable_tls` | Whether Elektra uses mTLS for Temporal (`true`/`false`) |
| `temporal_inventory_schedule` | Cron-style string for periodic inventory workflows (e.g., `@every 3m`) |
| `temporal_subscribe_queue` / `temporal_publish_queue` | Task queues for inbound/outbound workflows (must match cloud-workflow queues) |

**Site identity and Temporal namespace:**

| Key | Description |
| --- | --- |
| `cluster_id` | The **site UUID**. Used as `CLUSTER_ID` env and `TEMPORAL_SUBSCRIBE_NAMESPACE`. Must match the DB rows, Temporal namespace, and Site CR. |
| `temporal_subscribe_namespace` | Must equal `cluster_id` |

**Database (`ConfigMap/elektra-database-config`):**

| Key | Default | Description |
| --- | --- | --- |
| `DB_HOST` | `forge-pg-cluster.postgres.svc.cluster.local` | Postgres host |
| `DB_PORT` | `5432` | Postgres port |
| `DB_NAME` | `elektra` | Database name |
| `SECRET_REF` | `elektra-site-agent.elektra.forge-pg-cluster.credentials.postgresql.acid.zalan.do` | Credentials secret reference |

**Carbide integration:**

| Key | Description |
| --- | --- |
| `carbide_address` | Carbide gRPC endpoint (default: `carbide-api.forge-system.svc.cluster.local:1079`) |
| `carbide_grpc` | Whether Elektra uses gRPC to talk to Carbide |
| `carbide_grpc_skip_auth` | Whether to skip server-side identity checking (set to `false` for production) |

#### Certificates and gRPC client identity

The `grpc-client` overlay defines:

-   **`CertificateRequestPolicy/site-agent-approver-policy`:**
    -   `issuerRef` → ClusterIssuer `vault-forge-issuer`
    -   Scoped to namespace `elektra-site-agent`
    -   Allows DNS SANs: `*.svc`, `*.cluster.local`, `*.svc.cluster.local`
    -   Allows URIs with prefix: `spiffe://forge.local/elektra-site-agent/sa/*`
-   **`Certificate/grpc-client-cert`:**
    -   `secretName: elektra-site-agent-grpc-client-cert`
    -   `dnsNames: elektra.elektra-site-agent.svc.cluster.local`
    -   `uris: spiffe://forge.local/elektra-site-agent/sa/elektra-site-agent`
    -   Mounted at `/etc/carbide` (volume `spiffe`)

If your PKI differs, update `selector.issuerRef.name` in the policy, `spec.issuerRef.name`, and
SAN/URI values in `grpc-client-cert`, and the `secretName` used by the `spiffe` volume.

**Dynamic secrets used by Elektra:**

1.  **Database credentials Secret** — keys `username`, `password`; typically from Vault via ESO.
2.  **`bootstrap-info`** (runtime, not in static manifests) — expected keys: `site-uuid`, `otp`,
    `creds-url`, `cacert`. Mounted at `/etc/sitereg`. Created by `setup-site-bootstrap.sh`
    (see **Site bootstrap workflow** below).
3.  **`temporal-cert`** (runtime) — keys: `otp`, `cacertificate`, `certificate`, `key`. Mounted
    via projected volume `temporal-auth` at `/var/secrets/temporal/certs` (must match
    `temporal_cert_path`). Base manifests include a placeholder; real mTLS material is
    substituted by the bootstrap flow.

#### Site bootstrap workflow

The Elektra repo includes three helper scripts in `elektra-site-agent/deploy/`. Run them **in
order**. All scripts default to the current kube context; set `KUBECTL_CONTEXT=<context>` to
override.

**1) `gen-site-sql.sh` — generate `site.sql` and `SITE_UUID`**

```bash
./gen-site-sql.sh
```

-   Generates a `SITE_UUID` (or uses the `SITE_UUID` env if set)
-   Uses the directory name as site name (or `SITE_NAME` env)
-   Writes `site.sql` with inserts into `infrastructure_provider` and `site` (with `id = SITE_UUID`)

**2) `create-site-in-db.sh` — insert site rows and register Temporal namespace**

```bash
./create-site-in-db.sh
# or ./create-site-in-db.sh /path/to/site.sql
```

-   Extracts `SITE_UUID` from `site.sql`
-   If no site row exists for this `SITE_UUID`, pipes `site.sql` into `psql`
-   Registers a Temporal namespace named `SITE_UUID` using
    `tctl --ns <SITE_UUID> namespace register`

**3) `setup-site-bootstrap.sh` — create site CR and secrets**

```bash
./setup-site-bootstrap.sh
# Optional: SITE_UUID=<existing> ./setup-site-bootstrap.sh
```

What it does:

1.  Creates the Site CR via cloud-site-manager
    (`https://sitemgr.cloud-site-manager:8100/v1/site`)
2.  Fetches the CA cert from credsmgr
3.  Reads the OTP from the Site CR status
4.  Ensures namespace `elektra-site-agent` exists
5.  Creates/updates two secrets in `elektra-site-agent`:
    -   `bootstrap-info` with `site-uuid`, `otp`, `creds-url`, and `cacert`
    -   `temporal-cert` with blank placeholder values (scaffold only)

At this point, DB rows, Temporal namespace, Site CR, OTP, CA, and bootstrap secrets all exist, and
you are ready to wire the UUID into the overlay and deploy Elektra.

#### Overlay configuration and deployment

The overlay imports the base. The only fields you must always adjust per site are in
`overlay/config.properties`:

```properties
cluster_id=<SITE_UUID>
temporal_host=<TEMPORAL_FRONTEND_HOSTNAME>
temporal_port=7233
temporal_publish_namespace=site
temporal_publish_queue=site
temporal_subscribe_namespace=<SITE_UUID>
temporal_subscribe_queue=site
```

Also update the image tag in `overlay/kustomization.yaml`:

```yaml
images:
  - name: nvcr.io/nvidian/nvforge-devel/forge-elektra
    newTag: <TAG>
```

**Deploy Elektra:**

With DB Secret and `elektra-database-config` in place, Temporal endpoint and namespaces ready,
Vault + cert-manager (`vault-forge-issuer`) configured, and `bootstrap-info` and `temporal-cert`
created via `setup-site-bootstrap.sh`:

```bash
kubectl apply -k ./overlay
```

Verify pods:

```bash
kubectl -n elektra-site-agent get pods
```

You should eventually see `elektra-site-agent-0`, `elektra-site-agent-1`, and
`elektra-site-agent-2` all in `Running` state.

At this point, the site agent is fully wired:

-   Uses mTLS and SPIFFE to communicate with Carbide
-   Connects to Temporal with publish namespace/queue `site`/`site` and subscribe namespace
    `<SITE_UUID>`/queue `site`
-   Reads per-site identity and credentials from the DB, Temporal, `bootstrap-info`, and
    `temporal-cert` secrets

## Networking Checklist (Contour/Envoy + LB)

-   **Contour/Envoy** (reference: Contour **1.25.2**, Envoy **1.26.4**):
    -   Create `Ingress`/`HTTPProxy` entries for any external UIs or APIs you expose.
    -   Use **TLS** via your cert-manager Issuer (`secretName: <YOUR_CERT_SECRET>`).
-   **LoadBalancer:**
    -   If on-premises: configure **MetalLB v0.14.5** with your own `IPAddressPool` CIDRs and
        (optionally) BGP peerings.
    -   If on cloud: use the provider LB and map `Service type LoadBalancer` on required ports
        (e.g., cloud-api on `80`/`9360`, carbide-api on `443`).

## Host Ingestion

After Carbide is up and running you can begin ingesting managed hosts. Before you begin, make
sure that:

-   You have the **forge-admin-cli** command available. You can compile it from sources, use a
    pre-compiled binary, or use a containerized version.
-   You can access the carbide site using admin CLI:

    ```bash
    forge-admin-cli -c https://api-<ENVIRONMENT_NAME>.<SITE_DOMAIN_NAME> instance show
    ```

-   DHCP requests from all managed host IPMI networks have been forwarded to the DHCP service at
    `CARBIDE_DHCP_EXTERNAL`.
-   You have the following information for all hosts to be ingested:
    -   MAC address of the host BMC
    -   Chassis serial number
    -   Host BMC username (typically factory default)
    -   Host BMC password (typically factory default)

Upon first login, Carbide requires setting new site-wide defaults to replace factory credentials:

1.  Host BMC credential
2.  DPU BMC credential
3.  Host UEFI password
4.  DPU UEFI password

**Update host UEFI password:**

```bash
forge-admin-cli -c <API_URL> host generate-host-uefi-password
forge-admin-cli -c <API_URL> credential add-uefi --kind=host --password='<PASSWORD>'
```

**Update Host and DPU BMC password:**

```bash
forge-admin-cli -c <API_URL> credential add-bmc --kind=site-wide-root --password='<PASSWORD>'
```

**Approve all machines for ingestion:**

Configure a rule to automatically approve all machines. Failing to do this will cause machines
to raise health alerts:

```bash
forge-admin-cli -c <API_URL> mb site trusted-machine approve \* persist --pcr-registers="0,3,5,6"
```

**Add expected machines table:**

Only servers listed in this table will be ingested. Prepare a JSON file:

```json
{
  "expected_machines": [
    {
      "bmc_mac_address": "<MAC_ADDRESS>",
      "bmc_username": "<BMC_USERNAME>",
      "bmc_password": "<BMC_PASSWORD>",
      "chassis_serial_number": "<SERIAL_NUMBER>"
    }
  ]
}
```

Upload the file:

```bash
forge-admin-cli -c <API_URL> credential em replace-all --filename expected_machines.json
```

