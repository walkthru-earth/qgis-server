# QGIS Server - Multi-Architecture Build
# Walkthru Earth

QGIS_VERSION ?= master
GDAL_VERSION ?= 3.12.1
DOCKER_TAG ?= latest
IMAGE_NAME ?= walkthruearth/qgis-server

# Detect host architecture
ARCH := $(shell uname -m)
ifeq ($(ARCH),arm64)
    PLATFORM ?= linux/arm64
else ifeq ($(ARCH),aarch64)
    PLATFORM ?= linux/arm64
else
    PLATFORM ?= linux/amd64
endif

# Build arguments
BUILD_ARGS = --build-arg QGIS_VERSION=$(QGIS_VERSION) \
             --build-arg GDAL_VERSION=$(GDAL_VERSION)

.PHONY: help
help: ## Show this help message
	@echo "QGIS Server Docker Build"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
	@echo ""
	@echo "Variables:"
	@echo "  QGIS_VERSION=$(QGIS_VERSION)"
	@echo "  GDAL_VERSION=$(GDAL_VERSION)"
	@echo "  DOCKER_TAG=$(DOCKER_TAG)"
	@echo "  PLATFORM=$(PLATFORM)"

# =============================================================================
# Single Architecture Builds (for local development)
# =============================================================================

.PHONY: build
build: build-server ## Build all images (single arch)

.PHONY: build-server
build-server: ## Build server image (single arch)
	docker build \
		--platform $(PLATFORM) \
		--target server \
		--tag $(IMAGE_NAME):$(DOCKER_TAG) \
		$(BUILD_ARGS) \
		.

.PHONY: build-debug
build-debug: ## Build debug server image (single arch)
	docker build \
		--platform $(PLATFORM) \
		--target server-debug \
		--tag $(IMAGE_NAME):$(DOCKER_TAG)-debug \
		$(BUILD_ARGS) \
		.

# =============================================================================
# Multi-Architecture Builds (requires buildx)
# =============================================================================

.PHONY: buildx-setup
buildx-setup: ## Setup buildx for multi-arch builds
	docker buildx create --name qgis-builder --use --bootstrap || true
	docker buildx inspect --bootstrap

.PHONY: buildx-server
buildx-server: buildx-setup ## Build and push server (multi-arch)
	docker buildx build \
		--platform linux/amd64,linux/arm64 \
		--target server \
		--tag $(IMAGE_NAME):$(DOCKER_TAG) \
		$(BUILD_ARGS) \
		--push \
		.

.PHONY: buildx-debug
buildx-debug: buildx-setup ## Build and push debug server (multi-arch)
	docker buildx build \
		--platform linux/amd64,linux/arm64 \
		--target server-debug \
		--tag $(IMAGE_NAME):$(DOCKER_TAG)-debug \
		$(BUILD_ARGS) \
		--push \
		.

.PHONY: buildx-all
buildx-all: buildx-server buildx-debug ## Build and push all images (multi-arch)

# =============================================================================
# Local Testing
# =============================================================================

.PHONY: run
run: ## Run server locally
	docker run --rm -it \
		-p 8080:8080 \
		-v $(PWD)/tests/data:/etc/qgisserver:ro \
		$(IMAGE_NAME):$(DOCKER_TAG)

.PHONY: run-spawn
run-spawn: ## Run with spawn-fcgi mode
	docker run --rm -it \
		-p 3000:3000 \
		-e SERVER=spawn-fcgi \
		-v $(PWD)/tests/data:/etc/qgisserver:ro \
		$(IMAGE_NAME):$(DOCKER_TAG)

.PHONY: shell
shell: ## Open shell in container
	docker run --rm -it \
		--entrypoint /bin/bash \
		$(IMAGE_NAME):$(DOCKER_TAG)

.PHONY: test
test: ## Run tests with docker-compose
	docker compose -f docker-compose.test.yaml up --build --abort-on-container-exit
	docker compose -f docker-compose.test.yaml down

.PHONY: test-python
test-python: ## Test Python QGIS imports
	docker run --rm $(IMAGE_NAME):$(DOCKER_TAG) \
		python3 -c "from qgis.core import *; from qgis.server import *; print('OK')"

# =============================================================================
# Cleanup
# =============================================================================

.PHONY: clean
clean: ## Clean up Docker resources
	docker compose -f docker-compose.test.yaml down -v 2>/dev/null || true
	docker buildx rm qgis-builder 2>/dev/null || true

.PHONY: prune
prune: ## Prune all Docker build cache
	docker builder prune -af
