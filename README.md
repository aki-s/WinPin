This doc is for `WinPin` version 0.0.2 (stable version)

# About

WinPin is a native macOS AppKit menu bar app for best-effort per-window pinning.

Useful when;

- You are annoyed by the default MacOS switcher, which brings all windows in front.
  This behavior hides the previous window you were working but you have been interested in yet.
  - You want to focus solely on the active windows you're using across multiple apps.
- You join a video meeting while keeping the window on top of other screens.
  (e.g. Zoom.app supports this feature, but only when minimized).

## Installation

### Homebrew (Recommended)

```sh
brew tap aki-s/tap
brew install --cask win-pin
```

## Features

### Shortcut

`ctrl+alt+Command+t` to Pin the currently focused window.

### Menu bar

![menu](./docs/menu.20260816.png)

You can define which window should be stacked on the other Pinned windows manually.

![win-stacks](./docs/Pinwin.win-stacks.png)

## Development

### Daily Development & Debugging

```sh
# Build debug binary and reset accessibility permission
./scripts/build-debug-reset-accessibility.sh

# Restart app
make restart
# or ./scripts/restart.sh
```

### Test & Lint

```sh
# Run unit tests
make test

# Run static analysis and lint
make lint

# Automatically format and fix lint issues
make fix
```

### Release Workflow

#### 0. Setup

```sh
brew install goreleaser act gh
```

Register PAT secret named `HOMEBREW_TAP_GITHUB_TOKEN` to access ${owner}/homebrew-tap at the artifact repository

https://github.com/${owner}/WinPin/settings/secrets/actions

#### 1. Local Verification (Dry-Run with GoReleaser)

```sh
# Build arm64 and x86_64 Release binaries for version 0.0.1
make build-all-arch APP_VERSION=0.0.1

# Prepare artifacts for GoReleaser
make goreleaser-prep

# Test packaging and cask generation locally (Dry-run without publishing)
make goreleaser-dryrun APP_VERSION=0.0.1
```

#### 2. Local Release & Draft PR to homebrew-tap

```sh
# Create GitHub Release on ${owner}/WinPin and create a draft PR in ${owner}/homebrew-tap
GITHUB_TOKEN="$(gh auth token)" \
HOMEBREW_TAP_GITHUB_TOKEN="<your-pat-for-homebrew-tap>" \
make goreleaser-release APP_VERSION=0.0.1
```

#### 3. GitHub Actions Release

Trigger the `goreleaser` workflow via GitHub Actions (`workflow_dispatch`) by specifying the release tag (e.g., `0.0.1`).
Ensure `HOMEBREW_TAP_GITHUB_TOKEN` secret is configured in the repository settings.
