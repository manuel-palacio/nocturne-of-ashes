#!/usr/bin/env bash
# Checks that the web build in the directory given (build/public by default) is the public flavour,
# the only one the site may serve: its flavour.txt says "public", and its pack holds the project
# setting the export writes for the `public` feature. Exits non-zero, saying why, when either fails:
# a test-flavour build (flavour.txt "test", no such setting) would let a link to the site turn on
# the probe and the test parameters.
set -euo pipefail
cd "$(dirname "$0")/.."
dir="${1:-build/public}"
dir="${dir%/}"
fail() { echo "ops/check-public-build.sh: $dir $1; not deploying it" >&2; exit 1; }
[ -f "$dir/flavour.txt" ] || fail "has no flavour.txt"
flavour="$(cat "$dir/flavour.txt")"
[ "$flavour" = public ] || fail "is the \"$flavour\" flavour, not \"public\""
[ -f "$dir/index.pck" ] || fail "has no index.pck"
# The feature list is stored as the setting's name, a few bytes of type and length, then the text.
LC_ALL=C grep -aq '_custom_features.\{0,16\}public' "$dir/index.pck" \
  || fail "was not exported with the public feature"
echo "$dir is the public flavour"
