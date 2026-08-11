LUA ?= lua
SWIFT ?= swift
INSTALL ?= install
PRETTIER ?= npx --yes prettier@3.9.6
STYLUA ?= stylua
TAPLO ?= npx --yes @taplo/cli@0.7.0
PRETTIER_MD_SOURCES := README.md
PRETTIER_YAML_SOURCES := ".github/**/*.{yml,yaml}"
PRETTIER_JSON_SOURCES := ".github/**/*.json" .luarc.json
TAPLO_SOURCES := .stylua.toml "examples/**/*.toml" "themes/**/*.toml"
LOCAL_BIN_DIR ?= $(HOME)/.local/bin
GENERATED_SOURCES := \
	Sources/EasyBarKit/Lua/easybar/event_tokens.lua \
	Sources/EasyBarKit/Lua/easybar/theme_tokens.lua \
	Sources/EasyBarKit/Lua/easybar_api.base.lua \
	Sources/EasyBarKit/Lua/easybar_api.events.lua \
	Sources/EasyBarKit/Lua/easybar_api.lua \
	Sources/EasyBarKit/Lua/easybar_api.themes.lua \
	Sources/EasyBarKit/Theme/ThemeColorToken.swift \
	config.defaults.toml \
	config.schema.json

VERSION_PREFIX ?= v
LATEST_TAG := $(shell git tag --list '$(VERSION_PREFIX)*' --sort=-v:refname | head -n 1)
CURRENT_VERSION := $(if $(LATEST_TAG),$(patsubst $(VERSION_PREFIX)%,%,$(LATEST_TAG)),0.0.0)
CURRENT_CORE_VERSION := $(firstword $(subst -, ,$(CURRENT_VERSION)))
BUILD_VERSION ?= $(if $(LATEST_TAG),$(CURRENT_VERSION),dev)

NEXT_PATCH := $(shell python3 -c 'm,n,p=map(int,"$(CURRENT_CORE_VERSION)".split(".")); print(f"{m}.{n}.{p+1}")')
NEXT_MINOR := $(shell python3 -c 'm,n,p=map(int,"$(CURRENT_CORE_VERSION)".split(".")); print(f"{m}.{n+1}.0")')
NEXT_MAJOR := $(shell python3 -c 'm,n,p=map(int,"$(CURRENT_CORE_VERSION)".split(".")); print(f"{m+1}.0.0")')

.DEFAULT_GOAL := help

.PHONY: help build test check check-lua check-concurrency prepare-build-version generate check-generated \
        generate-event-catalog generate-theme-tokens generate-config \
        fmt fmt-swift fmt-lua fmt-md fmt-yaml fmt-json fmt-toml \
        lint lint-swift lint-lua install-local clean

help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z\_0-9-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ Build and test

build: prepare-build-version ## Build EasyBarKit and shared helper products.
	@$(SWIFT) build

check: test check-generated check-concurrency lint ## Run the complete repository verification suite.

test: check-lua prepare-build-version ## Run Swift and Lua tests.
	@$(SWIFT) test --disable-sandbox

check-lua: ## Validate Lua runtime sources and examples.
	@LUA="$(LUA)" scripts/ci/check-lua.sh

check-concurrency: prepare-build-version ## Build every target with complete strict concurrency checking.
	@scripts/ci/check-strict-concurrency.sh

prepare-build-version: ## Stamp direct Kit builds with the current repository version.
	@mkdir -p .build
	@printf '%s\n' "$(BUILD_VERSION)" > .build/easybar-build-version

##@ Generated sources

generate: generate-theme-tokens generate-event-catalog generate-config ## Regenerate checked-in generated artifacts.

generate-theme-tokens: ## Regenerate Swift/Lua theme tokens.
	@python3 scripts/generate/theme_tokens.py

generate-event-catalog: ## Regenerate Lua event catalog files.
	@python3 scripts/generate/event_catalog.py

generate-config: ## Regenerate config references from the shared schema.
	@$(SWIFT) run EasyBarGenerateConfig all

check-generated: generate ## Verify generated artifacts are committed.
	@python3 scripts/generate/check.py check-diff \
		$(foreach source,$(GENERATED_SOURCES),--scope "$(source)")

##@ Formatting

fmt: fmt-swift fmt-lua fmt-md fmt-yaml fmt-json fmt-toml ## Format supported source files.

fmt-swift: ## Format Swift sources.
	@$(SWIFT) format format --in-place --recursive --parallel Sources Tests Plugins

fmt-lua: ## Format Lua sources.
	@$(STYLUA) Sources/EasyBarKit/Lua examples Tests/lua

fmt-md: ## Format Markdown files.
	@$(PRETTIER) --write $(PRETTIER_MD_SOURCES)

fmt-yaml: ## Format YAML files.
	@$(PRETTIER) --write $(PRETTIER_YAML_SOURCES)

fmt-json: ## Format JSON files.
	@$(PRETTIER) --write $(PRETTIER_JSON_SOURCES)

fmt-toml: ## Format TOML files.
	@$(TAPLO) fmt $(TAPLO_SOURCES)

lint: lint-swift lint-lua ## Check formatting without changing files.

lint-swift: ## Check Swift formatting.
	@$(SWIFT) format lint --recursive Sources Tests Plugins

lint-lua: ## Check Lua formatting.
	@$(STYLUA) --check Sources/EasyBarKit/Lua examples Tests/lua

##@ Development

install-local: prepare-build-version ## Install the kit's CLI, Lua runtime, and helper agents into LOCAL_BIN_DIR.
	@$(SWIFT) build -c release
	@$(INSTALL) -d "$(LOCAL_BIN_DIR)"
	@bin_dir="$$($(SWIFT) build -c release --show-bin-path)"; \
		$(INSTALL) -m 755 "$$bin_dir/EasyBarCtl" "$(LOCAL_BIN_DIR)/easybar"; \
		$(INSTALL) -m 755 "$$bin_dir/EasyBarLuaRuntime" "$(LOCAL_BIN_DIR)/EasyBarLuaRuntime"; \
		$(INSTALL) -m 755 "$$bin_dir/EasyBarCalendarAgent" "$(LOCAL_BIN_DIR)/EasyBarCalendarAgent"; \
		$(INSTALL) -m 755 "$$bin_dir/EasyBarNetworkAgent" "$(LOCAL_BIN_DIR)/EasyBarNetworkAgent"

clean: ## Remove SwiftPM build output.
	@$(SWIFT) package clean
	@rm -rf .build

##@ Tagging

tag-patch: ## Create the next patch tag locally.
	@git tag -a "$(VERSION_PREFIX)$(NEXT_PATCH)" -m "Release $(VERSION_PREFIX)$(NEXT_PATCH)"
	@echo "Created tag $(VERSION_PREFIX)$(NEXT_PATCH)"

tag-minor: ## Create the next minor tag locally.
	@git tag -a "$(VERSION_PREFIX)$(NEXT_MINOR)" -m "Release $(VERSION_PREFIX)$(NEXT_MINOR)"
	@echo "Created tag $(VERSION_PREFIX)$(NEXT_MINOR)"

tag-major: ## Create the next major tag locally.
	@git tag -a "$(VERSION_PREFIX)$(NEXT_MAJOR)" -m "Release $(VERSION_PREFIX)$(NEXT_MAJOR)"
	@echo "Created tag $(VERSION_PREFIX)$(NEXT_MAJOR)"

push-tags: ## Push commits and tags to origin.
	@git push --follow-tags

tag: ## Show latest tag.
	@echo "Latest version: $(LATEST_TAG)"
