APP_NAME := EasyBar
APP_TARGET := EasyBarApp
APP_EXEC := EasyBar
APP_PRODUCT := EasyBar
LUA_RUNTIME_PRODUCT := EasyBarLuaRuntime
LUA_RUNTIME_EXEC := EasyBarLuaRuntime
CALENDAR_AGENT_NAME := EasyBarCalendarAgent
CALENDAR_AGENT_PRODUCT := EasyBarCalendarAgent
CALENDAR_AGENT_EXEC := EasyBarCalendarAgent
NETWORK_AGENT_NAME := EasyBarNetworkAgent
NETWORK_AGENT_PRODUCT := EasyBarNetworkAgent
NETWORK_AGENT_EXEC := EasyBarNetworkAgent
CLI_PRODUCT := EasyBarCtl
CLI_EXEC := easybar
RESOURCE_BUNDLE_NAME := $(APP_NAME)_$(APP_TARGET).bundle
APP_RESOURCE_DIR_NAME := $(APP_NAME)

DIST_DIR := dist
THEMES_DIR := themes
APP_BUNDLE := $(DIST_DIR)/$(APP_NAME).app
APP_CONTENTS := $(APP_BUNDLE)/Contents
APP_MACOS := $(APP_CONTENTS)/MacOS
APP_RESOURCES := $(APP_CONTENTS)/Resources
APP_RESOURCE_DIR := $(APP_RESOURCES)/$(APP_RESOURCE_DIR_NAME)
APP_THEMES_DIR := $(APP_RESOURCES)/Themes
APP_BIN := $(APP_MACOS)/$(APP_EXEC)
LUA_RUNTIME_BIN := $(APP_MACOS)/$(LUA_RUNTIME_EXEC)

APP_ICON_SVG := packaging/easybar-icon.svg
APP_ICON_FILE := $(APP_NAME)
APP_ICON_ICNS := $(APP_RESOURCES)/$(APP_ICON_FILE).icns

CALENDAR_AGENT_BUNDLE := $(DIST_DIR)/$(CALENDAR_AGENT_NAME).app
CALENDAR_AGENT_CONTENTS := $(CALENDAR_AGENT_BUNDLE)/Contents
CALENDAR_AGENT_MACOS := $(CALENDAR_AGENT_CONTENTS)/MacOS
CALENDAR_AGENT_RESOURCES := $(CALENDAR_AGENT_CONTENTS)/Resources
CALENDAR_AGENT_BIN := $(CALENDAR_AGENT_MACOS)/$(CALENDAR_AGENT_EXEC)
CALENDAR_AGENT_PLIST_TEMPLATE := Sources/EasyBarCalendarAgent/Info.plist
CALENDAR_AGENT_PLIST := $(CALENDAR_AGENT_CONTENTS)/Info.plist
CALENDAR_AGENT_ICON_SVG := packaging/easybar-calendar-agent-icon.svg
CALENDAR_AGENT_ICON_FILE := $(CALENDAR_AGENT_NAME)
CALENDAR_AGENT_ICON_ICNS := $(CALENDAR_AGENT_RESOURCES)/$(CALENDAR_AGENT_ICON_FILE).icns

NETWORK_AGENT_BUNDLE := $(DIST_DIR)/$(NETWORK_AGENT_NAME).app
NETWORK_AGENT_CONTENTS := $(NETWORK_AGENT_BUNDLE)/Contents
NETWORK_AGENT_MACOS := $(NETWORK_AGENT_CONTENTS)/MacOS
NETWORK_AGENT_RESOURCES := $(NETWORK_AGENT_CONTENTS)/Resources
NETWORK_AGENT_BIN := $(NETWORK_AGENT_MACOS)/$(NETWORK_AGENT_EXEC)
NETWORK_AGENT_PLIST_TEMPLATE := Sources/EasyBarNetworkAgent/Info.plist
NETWORK_AGENT_PLIST := $(NETWORK_AGENT_CONTENTS)/Info.plist
NETWORK_AGENT_ICON_SVG := packaging/easybar-network-agent-icon.svg
NETWORK_AGENT_ICON_FILE := $(NETWORK_AGENT_NAME)
NETWORK_AGENT_ICON_ICNS := $(NETWORK_AGENT_RESOURCES)/$(NETWORK_AGENT_ICON_FILE).icns

CLI_BIN := $(DIST_DIR)/$(CLI_EXEC)
PLIST_TEMPLATE := Sources/EasyBarApp/Info.plist
PLIST := $(APP_CONTENTS)/Info.plist

PACKAGE_NAME = $(APP_NAME)-$(VERSION).zip
PACKAGE_ZIP = $(DIST_DIR)/$(PACKAGE_NAME)
CALENDAR_AGENT_PACKAGE_ZIP = $(DIST_DIR)/$(CALENDAR_AGENT_NAME)-$(VERSION).zip
NETWORK_AGENT_PACKAGE_ZIP = $(DIST_DIR)/$(NETWORK_AGENT_NAME)-$(VERSION).zip
PACKAGE_STAGE := $(DIST_DIR)/package

BUNDLE_ID ?= com.gi8lino.EasyBar
VERSION ?= dev
ARCH ?= universal
RUN_ARCH ?= arm64
CODESIGN_IDENTITY ?= -
NOTARYTOOL_PROFILE ?=
NOTARY_SUBMIT ?= 0
CLEAN_BUILD ?= 0
NOTARY_ZIP := $(DIST_DIR)/$(APP_NAME)-notarize.zip

VERSION_PREFIX ?= v
LATEST_TAG := $(shell git tag --list '$(VERSION_PREFIX)*' --sort=-v:refname | head -n 1)
CURRENT_VERSION := $(if $(LATEST_TAG),$(patsubst $(VERSION_PREFIX)%,%,$(LATEST_TAG)),0.0.0)
CURRENT_CORE_VERSION := $(firstword $(subst -, ,$(CURRENT_VERSION)))

NEXT_PATCH := $(shell python3 -c 'm,n,p=map(int,"$(CURRENT_CORE_VERSION)".split(".")); print(f"{m}.{n}.{p+1}")')
NEXT_MINOR := $(shell python3 -c 'm,n,p=map(int,"$(CURRENT_CORE_VERSION)".split(".")); print(f"{m}.{n+1}.0")')
NEXT_MAJOR := $(shell python3 -c 'm,n,p=map(int,"$(CURRENT_CORE_VERSION)".split(".")); print(f"{m+1}.0.0")')

SWIFT_BUILD_RELEASE := swift build -c release
SWIFT_BUILD_DEBUG := swift build -c debug
LOCAL_HOME := $(CURDIR)/.home
LOCAL_CACHE_DIR := $(CURDIR)/.cache
LOCAL_CLANG_MODULE_CACHE := $(CURDIR)/.build/clang-module-cache
LOCAL_SWIFT_ENV := HOME="$(LOCAL_HOME)" XDG_CACHE_HOME="$(LOCAL_CACHE_DIR)" CLANG_MODULE_CACHE_PATH="$(LOCAL_CLANG_MODULE_CACHE)"
LOCAL_INSTALL_ARCH ?= $(RUN_ARCH)
LOCAL_APP_DIR ?= $(HOME)/Applications
LOCAL_BIN_DIR ?= $(HOME)/.local/bin
LOCAL_AGENT_DIR ?= $(HOME)/Library/Application Support/EasyBar/Agents
LOCAL_LAUNCH_AGENT_DIR ?= $(HOME)/Library/LaunchAgents
LOCAL_LOG_DIR ?= $(HOME)/Library/Logs/EasyBar
LOCAL_STATE_DIR ?= $(HOME)/Library/Application Support/EasyBar/LocalInstall
WIDGETS_INSTALL_DIR ?= $(HOME)/.config/easybar/widgets
WIDGETS_INSTALL_MANIFEST ?= $(CURDIR)/examples/install-manifest.csv
PRETTIER ?= npx --yes prettier@3.9.6
STYLUA ?= stylua
LUA ?= lua

ifeq ($(ARCH),universal)
ARCHES := arm64 x86_64
else ifeq ($(ARCH),arm64)
ARCHES := arm64
else ifeq ($(ARCH),x86_64)
ARCHES := x86_64
else
$(error Unsupported ARCH '$(ARCH)'. Use arm64, x86_64, or universal)
endif

ifeq ($(RUN_ARCH),universal)
RUN_ARCHES := arm64 x86_64
else ifeq ($(RUN_ARCH),arm64)
RUN_ARCHES := arm64
else ifeq ($(RUN_ARCH),x86_64)
RUN_ARCHES := x86_64
else
$(error Unsupported RUN_ARCH '$(RUN_ARCH)'. Use arm64, x86_64, or universal)
endif

.DEFAULT_GOAL := help

.PHONY: help all \
        generate check-generated generate-event-catalog generate-theme-tokens generate-config generate-default-config generate-swift-env \
        build bundle package release app cli validate-config \
        fmt fmt-swift fmt-lua fmt-markdown \
        lint lint-swift lint-lua check-lua test test-hardening \
        clean clean-dist run run-debug run-trace install-local install-widgets uninstall-local stop restart-app icons \
        build-app build-lua-runtime build-calendar-agent build-network-agent build-cli \
        copy-resources copy-debug-resources prepare-debug-app-bundle verify verify-release \
        sign notarize \
        print-arch print-run-arch print-version print-local-version print-latest-tag print-package-sha256 \
        tag-patch tag-minor tag-major push-tags tag \
        run-build-app run-build-lua-runtime run-build-calendar-agent run-build-network-agent run-build-cli \
        demo

help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Generated

generate: generate-theme-tokens generate-event-catalog generate-config ## Generate all checked-in generated artifacts.

check-generated: generate ## Verify all checked-in generated artifacts are committed.
	@python3 scripts/generate/check.py check-diff

generate-theme-tokens: ## Regenerate shared theme token artifacts for Swift and Lua.
	@python3 scripts/generate/theme_tokens.py

generate-event-catalog: ## Regenerate Lua event catalog files from the shared manifest.
	@python3 scripts/generate/event_catalog.py

generate-config: ## Regenerate the default config from the app config schema.
	@swift run EasyBarGenerateConfig all

generate-default-config: ## Regenerate the visible default config reference from the app config schema.
	@swift run EasyBarGenerateConfig defaults

##@ Build

all: build ## Build the default artifacts.

generate-swift-env: ## Create repo-local directories for SwiftPM and compiler caches.
	@mkdir -p "$(LOCAL_HOME)/Library/org.swift.swiftpm/configuration" \
		"$(LOCAL_HOME)/Library/org.swift.swiftpm/security" \
		"$(LOCAL_HOME)/Library/Caches/org.swift.swiftpm" \
		"$(LOCAL_CACHE_DIR)" \
		"$(LOCAL_CLANG_MODULE_CACHE)"

build: bundle ## Build the app bundle and CLI for the selected ARCH.

app: ## Build only the app executable for the selected ARCH.
	@$(MAKE) --no-print-directory build-app ARCH=$(ARCH) VERSION=$(VERSION)

cli: ## Build only the CLI executable for the selected ARCH.
	@$(MAKE) --no-print-directory build-cli ARCH=$(ARCH) VERSION=$(VERSION)

validate-config: cli ## Validate a config file with CONFIG=/path/to/config.toml.
	@if [ -z "$(CONFIG)" ]; then \
		echo "Usage: make validate-config CONFIG=/path/to/config.toml"; \
		exit 2; \
	fi
	@"$(CLI_BIN)" config validate --config "$(CONFIG)"

##@ Formatting

fmt: fmt-swift fmt-lua fmt-markdown ## Format Swift, Lua, and Markdown files.

fmt-swift: ## Format all Swift source files in the repository.
	@swift format format --in-place --recursive --parallel .

fmt-lua: ## Format all Lua source files in the repository.
	@$(STYLUA) .

fmt-markdown: ## Format Markdown files with Prettier.
	@$(PRETTIER) --write "**/*.md"

lint: lint-swift lint-lua ## Check Swift and Lua formatting without modifying files.

lint-swift: ## Check Swift source formatting without modifying files.
	@swift format lint --recursive .

lint-lua: ## Check Lua formatting, syntax, and example widget startup.
	@$(STYLUA) --check .
	@$(MAKE) --no-print-directory check-lua

check-lua: ## Validate Lua sources, runtime behavior, and example widgets.
	@LUA="$(LUA)" scripts/ci/check-lua.sh

test: generate-swift-env check-lua ## Run the Swift and Lua test suites without regenerating checked-in artifacts.
	@env $(LOCAL_SWIFT_ENV) swift test --disable-sandbox

test-hardening: generate-swift-env ## Run the focused hardening regression suite.
	@env $(LOCAL_SWIFT_ENV) swift test --disable-sandbox --filter HardeningTests

bundle: ## Build the app, agent bundles, and CLI into dist/.
	@scripts/build/bundle.sh \
		--arch "$(ARCH)" \
		--version "$(VERSION)" \
		--bundle-id "$(BUNDLE_ID)" \
		--codesign-identity "$(CODESIGN_IDENTITY)" \
		--notarytool-profile "$(NOTARYTOOL_PROFILE)" \
		--notary-submit "$(NOTARY_SUBMIT)" \
		--clean-build "$(CLEAN_BUILD)" \
		--dist-dir "$(DIST_DIR)"

package: bundle ## Create separate release ZIPs for the cask and agent formulae.
	@scripts/release/package.sh --version "$(VERSION)" --dist-dir "$(DIST_DIR)"

release: verify-release ## Build and verify the zipped release artifacts.
	@echo "Release artifacts ready: $(PACKAGE_ZIP) $(CALENDAR_AGENT_PACKAGE_ZIP) $(NETWORK_AGENT_PACKAGE_ZIP)"

build-app: ## Internal target: build the app executable for ARCH.
	@scripts/build/build-products.sh release "$(ARCH)" --version "$(VERSION)" "$(APP_PRODUCT)=$(APP_BIN)"

build-lua-runtime: ## Internal target: build the Lua runtime executable for ARCH.
	@scripts/build/build-products.sh release "$(ARCH)" --version "$(VERSION)" "$(LUA_RUNTIME_PRODUCT)=$(LUA_RUNTIME_BIN)"

build-calendar-agent: ## Internal target: build the calendar agent executable for ARCH.
	@scripts/build/build-products.sh release "$(ARCH)" --version "$(VERSION)" "$(CALENDAR_AGENT_PRODUCT)=$(CALENDAR_AGENT_BIN)"

build-network-agent: ## Internal target: build the network agent executable for ARCH.
	@scripts/build/build-products.sh release "$(ARCH)" --version "$(VERSION)" "$(NETWORK_AGENT_PRODUCT)=$(NETWORK_AGENT_BIN)"

build-cli: ## Internal target: build the CLI executable for ARCH.
	@scripts/build/build-products.sh release "$(ARCH)" --version "$(VERSION)" "$(CLI_PRODUCT)=$(CLI_BIN)"

copy-resources: ## Internal target: copy SwiftPM resources and root assets into the app bundle.
	@scripts/build/copy-resources.sh release "$(ARCH)" "$(RESOURCE_BUNDLE_NAME)" "$(APP_BUNDLE)" "$(APP_RESOURCE_DIR)" "$(THEMES_DIR)" "$(APP_THEMES_DIR)" "$(VERSION)"

copy-debug-resources: ## Internal target: copy debug SwiftPM resources and root assets into the app bundle.
	@scripts/build/copy-resources.sh debug "$(RUN_ARCH)" "$(RESOURCE_BUNDLE_NAME)" "$(APP_BUNDLE)" "$(APP_RESOURCE_DIR)" "$(THEMES_DIR)" "$(APP_THEMES_DIR)" "$(VERSION)"

prepare-debug-app-bundle: ## Internal target: prepare local debug app bundle metadata.
	@mkdir -p "$(APP_CONTENTS)"
	@cp "$(PLIST_TEMPLATE)" "$(PLIST)"
	@python3 scripts/build/stamp.py plist \
		--plist "$(PLIST)" \
		--bundle-id "$(BUNDLE_ID)" \
		--version "$(VERSION)" \
		--executable "$(APP_EXEC)" \
		--name "$(APP_NAME)" \
		--icon-file "$(APP_ICON_FILE)"
	@touch "$(APP_BUNDLE)"

icons: ## Generate .icns files from SVG icons using librsvg, ImageMagick, sips, and iconutil.
	@scripts/assets/app_icons.sh "$(SVG_CONVERT)" "$(IMAGE_CONVERT)" "$(DIST_DIR)" \
		"$(APP_ICON_SVG):$(APP_ICON_ICNS)" \
		"$(CALENDAR_AGENT_ICON_SVG):$(CALENDAR_AGENT_ICON_ICNS)" \
		"$(NETWORK_AGENT_ICON_SVG):$(NETWORK_AGENT_ICON_ICNS)"

sign: ## Sign the app bundle, calendar agent, network agent, and CLI. Set CODESIGN_IDENTITY for Developer ID builds.
	@scripts/release/sign-artifacts.sh \
		"$(CODESIGN_IDENTITY)" \
		"$(APP_BUNDLE)" \
		"$(CALENDAR_AGENT_BUNDLE)" \
		"$(NETWORK_AGENT_BUNDLE)" \
		"$(CLI_BIN)"

notarize: ## Notarize the app bundle when NOTARY_SUBMIT=1 and a keychain profile is configured.
	@scripts/release/notarize-app.sh \
		"$(NOTARY_SUBMIT)" \
		"$(CODESIGN_IDENTITY)" \
		"$(NOTARYTOOL_PROFILE)" \
		"$(APP_BUNDLE)" \
		"$(NOTARY_ZIP)"

verify: ## Show the built bundle structure and validate key packaged files.
	@scripts/build/verify-bundle.sh --arch "$(ARCH)" --dist-dir "$(DIST_DIR)"

verify-release: package ## Build and validate the release package and print fingerprints.
	@scripts/release/verify-release.sh --version "$(VERSION)" --arch "$(ARCH)" --dist-dir "$(DIST_DIR)"

run: ## Fast local run with debug builds and local agents.
	@scripts/dev/run-local.sh info --run-arch "$(RUN_ARCH)" --version "$(VERSION)" --bundle-id "$(BUNDLE_ID)" --dist-dir "$(DIST_DIR)"

run-debug: ## Fast local run with debug builds and debug logging enabled.
	@scripts/dev/run-local.sh debug --run-arch "$(RUN_ARCH)" --version "$(VERSION)" --bundle-id "$(BUNDLE_ID)" --dist-dir "$(DIST_DIR)"

run-trace: ## Fast local run with debug builds and trace logging enabled.
	@scripts/dev/run-local.sh trace --run-arch "$(RUN_ARCH)" --version "$(VERSION)" --bundle-id "$(BUNDLE_ID)" --dist-dir "$(DIST_DIR)"

install-local: ## Build and install the current checkout with a Git-derived local version.
	@local_version="$$(scripts/dev/local-version.sh --version-prefix "$(VERSION_PREFIX)")"; \
		echo "Building local version $$local_version"; \
		$(MAKE) --no-print-directory bundle \
			ARCH="$(LOCAL_INSTALL_ARCH)" \
			VERSION="$$local_version" \
			BUNDLE_ID="$(BUNDLE_ID)" \
			CODESIGN_IDENTITY="$(CODESIGN_IDENTITY)" \
			NOTARY_SUBMIT=0 \
			NOTARYTOOL_PROFILE= \
			CLEAN_BUILD="$(CLEAN_BUILD)"
	@scripts/dev/install-local.sh \
		--dist-dir "$(DIST_DIR)" \
		--app-dir "$(LOCAL_APP_DIR)" \
		--bin-dir "$(LOCAL_BIN_DIR)" \
		--agent-dir "$(LOCAL_AGENT_DIR)" \
		--launch-agent-dir "$(LOCAL_LAUNCH_AGENT_DIR)" \
		--log-dir "$(LOCAL_LOG_DIR)" \
		--state-dir "$(LOCAL_STATE_DIR)"

install-widgets: ## Interactively copy bundled examples and declared assets.
	@scripts/dev/install-widgets.sh \
		"$(CURDIR)/examples" \
		"$(WIDGETS_INSTALL_DIR)" \
		"$(WIDGETS_INSTALL_MANIFEST)"

uninstall-local: ## Remove the local installation and restore the previous Homebrew service states.
	@scripts/dev/uninstall-local.sh \
		--app-dir "$(LOCAL_APP_DIR)" \
		--bin-dir "$(LOCAL_BIN_DIR)" \
		--agent-dir "$(LOCAL_AGENT_DIR)" \
		--launch-agent-dir "$(LOCAL_LAUNCH_AGENT_DIR)" \
		--state-dir "$(LOCAL_STATE_DIR)"

run-build-app: ## Internal target: fast local app build for RUN_ARCH.
	@scripts/build/build-products.sh debug "$(RUN_ARCH)" --version "$(VERSION)" "$(APP_PRODUCT)=$(APP_BIN)"

run-build-lua-runtime: ## Internal target: fast local Lua runtime build for RUN_ARCH.
	@scripts/build/build-products.sh debug "$(RUN_ARCH)" --version "$(VERSION)" "$(LUA_RUNTIME_PRODUCT)=$(LUA_RUNTIME_BIN)"

run-build-calendar-agent: ## Internal target: fast local calendar agent build for RUN_ARCH.
	@scripts/build/build-products.sh debug "$(RUN_ARCH)" --version "$(VERSION)" "$(CALENDAR_AGENT_PRODUCT)=$(CALENDAR_AGENT_BIN)"

run-build-network-agent: ## Internal target: fast local network agent build for RUN_ARCH.
	@scripts/build/build-products.sh debug "$(RUN_ARCH)" --version "$(VERSION)" "$(NETWORK_AGENT_PRODUCT)=$(NETWORK_AGENT_BIN)"

run-build-cli: ## Internal target: fast local CLI build for RUN_ARCH.
	@scripts/build/build-products.sh debug "$(RUN_ARCH)" --version "$(VERSION)" "$(CLI_PRODUCT)=$(CLI_BIN)"

stop: ## Stop EasyBar and its agents from installed and local app runs.
	@scripts/dev/stop-local.sh --dist-dir "$(DIST_DIR)"

restart-app: stop ## Restart the installed EasyBar application.
	open -a EasyBar

##@ Cleanup

clean-dist: ## Remove dist/.
	@scripts/build/clean-dist-dir.sh "$(DIST_DIR)"

clean: ## Remove dist/ and .build without modifying tracked sources.
	@scripts/build/clean-dist-dir.sh "$(DIST_DIR)"
	@rm -rf ".build"

##@ Info

print-arch: ## Print the selected ARCH.
	@echo "$(ARCH)"

print-run-arch: ## Print the selected RUN_ARCH.
	@echo "$(RUN_ARCH)"

print-version: ## Print the current version derived from the latest tag.
	@echo "$(CURRENT_VERSION)"

print-local-version: ## Print the Git-derived version used by install-local.
	@scripts/dev/local-version.sh --version-prefix "$(VERSION_PREFIX)"

print-latest-tag: ## Print the latest matching git tag.
	@echo "$(LATEST_TAG)"

print-package-sha256: package ## Print the SHA-256 of the packaged ZIPs.
	@shasum -a 256 "$(PACKAGE_ZIP)" "$(CALENDAR_AGENT_PACKAGE_ZIP)" "$(NETWORK_AGENT_PACKAGE_ZIP)"

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

##@ Tools

demo: ## Populate the demo calendar with random events.
	@swift scripts/tools/populate-demo-calendar.swift demo
