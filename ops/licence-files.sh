#!/usr/bin/env bash
# Prints, one per line, every licence file CREDITS.md names (a `...LICENSE...` path in backticks),
# relative to the repository root. ops/build-web.sh serves their texts and ops/check-budget.sh checks
# that the build holds each one.
set -euo pipefail
cd "$(dirname "$0")/.."
grep -oE '`[^`]*LICENSE[^`]*`' CREDITS.md | tr -d '`' | sort -u
