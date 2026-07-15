#!/usr/bin/env bash
# Normalize a local file OR a URL into <project>/work/source.mp4
set -euo pipefail
SRC="${1:?usage: intake.sh <file-or-url> <project-dir>}"
PROJ="${2:?missing project dir}"
mkdir -p "$PROJ/work"
OUT="$PROJ/work/source.mp4"

if [[ "$SRC" =~ ^https?:// ]]; then
  command -v yt-dlp >/dev/null 2>&1 || { echo "yt-dlp not installed. Run: python -m pip install -U yt-dlp"; exit 3; }
  yt-dlp -f "bv*+ba/b" --merge-output-format mp4 -o "$PROJ/work/dl.%(ext)s" "$SRC"
  IN="$(ls "$PROJ"/work/dl.* | head -1)"
else
  [ -f "$SRC" ] || { echo "no such file: $SRC"; exit 2; }
  IN="$SRC"
fi

# normalize to a known-good baseline (+faststart for streaming)
ffmpeg -y -i "$IN" -c:v libx264 -pix_fmt yuv420p -c:a aac -movflags +faststart "$OUT"
[ "$IN" != "$SRC" ] && rm -f "$IN" || true
echo "$OUT"
