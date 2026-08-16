ARCH ?= arm64
APP_VERSION ?= 0.0.1
VERSION_NUM := $(patsubst v%,%,$(APP_VERSION))

## ----------------------------------------------------------------
## build
## ----------------------------------------------------------------

.PHONY: build-debug
build-debug:
	xcodebuild -project WinPin.xcodeproj \
		-scheme WinPin \
		-configuration Debug \
		-derivedDataPath build/DerivedData \
		build

.PHONY: build-app
build-app:
	@mkdir -p .build/$(ARCH)
	xcodebuild -project WinPin.xcodeproj \
		-scheme WinPin \
		-configuration Release \
		-destination "generic/platform=macOS" \
		ARCHS="$(ARCH)" \
		ONLY_ACTIVE_ARCH=NO \
		MARKETING_VERSION="$(VERSION_NUM)" \
		CURRENT_PROJECT_VERSION="$(VERSION_NUM)" \
		-derivedDataPath "build/DerivedData-$(ARCH)" \
		clean build
	rm -rf .build/$(ARCH)/WinPin.app
	cp -R build/DerivedData-$(ARCH)/Build/Products/Release/WinPin.app .build/$(ARCH)/WinPin.app

.PHONY: build-all-arch
build-all-arch:
	$(MAKE) build-app ARCH=arm64 APP_VERSION=$(APP_VERSION)
	$(MAKE) build-app ARCH=x86_64 APP_VERSION=$(APP_VERSION)

## ----------------------------------------------------------------
## goreleaser
## ----------------------------------------------------------------

.PHONY: goreleaser-prep
goreleaser-prep:
	@mkdir -p .goreleaser/WinPin_arm64 .goreleaser/WinPin_x86_64
	rm -rf .goreleaser/WinPin_arm64/WinPin.app .goreleaser/WinPin_x86_64/WinPin.app
	cp -R .build/arm64/WinPin.app .goreleaser/WinPin_arm64/WinPin.app
	cp -R .build/x86_64/WinPin.app .goreleaser/WinPin_x86_64/WinPin.app

.PHONY: goreleaser-dryrun
goreleaser-dryrun:
	GORELEASER_CURRENT_TAG=$(APP_VERSION) goreleaser release --snapshot --clean --skip=publish,announce,validate

.PHONY: goreleaser-release
goreleaser-release:
	GORELEASER_CURRENT_TAG=$(APP_VERSION) goreleaser release --clean

## ----------------------------------------------------------------
## test
## ----------------------------------------------------------------

.PHONY: test
test:
	xcodebuild -project WinPin.xcodeproj \
		-scheme WinPin \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath build/DerivedData \
		test

## ----------------------------------------------------------------
## lint
## ----------------------------------------------------------------

.PHONY: lint-format
lint-format:
	swiftformat --version
	swiftformat --lint . --exclude .build,build,.goreleaser,dist --reporter github-actions-log

	swiftlint --version
	swiftlint lint --strict --cache-path .build/swiftlint-cache --exclude .build,build,.goreleaser,dist

.PHONY: lint-unused
lint-unused:
	periphery version
	periphery scan --project WinPin.xcodeproj --schemes WinPin

.PHONY: lint
lint: lint-unused lint-format

## ----------------------------------------------------------------
## fix
## ----------------------------------------------------------------

.PHONY: lint-fix
lint-fix:
	swiftlint lint --fix --cache-path .build/swiftlint-cache WinPin WinPinTests

.PHONY: format
format:
	swiftformat WinPin WinPinTests
	swiftlint lint --fix --cache-path .build/swiftlint-cache WinPin WinPinTests

.PHONY: fix
fix: format

## ----------------------------------------------------------------
## run & restart
## ----------------------------------------------------------------

.PHONY: restart
restart:
	./scripts/restart.sh

## ----------------------------------------------------------------
## clean
## ----------------------------------------------------------------

.PHONY: clean
clean:
	rm -rf .build build dist .goreleaser
