.DEFAULT_GOAL := help

RELEASE_NAME  := panoramax
API_PORT      := 5000
AUTH_PORT     := 8182
WEBSITE_PORT  := 3000

DEV_CLUSTER := panoramax-dev

HELM_DEPS := helm
DEPS      := helm kubectl vcluster

define check_bins
@for dep in $(1); do \
	if ! command -v "$$dep" >/dev/null 2>&1; then \
		echo "Error: $$dep is not installed or not in PATH"; \
		exit 1; \
	fi; \
done
endef

.PHONY: check-helm
check-helm:
	$(call check_bins,$(HELM_DEPS))

.PHONY: check-deps
check-deps:
	$(call check_bins,$(DEPS))

.PHONY: confirm
confirm: check-deps
	@bash -c ' \
		if [ ! -t 0 ] && [ ! -t 2 ]; then \
			echo "Error: stdin is not a TTY — cannot confirm in non-interactive mode"; \
			exit 1; \
		fi; \
		echo ""; \
		echo "  Kubernetes context : $$(kubectl config current-context 2>/dev/null || echo "<error>")"; \
		echo "  Cluster            : $$(kubectl config view --minify -o jsonpath="{.clusters[0].name}" 2>/dev/null || echo "<error>")"; \
		echo "  Namespace          : $$(kubectl config view --minify -o jsonpath="{.contexts[0].context.namespace}" 2>/dev/null || echo "default")"; \
		echo ""; \
		read -r -p "  Deploy to this cluster? Type YES to continue: " answer; \
		[ "$$answer" = "YES" ] || { echo "Aborted."; exit 1; } \
	'

##@ Local Cluster

.PHONY: cluster-create
cluster-create: check-deps ## Create a local vind dev cluster (vcluster create panoramax-dev)
	vcluster create $(DEV_CLUSTER)

.PHONY: cluster-delete
cluster-delete: ## Delete the local vind dev cluster (vcluster delete panoramax-dev)
	@bash -c ' \
		if [ ! -t 0 ] && [ ! -t 2 ]; then \
			echo "Error: stdin is not a TTY — cannot confirm in non-interactive mode"; \
			exit 1; \
		fi; \
		read -r -p "  Delete cluster $(DEV_CLUSTER)? Type YES to continue: " answer; \
		[ "$$answer" = "YES" ] || { echo "Aborted."; exit 1; } \
	'
	vcluster delete $(DEV_CLUSTER)

##@ Deployment

.PHONY: install
install: confirm ## Install the chart and auto-configure external URLs once LB IPs are ready
	@echo "Installing $(RELEASE_NAME)..."
	helm install $(RELEASE_NAME) . || { echo "Error: helm install failed"; exit 1; }
	@bash -c ' \
		wait_for_ip() { \
			svc=$$1; i=0; \
			while [ $$i -lt 60 ]; do \
				IP=$$(kubectl get svc $$svc -o jsonpath="{.status.loadBalancer.ingress[0].ip}" 2>/dev/null); \
				[ -n "$$IP" ] && echo "$$IP" && return 0; \
				i=$$((i+1)); sleep 2; \
			done; \
			return 1; \
		}; \
		echo "Waiting for LoadBalancer IPs (timeout: 120s)..."; \
		API_IP=$$(wait_for_ip $(RELEASE_NAME)-api)  || { echo "Error: timed out waiting for API LoadBalancer IP";  helm uninstall $(RELEASE_NAME); exit 1; }; \
		AUTH_IP=$$(wait_for_ip $(RELEASE_NAME)-auth) || { echo "Error: timed out waiting for Auth LoadBalancer IP"; helm uninstall $(RELEASE_NAME); exit 1; }; \
		echo "  API IP  : $$API_IP"; \
		echo "  Auth IP : $$AUTH_IP"; \
		echo "Upgrading with real external URLs..."; \
		helm upgrade $(RELEASE_NAME) . --reuse-values \
			--set apiExternalUrl=http://$$API_IP:$(API_PORT) \
			--set authExternalUrl=http://$$AUTH_IP:$(AUTH_PORT) \
		|| { echo "Error: helm upgrade failed"; helm uninstall $(RELEASE_NAME); exit 1; }; \
		WEBSITE_IP=$$(kubectl get svc $(RELEASE_NAME)-website -o jsonpath="{.status.loadBalancer.ingress[0].ip}" 2>/dev/null); \
		echo ""; \
		if [ -n "$$WEBSITE_IP" ]; then \
			echo "Done. Website: http://$$WEBSITE_IP:$(WEBSITE_PORT)"; \
		else \
			echo "Done. Website IP pending — run: make status"; \
		fi \
	'

.PHONY: upgrade
upgrade: confirm ## Upgrade the chart (reuse existing values)
	helm upgrade $(RELEASE_NAME) . --reuse-values

.PHONY: uninstall
uninstall: confirm ## Uninstall the chart
	helm uninstall $(RELEASE_NAME)

##@ Development

.PHONY: lint
lint: check-helm ## Run helm lint
	helm lint .

.PHONY: dry-run
dry-run: check-helm ## Render templates without deploying
	helm template $(RELEASE_NAME) . \
		--set apiExternalUrl=http://example.com:$(API_PORT) \
		--set authExternalUrl=http://example.com:$(AUTH_PORT)

.PHONY: status
status: check-deps ## Show running services and their external IPs
	kubectl get svc -l "app.kubernetes.io/instance=$(RELEASE_NAME)"

.PHONY: scale-workers
scale-workers: confirm ## Scale background workers (usage: make scale-workers REPLICAS=10)
	@[ -n "$(REPLICAS)" ] || { echo "Error: REPLICAS not set — usage: make scale-workers REPLICAS=10"; exit 1; }
	helm upgrade $(RELEASE_NAME) . --reuse-values --set worker.replicas=$(REPLICAS)

##@ Help

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
