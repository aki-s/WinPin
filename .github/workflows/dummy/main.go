package main

// WORKAROUND EXPLANATION:
// GoReleaser open-source requires a "build" context to assign GOOS (darwin) and GOARCH
// metadata to archives. Without this metadata, the `homebrew_casks` step will fail with:
// "no linux/macos archives found matching goos=..."
//
// The `builder: prebuilt` feature would normally solve this by letting us import the
// pre-built macOS `.app` bundle, but it is a paid GoReleaser Pro feature.
//
// To bypass this limitation, we provide this dummy Go file. GoReleaser will "build" it,
// successfully assign the `darwin/amd64` and `darwin/arm64` metadata to the build, and
// then we map this build to our custom `archives` block in `.goreleaser.yaml` to include
// the actual `.app` bundle.
func main() {}

