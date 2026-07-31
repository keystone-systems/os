.DEFAULT_GOAL := help

.PHONY: help ci fmt check-lockfile test test-checks test-module test-integration test-template test-template-eval
.PHONY: test-tui-eval test-tui-build
.PHONY: vm-create vm-start vm-stop vm-destroy vm-reset vm-ssh vm-console vm-display vm-status vm-post-install vm-reset-secureboot
.PHONY: build-vm-terminal build-vm-desktop build-iso build-iso-ssh
.PHONY: test-e2e test-e2e-build
.PHONY: test-deploy test-desktop test-hm

# Default VM name for libvirt targets
VM_NAME ?= keystone-test-vm

help: ## Show this help message
	@echo "Available targets:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""

ci: ## Run CI checks (format + lockfile verification)
	$(MAKE) fmt
	$(MAKE) check-lockfile

fmt: ## Format Nix files
	nix fmt -- **/*.nix

check-lockfile: ## Verify flake.lock is up to date
	@echo "Checking if flake.lock is up to date..."
	@if ! git diff --quiet flake.lock; then \
		echo "Error: flake.lock has uncommitted changes"; \
		exit 1; \
	fi
	@nix flake check --no-build
	@echo "Lockfile verification passed"

## Test Targets
## Tests are defined in ./tests/flake.nix (separate from main flake)

test: ## Run all tests (checks + module + integration)
	nix flake check
	nix build ./tests#test-server-isolation --no-link
	nix build ./tests#test-desktop-isolation --no-link
	nix build ./tests#test-os-evaluation --no-link
	nix build ./tests#test-iso-evaluation --no-link
	nix build ./tests#test-installer --no-link
	nix build ./tests#test-remote-unlock --no-link

test-checks: ## Run flake checks only (fast validation)
	nix flake check

test-module: ## Run module isolation tests
	nix build ./tests#test-server-isolation --no-link
	nix build ./tests#test-desktop-isolation --no-link
	nix build ./tests#test-os-evaluation --no-link
	nix build ./tests#test-iso-evaluation --no-link

test-integration: ## Run integration tests
	nix build ./tests#test-installer --no-link
	nix build ./tests#test-remote-unlock --no-link

test-template: ## Validate flake template evaluates correctly
	@echo "🧪 Testing flake template..."
	@cd templates/default && nix flake check --no-build --override-input keystone "path:$(CURDIR)"
	@echo "✅ Template validation passed"

test-template-eval: ## Evaluate template configs (TUI output contract)
	nix build .#checks.x86_64-linux.template-evaluation --print-build-logs

## TUI Config Generation Tests
## Rust integration tests that generate configs and validate against local modules

test-tui-eval: ## Evaluate TUI-generated configs against local modules
	cd packages/ks && nix develop ../../ --command cargo test config_evaluates -- --ignored

test-tui-build: ## Build-test TUI-generated configs + ISO (slow, on-demand only)
	cd packages/ks && nix develop ../../ --command cargo test _builds -- --ignored

## ISO Building

build-iso: ## Build installer ISO
	./bin/build-iso

build-iso-ssh: ## Build installer ISO with SSH key
	@if [ -f ~/.ssh/id_ed25519.pub ]; then \
		./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub; \
	elif [ -f ~/.ssh/id_rsa.pub ]; then \
		./bin/build-iso --ssh-key ~/.ssh/id_rsa.pub; \
	else \
		echo "❌ Error: No SSH key found at ~/.ssh/id_ed25519.pub or ~/.ssh/id_rsa.pub"; \
		exit 1; \
	fi

## Fast Config Testing (no encryption/TPM)
## Uses nixos-rebuild build-vm for rapid iteration

build-vm-terminal: ## Build and SSH into terminal dev VM
	./bin/build-vm terminal

build-vm-desktop: ## Build and open desktop VM
	./bin/build-vm desktop

## Libvirt VM Management (TPM + Secure Boot)
## Uses bin/virtual-machine for full-stack testing with encryption

vm-create: ## Create and start libvirt VM with TPM + Secure Boot
	@if [ ! -f vms/keystone-installer.iso ]; then \
		echo "📀 ISO not found, building with SSH key..."; \
		$(MAKE) build-iso-ssh; \
	fi
	./bin/virtual-machine --name $(VM_NAME) --start

vm-start: ## Start existing VM
	@if ! virsh dominfo $(VM_NAME) >/dev/null 2>&1; then \
		echo "❌ VM '$(VM_NAME)' not found. Create with: make vm-create"; \
		exit 1; \
	elif virsh list --state-running | grep -q "$(VM_NAME)"; then \
		echo "ℹ️  VM '$(VM_NAME)' is already running"; \
	else \
		virsh start $(VM_NAME); \
	fi

vm-stop: ## Stop VM gracefully
	@virsh shutdown $(VM_NAME) 2>/dev/null || echo "ℹ️  VM '$(VM_NAME)' not running"

vm-destroy: ## Force stop VM
	@virsh destroy $(VM_NAME) 2>/dev/null || echo "ℹ️  VM '$(VM_NAME)' not running"

vm-reset: ## Delete VM and all artifacts
	./bin/virtual-machine --reset $(VM_NAME)

vm-ssh: ## SSH into test VM
	./bin/test-vm-ssh $(VM_NAME)

vm-console: ## Connect to VM serial console
	@virsh console $(VM_NAME)

vm-display: ## Open graphical display for VM
	@if ! virsh list --state-running | grep -q "$(VM_NAME)"; then \
		echo "⚠️  VM '$(VM_NAME)' is not running"; \
		echo "Start it with: make vm-create"; \
		exit 1; \
	fi
	@command -v remote-viewer >/dev/null 2>&1 || (echo "❌ Error: remote-viewer not found. Install virt-viewer" && exit 1)
	@echo "🖥️  Opening remote-viewer for $(VM_NAME)..."
	@remote-viewer $$(virsh domdisplay $(VM_NAME))

vm-status: ## Show VM status
	@virsh dominfo $(VM_NAME) 2>/dev/null || echo "ℹ️  VM '$(VM_NAME)' not defined"

vm-post-install: ## Post-install: remove ISO, snapshot, reboot
	./bin/virtual-machine --post-install-reboot $(VM_NAME)

vm-reset-secureboot: ## Reset to Secure Boot setup mode
	./bin/virtual-machine --reset-setup-mode $(VM_NAME)

## E2E Testing (ISO build + VM boot + install + validate)

test-e2e: ## Run full e2e test from keystone repo
	./bin/test-e2e

test-e2e-build: ## Build e2e ISO only (no VM boot)
	./bin/test-e2e --build-only

## Deployment Testing

test-deploy: ## Run full stack deployment test
	./bin/test-deployment

test-desktop: ## Test Hyprland desktop environment
	./bin/test-desktop

test-hm: ## Test home-manager modules
	./bin/test-home-manager
