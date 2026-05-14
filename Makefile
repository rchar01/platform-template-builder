SHELL := /bin/sh
.DEFAULT_GOAL := help

TEMPLATE ?= rocky-9
CONFIG_ROOT ?= configs
CONFIG ?= $(CONFIG_ROOT)/$(TEMPLATE)-cloud-base.env
SSH_CONFIG ?= $(CONFIG_ROOT)/ssh/template-builder.env
PLATFORM_SSH_INIT ?= platform-ssh-init

.PHONY: help verify syntax shellcheck init-ssh check-tools \
	validate build cleanup \
	check-config check-ssh-config

## Show available commands
help:
	@printf '%s\n' 'Available targets:'
	@awk '\
		/^## / { help = substr($$0, 4); next } \
		/^[a-zA-Z0-9_.-]+:/ { \
			if (help != "") { \
				target = $$1; \
				sub(/:.*/, "", target); \
				printf "  %-24s %s\n", target, help; \
				help = ""; \
			} \
		} \
	' $(MAKEFILE_LIST) | sort

## Run local syntax checks
syntax:
	bash -n scripts/*.sh

## Run ShellCheck on scripts
shellcheck:
	@command -v shellcheck >/dev/null 2>&1 || { printf '%s\n' 'shellcheck not found; install ShellCheck or skip this target' >&2; exit 1; }
	shellcheck scripts/*.sh

## Run local verification checks
verify: syntax

## Initialize local SSH key/config for Proxmox template builds
init-ssh: check-ssh-config
	PLATFORM_SSH_INIT="$(PLATFORM_SSH_INIT)" ./scripts/init-proxmox-ssh.sh "$(SSH_CONFIG)" \
		$(if $(SSH_EMPTY_PASSPHRASE),--empty-passphrase) \
		$(if $(SSH_WRITE_CONFIG),--write-config) \
		$(if $(SSH_TEST),--test) \
		$(if $(SSH_PRINT_PUBLIC_KEY),--print-public-key)

## Check required local tools, and remote tools if config exists
check-tools:
	@if [ -f "$(CONFIG)" ]; then \
		./scripts/check-tools.sh "$(CONFIG)"; \
	else \
		./scripts/check-tools.sh || exit $$?; \
		printf '%s\n' "[WARN] Skipped remote tool checks because $(CONFIG) does not exist"; \
		printf '%s\n' "[WARN] Create it from configs/$(TEMPLATE)-cloud-base.env.example, or set CONFIG/CONFIG_ROOT to a private config path"; \
	fi

## Validate template config, e.g. TEMPLATE=rocky-9
validate: check-config
	./scripts/validate-config.sh $(CONFIG)

## Build template remotely, e.g. TEMPLATE=rocky-9
build: check-config
	./scripts/remote-run-template-build.sh $(CONFIG)

## Cleanup template remotely, e.g. TEMPLATE=rocky-9
cleanup: check-config
	./scripts/cleanup-template-vm.sh $(CONFIG)

check-config:
	@test -f "$(CONFIG)" || { printf '%s\n' "Missing $(CONFIG). Create it from configs/$(TEMPLATE)-cloud-base.env.example, or set CONFIG/CONFIG_ROOT to a private config path" >&2; exit 1; }

check-ssh-config:
	@test -f "$(SSH_CONFIG)" || { printf '%s\n' "Missing $(SSH_CONFIG). Create it from configs/ssh/template-builder.env.example, or set SSH_CONFIG/CONFIG_ROOT to a private config path" >&2; exit 1; }
