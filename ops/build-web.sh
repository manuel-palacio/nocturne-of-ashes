#!/usr/bin/env bash
# Exports the game for the browser into build/web (threads off, so any static server can host it), with
# the credits beside it: credits.txt (CREDITS.md) and licenses.txt, the engine's licence and notices as
# the engine itself gives them (tools/engine_licenses.gd), then every licence file CREDITS.md names.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/web
# Keeps Godot from importing the build output as project files.
touch build/.gdignore
# Godot keeps each resource's export conversion under .godot/exported and reuses it while the
# resource's own file is unchanged. A conversion leaves out values equal to the script's defaults at
# the time, so after a script's defaults change a reused one loads with the new defaults instead:
# convert everything afresh.
rm -rf .godot/exported
godot --headless --path . --export-release "Web" build/web/index.html

cp CREDITS.md build/web/credits.txt
godot --headless --path . -s tools/engine_licenses.gd -- build/engine-licenses.txt
{
  echo "Licence texts for Nocturne of Ashes and the work it uses, as named in credits.txt."
  printf '\n######## Godot Engine ########\n\n'
  cat build/engine-licenses.txt
  for file in $(ops/licence-files.sh); do
    printf '\n######## %s ########\n\n' "$file"
    cat "$file"
  done
} > build/web/licenses.txt
