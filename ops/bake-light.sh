#!/usr/bin/env bash
# Bakes the rooms' lightmaps (the LightmapGI in each room scene) into scenes/rooms/<room>.lmbake and
# <room>.exr. It opens the editor with the Forward+ renderer, which the lightmapper needs (the game
# draws with Compatibility), so it needs a display and a GPU; the editor quits when it is done.
# Run it after changing a room's geometry or a light's colour, range or energy, and commit the output.
#
# The bake plugin (tools/bake_light) is enabled in project.godot for this run only, and project.godot
# is put back as it was afterwards: the editor also rewrites it on quitting (it drops settings equal
# to Godot's defaults).
#
# A new room's first bake takes two runs. The first writes its lightmap, which Godot then imports
# VRAM-compressed, a form some browsers' WebGL cannot read; the plugin sets the import lossless, and
# the lightmapper keeps that setting from the second bake on. tests/visual/test_atmosphere.gd fails
# on a lightmap that is not stored lossless.
set -euo pipefail
cd "$(dirname "$0")/.."
godot --headless --path . --import
plugin='res://tools/bake_light/plugin.cfg'
kept=".godot/bake-light-project.godot"
cp project.godot "$kept"
trap 'cp "$kept" project.godot; rm -f "$kept"' EXIT
perl -pi -e 's{^(enabled=PackedStringArray\(.*)\)$}{$1, "'"$plugin"'")}' project.godot
if ! grep -qF "\"$plugin\"" project.godot; then
  echo "ops/bake-light.sh: could not enable the bake plugin in project.godot" >&2
  exit 1
fi
godot --editor --path . --rendering-method forward_plus -- --bake-light
