#!/usr/bin/env bash
# Slice transcript to [start,end], build ASS karaoke captions, burn them into the clip.
# usage: captions_burn.sh <in.mp4> <transcript.json> <startSec> <endSec> <out.mp4> <font.ttf> [wordsPerLine]
#
# Windows note: the ffmpeg `subtitles` filter chokes on drive-colon paths. We sidestep
# all escaping by generating the .ass + font copy in a temp dir and running ffmpeg from
# INSIDE it with relative filter paths (no colons to escape).
set -euo pipefail
IN="${1:?in}"; TR="${2:?transcript.json}"; S0="${3:?start sec}"; S1="${4:?end sec}"; OUT="${5:?out}"; FONT="${6:?font ttf}"; WPL="${7:-4}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# absolute in/out (these are ffmpeg -i/-o args, colons are fine there)
IN_ABS="$(cd "$(dirname "$IN")" && pwd)/$(basename "$IN")"
mkdir -p "$(dirname "$OUT")"
OUT_DIR="$(cd "$(dirname "$OUT")" && pwd)"; OUT_ABS="$OUT_DIR/$(basename "$OUT")"

# libass matches by font FAMILY name; the bundled font's family is "DejaVu Sans" (Bold=1 in style).
FONTNAME="${CAPTION_FONT_FAMILY:-DejaVu Sans}"

WORK="$(mktemp -d)"
cp "$FONT" "$WORK/"
node "$HERE/ass_from_words.cjs" "$TR" "$S0" "$S1" "$FONTNAME" "$WPL" > "$WORK/subs.ass"
# keep a copy of the ass next to the output for debugging
cp "$WORK/subs.ass" "${OUT_ABS%.mp4}.ass"

( cd "$WORK" && ffmpeg -y -i "$IN_ABS" -vf "subtitles=subs.ass:fontsdir=." \
    -c:v libx264 -pix_fmt yuv420p -c:a copy "$OUT_ABS" )

rm -rf "$WORK"
echo "$OUT_ABS"
