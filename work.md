# PR Review Context: docs/end-to-end-installation-guide

## What this PR does

This PR improves the deployment documentation for NVIDIA Bare Metal Manager (Carbide)
so external customers can actually deploy it end-to-end without needing internal NVIDIA
access, Slack channels, or video recordings.

## The problem

Customers following the public repos (bare-metal-manager-core and bare-metal-manager-rest)
hit three blockers:

1. **nvcr.io/nvidian references**: `site-setup.md` listed container images from NVIDIA's
   internal registry (nvcr.io/nvidian/nvforge-devel/...) with no instructions on how to
   build them from source. This was filed as GitHub issue #476.

2. **Vault/PostgreSQL gaps in helm/PREREQUISITES.md**: Customers asked (verbatim):
   - "A PKI secrets engine is required for Vault. Is there any specific setting also?"
   - "Do we have to create another one called 'carbide'?"
   - "I don't see Temporal in prerequisites. Do carbide still need it?"
   The answers were discoverable only by cross-referencing site-setup.md, Helm values
   files, and the ClusterIssuer example.

3. **No end-to-end guide**: The 10-step deployment flow (validated by SA teams at TLV01)
   was only documented internally. Externally, customers had to piece together:
   - building_bmm_containers.md (how to build core images)
   - bare-metal-manager-rest README (how to build REST images)
   - site-setup.md (foundation service baselines)
   - helm/PREREQUISITES.md (secrets and configmaps)
   - helm/README.md (Helm chart config)
   - deploy/README.md (Kustomize alternative)
   - ingesting_machines.md (host onboarding)
   with no document explaining the ordering or the gaps between them.

## Files changed (6 files, +685 -29)

### New: book/src/manuals/installation-guide.md

A lean "stitching" document that links to existing docs and fills gaps. Follows the
exact 10-step sequence SA teams used during production deployments:

1. Build and push containers (links to building_bmm_containers.md + REST README)
2. Site controller and Kubernetes (links to site-reference-arch.md)
3. Foundation services (links to site-setup.md + PREREQUISITES.md)
4. Site CA, credsmgr, and Temporal (GAP FILLED: deployment order, vault commands)
5. Deploy Carbide REST components (GAP FILLED: cloud-db, workflow, api, site-manager)
6. Deploy Carbide core (links to helm/README.md, with Kustomize alternative)
7. Install admin-cli (GAP FILLED: build from source, port-forward workaround)
8. Deploy Elektra site agent (GAP FILLED: site registration, Temporal namespace, OTP)
9. Ingest hosts (links to ingesting_machines.md)
10. Verification (GAP FILLED: healthz, admin UI, hello-world test)

Plus a troubleshooting section with real issues from SA deployments.

### Updated: book/src/manuals/building_bmm_containers.md

Added:
- Container image summary table (image name, Dockerfile, purpose, architecture)
- Which images are intermediate (don't push) vs deployable (must push)
- "Tagging and Pushing to a Private Registry" section with docker tag/push commands
- "Building BMM REST Containers" section with make docker-build + push loop
- REST image summary table
- Fixed typo: "perfrom" -> "perform", removed stray backtick in tar command

### Updated: book/src/manuals/site-setup.md

Replaced 5 lines referencing nvcr.io/nvidian/nvforge-devel/... with:
- `<YOUR_REGISTRY>/image-name:<TAG>` placeholder format
- "Build from [repo-name](github-link)" for each component
This directly fixes GitHub issue #476.

### Updated: helm/PREREQUISITES.md

Added under "HashiCorp Vault":
- PKI secrets engine must be at mount path `forgeca` (with vault commands)
- PKI role must be named `forge-cluster` (with vault write command)
- Kubernetes auth must have a role for cert-manager SA (with vault commands)
- Vault policy for PKI signing (with vault policy write command)
- Link to site-setup.md for additional details

Added new section "2a. Temporal":
- Temporal is NOT required for carbide-core (can use admin-cli with gRPC directly)
- Temporal IS required for bare-metal-manager-rest
- Reference versions, frontend endpoint, required namespaces, mTLS note

Updated under "PostgreSQL Database":
- Explicit: "Create a dedicated database named carbide with a dedicated user named
  carbide. Do not use the default postgres superuser."
- Added required extensions (btree_gin, pg_trgm) with psql command
- Link to site-setup.md for additional details

### Updated: book/src/SUMMARY.md

Added "End-to-End Installation Guide" as the first entry under Manuals.

### Updated: README.md

Added installation guide link in Getting Started section. Tweaked existing link
descriptions to be more specific.

## Overlap with PR #479

Larry Chen's PR #479 ("docs: remove private repos") also modifies site-setup.md to
strip nvcr.io/nvidian prefixes. His change is narrower (just removes the prefix,
leaving bare image names). Our change is broader (replaces with YOUR_REGISTRY
placeholders and adds build-from-source links). Whoever merges second resolves the
conflict on that file.

## How to review

1. Start with `book/src/manuals/installation-guide.md` -- does the 10-step flow make
   sense? Does it match what you'd actually do deploying Carbide?

2. Check `helm/PREREQUISITES.md` -- are the Vault commands correct? Is the Temporal
   section accurate (optional for core, required for REST)?

3. Check `book/src/manuals/building_bmm_containers.md` -- is the image summary table
   complete? Are the tag/push commands right?

4. Check `book/src/manuals/site-setup.md` -- are the replacement image names and repo
   links correct?

## Source material

- SA deployment notes for TLV01 (Chelsea Isaac's 10-step guide)
- Carbide Installation Walkthrough BYO K8s (~4000 line internal doc, sections 7.0-7.14)
- Customer questions from SMC/Rafay partner deployments
- GitHub issue #476 (nvcr.io references blocking customers)
- Slack threads from #carbide-sa-enablement and ext-rafay channels
