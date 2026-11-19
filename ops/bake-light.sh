#!/usr/bin/env bash
# Bakes the rooms' lightmaps (the LightmapGI in each room scene) into scenes/rooms/<room>.lmbake and
# <room>.exr. It opens the editor with the Forward+ renderer, which the lightmapper needs (the game
# draws with Compatibility), so it needs a display and a GPU; the editor quits when it is done.
# Run it after changing a room's geometry or a light's colour, range or energy, and commit the output.
set -euo pipefail
cd "$(dirname "$0")/.."
godot --headless --path . --import
# The editor rewrites project.godot on quitting (it drops settings equal to Godot's defaults); keep it.
kept="$(mktemp)"
trap 'cp "$kept" project.godot; rm -f "$kept"' EXIT
cp project.godot "$kept"
godot --editor --path . --rendering-method forward_plus -- --bake-light
