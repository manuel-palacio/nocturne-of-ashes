#!/usr/bin/env bash
# Checks the browser build in build/web against its budget: at most 80 MB on disk, and no single file
# other than the engine's .wasm over 30 MB. Prints the build's files and the ten largest assets inside
# the pack (index.pck), read from the pack's own file table by a few lines of Python. Run it from the
# repository root after ops/build-web.sh; it exits non-zero when the budget is broken, or when the
# build lacks the credits (credits.txt, the same as CREDITS.md) or a licence text: licenses.txt must
# hold the engine's licence and every licence file CREDITS.md names (ops/licence-files.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
web=build/web
pack="$web/index.pck"
total_limit=$((80 * 1024 * 1024))
file_limit=$((30 * 1024 * 1024))
[ -f "$pack" ] || { echo "ops/check-budget.sh: no $pack; run ops/build-web.sh first" >&2; exit 1; }

fail=0
mb() { awk -v b="$1" 'BEGIN {printf "%.1f", b / 1048576}'; }
total=0
while IFS= read -r file; do total=$((total + $(wc -c < "$file"))); done < <(find "$web" -type f)
echo "build/web: $(mb "$total") MB (limit 80 MB)"
[ "$total" -le "$total_limit" ] || { echo "ops/check-budget.sh: build/web is over 80 MB" >&2; fail=1; }

echo "Files:"
while IFS= read -r file; do
  size=$(wc -c < "$file" | tr -d ' ')
  printf '  %8s MB  %s\n' "$(mb "$size")" "${file#"$web"/}"
  if [ "${file##*.}" != "wasm" ] && [ "$size" -gt "$file_limit" ]; then
    echo "ops/check-budget.sh: $file is over 30 MB" >&2; fail=1
  fi
done < <(find "$web" -type f | sort)

echo "Credits and licences:"
if cmp -s CREDITS.md "$web/credits.txt"; then
  echo "  credits.txt is CREDITS.md"
else
  echo "ops/check-budget.sh: $web/credits.txt is missing or differs from CREDITS.md" >&2; fail=1
fi
licenses="$web/licenses.txt"
for section in "Godot Engine" $(ops/licence-files.sh); do
  if [ -f "$licenses" ] && grep -qxF "######## $section ########" "$licenses"; then
    echo "  licenses.txt holds $section"
  else
    echo "ops/check-budget.sh: $licenses lacks the licence of $section" >&2; fail=1
  fi
done

echo "Ten largest assets in the pack:"
python3 -I - "$pack" <<'PY'
import struct, sys

# The pack's header (Godot 4.7): magic, format version, engine version, flags, the offset the file
# offsets count from, then the offset of the file table: a count and, for each file, its path's
# length and padded path, offset, size, MD5 and flags.
data = open(sys.argv[1], "rb").read()
magic, _version, _major, _minor, _patch, _flags, _base, table = struct.unpack_from("<4sIIIIIQQ", data, 0)
if magic != b"GDPC":
    sys.exit("not a Godot pack: " + sys.argv[1])
count, = struct.unpack_from("<I", data, table)
at = table + 4
files = []
for _ in range(count):
    length, = struct.unpack_from("<I", data, at)
    path = data[at + 4:at + 4 + length].rstrip(b"\0").decode()
    _offset, size = struct.unpack_from("<QQ", data, at + 4 + length)
    at += 4 + length + 16 + 16 + 4
    files.append((size, path))
for size, path in sorted(files, reverse=True)[:10]:
    print("  %8.2f MB  %s" % (size / 1048576, path))
print("  (%d files, %.1f MB)" % (len(files), sum(s for s, _ in files) / 1048576))
PY
exit $fail
