#!/usr/bin/env bash
# Exports the game for the browser into build/web (threads off, so any static server can host it).
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
