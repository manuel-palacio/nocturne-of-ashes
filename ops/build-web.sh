#!/usr/bin/env bash
# Exports the game for the browser into build/web (threads off, so any static server can host it).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/web
# Keeps Godot from importing the build output as project files.
touch build/.gdignore
godot --headless --path . --export-release "Web" build/web/index.html
