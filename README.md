# Panoramax Helm Chart

Helm chart for [Panoramax](https://gitlab.com/panoramax/server/api), a geospatial street-level image management platform. This guide covers local deployment using [vind](https://github.com/loft-sh/vind) (vCluster in Docker).

## Prerequisites

- Docker running
- [vCluster CLI](https://www.vcluster.com/docs/get-started) v0.31.0 or later
- Helm 3
- kubectl

Install the vCluster CLI on macOS:
```bash
brew install loft-sh/tap/vcluster
```

Switch the CLI to use the Docker driver (this is what makes it vind):
```bash
vcluster use driver docker
```

## Before you deploy

The Keycloak realm configuration is not included in this repo. Copy `keycloak-realm.json` from the [upstream Panoramax repository](https://gitlab.com/panoramax/server/api) into `files/keycloak-realm.json`, replacing the placeholder.

## Create a local cluster

```bash
vcluster create panoramax-dev
```

This creates a virtual Kubernetes cluster as a Docker container and configures your kubeconfig automatically. Verify it's working:

```bash
kubectl get nodes
```

## Deploy the chart

Install with placeholder URLs first — you'll need real LoadBalancer IPs, which aren't assigned until after install:

```bash
helm install panoramax . \
  --set apiExternalUrl=http://placeholder \
  --set authExternalUrl=http://placeholder
```

Once the `api` and `auth` services have their LoadBalancer IPs assigned, grab them:

```bash
kubectl get svc api auth website
```

```
NAME      TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)
api       LoadBalancer   10.96.12.34    172.23.255.200   5000:xxxxx/TCP
auth      LoadBalancer   10.96.12.35    172.23.255.201   8182:xxxxx/TCP
website   LoadBalancer   10.96.12.36    172.23.255.202   3000:xxxxx/TCP
```

Update the chart with the real IPs. The `apiExternalUrl` must be reachable by both the browser and Keycloak's redirect URI validation:

```bash
helm upgrade panoramax . \
  --reuse-values \
  --set apiExternalUrl=http://172.23.255.200:5000 \
  --set authExternalUrl=http://172.23.255.201:8182
```

The website is now reachable at `http://172.23.255.202:3000`.

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

## Pause and resume the cluster

vind clusters can be paused to free resources without losing state:

```bash
vcluster pause panoramax-dev
vcluster resume panoramax-dev
```

## Tear down

```bash
helm uninstall panoramax
vcluster delete panoramax-dev
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
