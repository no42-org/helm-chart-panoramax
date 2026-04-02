# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Helm chart for [Panoramax](https://gitlab.com/panoramax/server/api) (internally branded "GeoVisio"), a geospatial street-level image management platform. Targets [kind](https://kind.sigs.k8s.io) (Kubernetes in Docker) for local development but is standard Kubernetes and works on any cluster.

## Chart layout

```
Chart.yaml / values.yaml
files/
  keycloak-realm.json       ← Keycloak realm import; replace placeholder before deploying
templates/
  _helpers.tpl              ← shared labels, dbUrl, apiImage, wait init-container snippets
  db/                       ← PostgreSQL+PostGIS StatefulSet + headless Service
  auth/                     ← Keycloak Deployment + LoadBalancer Service + realm ConfigMap
  api/                      ← Flask API Deployment + LoadBalancer Service
  website/                  ← Vue/Vite frontend Deployment + LoadBalancer Service
  worker/                   ← Background image-processing Deployment (replicas in values)
  pic-data-pvc.yaml         ← Shared PVC between api and worker pods
  migrations-job.yaml       ← Helm pre-install/pre-upgrade hook Job (runs db-upgrade)
  role-init-job.yaml        ← Helm post-install/post-upgrade hook Job (grants admin role)
```

## Installing

Use `make` — it handles the LoadBalancer IP chicken-and-egg automatically:

```bash
make cluster-create # create local kind dev cluster (kind create cluster --name panoramax-dev)
make cluster-delete # delete local kind dev cluster (kind delete cluster --name panoramax-dev)
make install        # install + wait for LB IPs + upgrade with real URLs
make upgrade        # upgrade, reusing existing values
make lint           # helm lint
make dry-run        # render templates without deploying
make status         # show services and external IPs
make scale-workers REPLICAS=10
make uninstall
make help           # full target list
```

Direct helm commands still work if needed:

```bash
helm lint .
helm template panoramax . --set apiExternalUrl=http://<api-ip>:5000
helm upgrade panoramax . --reuse-values --set worker.replicas=10
```

## Required: replace the Keycloak realm

`files/keycloak-realm.json` is a placeholder. Replace it with the real file before deploying:
- Get it from the upstream repo: `https://gitlab.com/panoramax/server/api`
- Or export from a running instance: `GET /admin/realms/geovisio` with an admin bearer token

The realm JSON supports `${GEOVISIO_BASE_URL}` and `${GEOVISIO_CLIENT_SECRET}` substitution — Keycloak injects these from the pod's environment at import time.

## Key values

| Value | Default | Notes |
|---|---|---|
| `imageTag` | `latest` | Applied to both `panoramax/api` and `panoramax/website` |
| `apiExternalUrl` | `http://localhost:5000` | Browser-facing API URL; used by Keycloak redirect URIs and website |
| `auth.clientSecret` | `what_a_secret` | Must match across `auth` and `api` and `keycloak-realm.json` |
| `worker.replicas` | `5` | Number of background image-processing pods |
| `api.pictureStorage` | `20Gi` | Size of the `pic-data` PVC (shared between api and worker) |

## Startup ordering

- `migrations-job` (pre-install hook) waits for `db:5432` then runs `db-upgrade`
- `api` Deployment has init containers waiting for `db:5432` and `auth:8080/realms/geovisio`
- `worker` Deployment has an init container waiting for `db:5432`
- `role-init-job` (post-install hook) retries up to 10 times to handle the migration race

## Git workflow

- **Never push directly to `main`.** All changes go through a pull request.
- Create a branch, open a PR, and merge via GitHub.

### Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

Common types:

| Type | When to use |
|---|---|
| `feat` | New feature or chart capability |
| `fix` | Bug fix |
| `chore` | Maintenance (deps, CI, tooling) |
| `docs` | Documentation only |
| `refactor` | Code change with no behaviour change |
| `ci` | Changes to GitHub Actions workflows |

Examples:

```
feat(worker): add horizontal pod autoscaler support
fix(migrations): resolve db hostname lookup in init container
chore(deps): bump actions/checkout from 4 to 6
ci: exclude templates/ from yamllint
docs: add vind local deployment guide to README
```

Breaking changes: append `!` after the type and add a `BREAKING CHANGE:` footer.

```
feat!: rename apiExternalUrl to api.externalUrl

BREAKING CHANGE: values key renamed; update your values.yaml before upgrading.
```

## Storage note

`pic-data-pvc.yaml` uses `ReadWriteOnce`. This works on kind (single node). For multi-node clusters with multiple worker pods, switch to `ReadWriteMany` and a compatible storage class.
