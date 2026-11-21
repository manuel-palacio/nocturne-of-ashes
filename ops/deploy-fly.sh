#!/usr/bin/env bash
# Builds the public flavour of the web export (build/public, where the probe and the test parameters
# do nothing) and deploys it to Fly.io as the app named in fly.toml (needs the fly CLI, logged in).
# One machine, stopped while nobody is playing and started by the next visit. Before deploying it
# checks that what it ships is the public flavour, and stops if not.
set -euo pipefail
cd "$(dirname "$0")/.."
ops/build-web.sh public
ops/check-public-build.sh build/public
fly deploy --ha=false
