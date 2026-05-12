SHELL := /bin/sh
.DEFAULT_GOAL := help

TEMPLATE ?= rocky-9
CONFIG ?= configs/$(TEMPLATE)-cloud-base.env

.PHONY: help verify syntax shellcheck check-tools \
	validate build cleanup \
	check-config

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

## Check required local tools, and remote tools if config exists
check-tools:
	@if [ -f "$(CONFIG)" ]; then \
		./scripts/check-tools.sh "$(CONFIG)"; \
	else \
		./scripts/check-tools.sh || exit $$?; \
		printf '%s\n' "[WARN] Skipped remote tool checks because $(CONFIG) does not exist"; \
		printf '%s\n' "[WARN] Create it with: cp configs/$(TEMPLATE)-cloud-base.env.example $(CONFIG)"; \
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
	@test -f "$(CONFIG)" || { printf '%s\n' "Missing $(CONFIG). Run: cp configs/$(TEMPLATE)-cloud-base.env.example $(CONFIG)" >&2; exit 1; }
