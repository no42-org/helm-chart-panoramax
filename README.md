# Panoramax Helm Chart

Helm chart for [Panoramax](https://gitlab.com/panoramax/server/api), a geospatial street-level image management platform. This guide covers local deployment using [kind](https://kind.sigs.k8s.io) (Kubernetes in Docker).

## Prerequisites

- Docker running
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- Helm 3
- kubectl

Install kind on macOS:
```bash
brew install kind
```

## Before you deploy

The Keycloak realm configuration is not included in this repo. Copy `keycloak-realm.json` from the [upstream Panoramax repository](https://gitlab.com/panoramax/server/api) into `files/keycloak-realm.json`, replacing the placeholder.

## Create a local cluster

```bash
make cluster-create
```

This creates a Kubernetes cluster as a Docker container and configures your kubeconfig automatically. Verify it's working:

```bash
kubectl get nodes
```

## Deploy the chart

```bash
make install
```

This single command handles the chicken-and-egg problem automatically:
1. Installs the chart with placeholder URLs
2. Waits for the `api` and `auth` LoadBalancer IPs to be assigned
3. Upgrades the chart with the real external URLs

At the end it prints the website URL and default credentials.

Other useful targets:

```
make lint            # helm lint
make dry-run         # render templates without deploying
make status          # show services and their external IPs
make upgrade         # upgrade, reusing existing values
make scale-workers REPLICAS=10
make uninstall
make cluster-delete  # delete the local dev cluster
make help            # full target list
```

Default admin credentials: username `elysee`, password `password`.

## Startup sequence

The chart handles ordering automatically:

1. `migrations` Job (pre-install hook) waits for PostgreSQL then runs `db-upgrade`
2. `api` Deployment waits for PostgreSQL and Keycloak to be ready before starting
3. `background-worker` Deployment waits for PostgreSQL
4. `role-init` Job (post-install hook) creates the `elysee` admin user

Keycloak takes ~60 seconds to start on first run. The API init container will wait for it.

## Scale background workers

```bash
helm upgrade panoramax . --reuse-values --set worker.replicas=10
```

## Enable image blurring

Add the blur API URL to the worker:

```bash
helm upgrade panoramax . --reuse-values \
  --set worker.blurApiUrl=http://<blur-api-host>:5500
```

Then uncomment the `API_BLUR_URL` env var in `templates/worker/deployment.yaml`.

## Tear down

```bash
make uninstall
make cluster-delete
```

## Install from the Helm repo

Once the chart is released via GitHub Actions, you can install directly without cloning:

```bash
helm repo add panoramax https://no42-org.github.io/helm-chart-panoramax
helm repo update
helm install panoramax panoramax/panoramax \
  --set apiExternalUrl=http://<api-ip>:5000 \
  --set authExternalUrl=http://<auth-ip>:8182
```
