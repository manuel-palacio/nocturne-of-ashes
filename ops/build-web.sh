#!/usr/bin/env bash
# Exports the game for the browser (threads off, so any static server can host it), in one of two
# flavours from the same source, named by the optional argument:
#   test   (the default) into build/web, by the "Web" preset: the browser tests' build, where the page
#          parameter probe=1 turns on the probe and the test parameters;
#   public into build/public, by the "Web public" preset (the `public` feature): the site's build, where
#          probe=1 and the test parameters do nothing (src/core/probe_gate.gd).
# Beside the game go the credits: credits.txt (CREDITS.md) and licenses.txt, the engine's licence and
# notices as the engine itself gives them (tools/engine_licenses.gd), then every licence file
# CREDITS.md names; and flavour.txt, holding the flavour's name, which ops/deploy-fly.sh checks.
set -euo pipefail
cd "$(dirname "$0")/.."
flavour="${1:-test}"
case "$flavour" in
  test) preset="Web"; out=build/web ;;
  public) preset="Web public"; out=build/public ;;
  *) echo "usage: ops/build-web.sh [test|public]" >&2; exit 2 ;;
esac
# Afresh, so nothing of an earlier export is left behind.
rm -rf "$out"
mkdir -p "$out"
# Keeps Godot from importing the build output as project files.
touch build/.gdignore
# Godot keeps each resource's export conversion under .godot/exported and reuses it while the
# resource's own file is unchanged. A conversion leaves out values equal to the script's defaults at
# the time, so after a script's defaults change a reused one loads with the new defaults instead:
# convert everything afresh.
rm -rf .godot/exported
godot --headless --path . --export-release "$preset" "$out/index.html"

cp CREDITS.md "$out/credits.txt"
godot --headless --path . -s tools/engine_licenses.gd -- build/engine-licenses.txt
{
  echo "Licence texts for Nocturne of Ashes and the work it uses, as named in credits.txt."
  printf '\n######## Godot Engine ########\n\n'
  cat build/engine-licenses.txt
  for file in $(ops/licence-files.sh); do
    printf '\n######## %s ########\n\n' "$file"
    cat "$file"
  done
} > "$out/licenses.txt"
echo "$flavour" > "$out/flavour.txt"
