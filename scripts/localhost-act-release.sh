#!/bin/bash

set -eux

# Prerequisites:
#
# Act is installed via `brew install act`
# - act version 0.2.89
#
# effective env must be given

GITHUB_TOKEN="$(gh auth token)"
HOMEBREW_TAP_GITHUB_TOKEN="${HOMEBREW_TAP_GITHUB_TOKEN}"
TAG="${TAG}"

# Prepare temporary directory for artifacts

_TMPDIR=.goreleaser/upload
_TMPWORKDIR=/tmp/act/release-build
mkdir -p "${_TMPDIR}/" "${_TMPWORKDIR}"
if [ -L "${_TMPWORKDIR}"/repo ]; then
  rm "${_TMPWORKDIR}"/repo
fi
ln -s "$PWD" "${_TMPWORKDIR}"/repo
cd "${_TMPWORKDIR}"/repo

SECRET_ARGS="\
  -s GITHUB_TOKEN=${GITHUB_TOKEN} \
  -s CAT_SWITCH_GITHUB_TOKEN=${GITHUB_TOKEN} \
  -s HOMEBREW_TAP_GITHUB_TOKEN=${HOMEBREW_TAP_GITHUB_TOKEN} \
"

# way-1: run specific job
#
act \
  ${SECRET_ARGS} \
  -j goreleaser \
  -P macos-26=-self-hosted --input tag="${TAG}" workflow_dispatch --artifact-server-path "${_TMPDIR}/"

## way-2: Imitate event
## # Prerequisite: Create a JSON file for workflow_dispatch event
## echo ' { "inputs": { "tag": "${TAG}" } } ' > ".goreleaser/localhost/tag-${TAG}.json"
##
#act \
#  ${SECRET_ARGS} \
#  -e ".goreleaser/localhost/tag-${TAG}.json" \
#  -P macos-26=-self-hosted workflow_dispatch --artifact-server-path "${_TMPDIR}/"
