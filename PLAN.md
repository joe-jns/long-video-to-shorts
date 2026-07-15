# long-video-to-shorts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a fully-local skill that turns one long video into N vertical (9:16) captioned "shorts", with the agent selecting moments and the user approving before render.

**Architecture:** A bash-script pipeline (intake → probe → transcribe → agent picks → build → deliver) driven by `SKILL.md` doctrine. Two render branches: face-cam (crop-to-face 9:16 + `embedded-captions` skill) and screen/gameplay (blurred-pad 9:16 + ffmpeg ASS karaoke burn-in). Transcription via `hyperframes transcribe`; the agent uses its own vision to locate faces and select moments.

**Tech Stack:** bash (Git Bash on Windows), ffmpeg/ffprobe 8.1.1, `hyperframes` CLI 0.7.58 (`transcribe`, `tts`), node 24 (ASS generation), `yt-dlp` (URL intake), `embedded-captions` skill.

## Global Constraints

- **No git repo** at `C:\Users\micro` — replace every "commit" with a **CHECKPOINT** (verify the artifact exists with correct properties). Do NOT `git init`.
- **Skill root:** `C:\Users\micro\.claude\skills\long-video-to-shorts\` — every path below is relative to it unless absolute.
- **Scripts are POSIX bash**, run via the Bash tool (Git Bash), invoked as `bash scripts/<name>.sh`. Use forward slashes; quote all paths.
- **Output frame:** exactly `1080x1920` (9:16), even dimensions, `yuv420p`, H.264 + AAC.
- **Language default:** `fr`. Transcription via the skill's own `scripts/transcribe.py` (faster-whisper, CPU int8) — NOT `hyperframes transcribe` (whisper-cpp is not built on this machine; see `_fixtures/ENV_NOTES.md`). Output schema: flat `words[].{text,start,end}` + `language` + `segments[]`.
- **Duration:** each short ≤ 60s (hard cap), ≥ ~12s useful minimum.
- **Per-project working dir:** the skill operates inside a user-chosen project dir containing `work/` (intermediates) and `shorts/` (finals). Fixtures for building the skill live in `_fixtures/` under the skill root.
- **Fonts:** bundle a free bold font in `assets/fonts/` (Inter or DejaVuSans-Bold) for gameplay captions + hook banner; reference by absolute path in ffmpeg.

---

### Task 0: Scaffold + environment gate + French-Whisper verification + fixtures

**Files:**
- Create: `_fixtures/make_fixtures.sh`
- Create: `_fixtures/` outputs `facecam.mp4`, `gameplay.mp4`, `fr_speech.wav`
- Create: dir tree `references/`, `scripts/`, `assets/fonts/`
- Create: `_fixtures/ENV_NOTES.md` (records verified facts: transcript.json shape, FR model used)

**Interfaces:**
- Produces: `_fixtures/facecam.mp4` (16:9, a synthetic "face" + French speech), `_fixtures/gameplay.mp4` (16:9, moving graphics + French speech), `_fixtures/transcript_sample.json` (real output of `hyperframes transcribe -l fr`), and `ENV_NOTES.md` documenting the transcript JSON schema (word objects: field names for text/start/end) that Task 6 depends on.

- [ ] **Step 1: Create directory tree**

```bash
mkdir -p "C:/Users/micro/.claude/skills/long-video-to-shorts/scripts" \
         "C:/Users/micro/.claude/skills/long-video-to-shorts/references" \
         "C:/Users/micro/.claude/skills/long-video-to-shorts/assets/fonts" \
         "C:/Users/micro/.claude/skills/long-video-to-shorts/_fixtures"
```

- [ ] **Step 2: Bundle a font**

Copy a free bold TTF into `assets/fonts/`. On Windows, `C:/Windows/Fonts/arialbd.ttf` exists but is not redistributable; prefer DejaVu (ships with many tools) or download Inter. Verify a usable font resolves:

```bash
ls -la "C:/Users/micro/.claude/skills/long-video-to-shorts/assets/fonts/"
# Must contain at least one .ttf (e.g. Inter-Bold.ttf or DejaVuSans-Bold.ttf)
```

Expected: at least one `.ttf` present. If none, download Inter Bold to that path before proceeding.

- [ ] **Step 3: Write `_fixtures/make_fixtures.sh`**

Generates French speech via `hyperframes tts`, then muxes it onto synthetic video so Whisper has real French to transcribe.

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

# 1) French speech (~8s) via hyperframes tts
npx --no-install hyperframes tts "Bonjour, ceci est un test. Voici le vrai piège des débutants en montage vidéo." \
  --language fr -o fr_speech.wav || echo "TTS failed — will fall back to silent audio"

# audio input: tts wav if present else anullsrc
if [ -f fr_speech.wav ]; then AUD=(-i fr_speech.wav); MAP=(-map 0:v -map 1:a); 
else AUD=(-f lavfi -i anullsrc=r=44100:cl=stereo); MAP=(-map 0:v -map 1:a); fi

# 2) facecam fixture: 1920x1080, a centered "face" (skin circle + eyes) shifted right of center
ffmpeg -y -f lavfi -i "color=c=0x223344:s=1920x1080:d=8:r=30" "${AUD[@]}" \
  -filter_complex "[0:v]drawbox=x=1120:y=340:w=360:h=360:color=0xE0B080:t=fill,\
drawbox=x=1200:y=470:w=40:h=40:color=black:t=fill,drawbox=x=1360:y=470:w=40:h=40:color=black:t=fill[v]" \
  -map "[v]" -map 1:a -shortest -c:v libx264 -pix_fmt yuv420p -c:a aac facecam.mp4

# 3) gameplay fixture: 1920x1080 moving test pattern
ffmpeg -y -f lavfi -i "testsrc2=s=1920x1080:d=8:r=30" "${AUD[@]}" \
  -map 0:v -map 1:a -shortest -c:v libx264 -pix_fmt yuv420p -c:a aac gameplay.mp4

echo "Fixtures ready:"; ls -la facecam.mp4 gameplay.mp4 fr_speech.wav 2>/dev/null || true
```

- [ ] **Step 4: Run fixture generation**

Run: `bash "C:/Users/micro/.claude/skills/long-video-to-shorts/_fixtures/make_fixtures.sh"`
Expected: `facecam.mp4` and `gameplay.mp4` created, 1920x1080, 8s, with an audio track.

- [ ] **Step 5: Verify French transcription (THE RISK — resolve here)**

```bash
cd "C:/Users/micro/.claude/skills/long-video-to-shorts/_fixtures"
npx --no-install hyperframes transcribe fr_speech.wav -l fr -m large-v3 --json > transcribe_out.json 2>transcribe_err.txt || cat transcribe_err.txt
# inspect: does it contain French words (e.g. "piège", "débutants") and word-level start/end?
cat transcribe_out.json | node -e "let d=require('fs').readFileSync(0,'utf8');console.log(d.slice(0,800))"
```

Expected: JSON containing recognizable French words with per-word `start`/`end`.
- If `-m large-v3` is unavailable or English-only output: try `-m small` (multilingual), then install the multilingual ggml model per `hyperframes` docs. Record the WORKING model + command in `ENV_NOTES.md`.
- **Gate:** do not proceed to Task 6 until a model reliably transcribes French. Copy the working transcript to `_fixtures/transcript_sample.json`.

- [ ] **Step 6: Document transcript schema**

Write `_fixtures/ENV_NOTES.md` recording: the exact working `transcribe` command for FR, and the JSON path to word objects + the field names for `text`, `start`, `end` (e.g. `segments[].words[].{word,start,end}`). Task 6 reads these exact field names.

- [ ] **Step 7: CHECKPOINT**

Verify: `_fixtures/facecam.mp4`, `_fixtures/gameplay.mp4`, `_fixtures/transcript_sample.json`, `_fixtures/ENV_NOTES.md` all exist; `ENV_NOTES.md` names the FR model and the word-field schema.

---

### Task 1: `intake.sh` — normalize input to `work/source.mp4`

**Files:**
- Create: `scripts/intake.sh`

**Interfaces:**
- Consumes: `$1` = local path OR http(s) URL; `$2` = project dir.
- Produces: `<project>/work/source.mp4` (H.264/AAC, faststart). Prints the absolute path on success.

- [ ] **Step 1: Write the test harness**

```bash
# tests inline: local-file path
PROJ="C:/Users/micro/.claude/skills/long-video-to-shorts/_fixtures/_t_intake"
rm -rf "$PROJ"; mkdir -p "$PROJ"
bash "C:/Users/micro/.claude/skills/long-video-to-shorts/scripts/intake.sh" \
  "C:/Users/micro/.claude/skills/long-video-to-shorts/_fixtures/facecam.mp4" "$PROJ"
```

- [ ] **Step 2: Run to verify it fails**

Run the harness above. Expected: FAIL (`intake.sh` not found).

- [ ] **Step 3: Implement `intake.sh`**

```bash
#!/usr/bin/env bash
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

# normalize (re-mux/encode to a known-good baseline, +faststart)
ffmpeg -y -i "$IN" -c:v libx264 -pix_fmt yuv420p -c:a aac -movflags +faststart "$OUT"
[ "$IN" != "$SRC" ] && rm -f "$IN" || true
echo "$OUT"
```

- [ ] **Step 4: Run to verify it passes**

Run the harness. Then:
```bash
ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$PROJ/work/source.mp4"
```
Expected: prints `h264`; `source.mp4` exists.

- [ ] **Step 5: CHECKPOINT** — `work/source.mp4` produced from a local file; URL branch present with a clear yt-dlp-missing error.

---

### Task 2: `probe.sh` — specs + contact sheet for classification

**Files:**
- Create: `scripts/probe.sh`

**Interfaces:**
- Consumes: `$1` = project dir (expects `work/source.mp4`).
- Produces: `<project>/work/probe.json` (width,height,duration,fps) and `<project>/work/contactsheet.png` (1fps tiled thumbnails). The AGENT reads the sheet to classify facecam vs screen and to locate faces/action.

- [ ] **Step 1: Write the test harness**

```bash
PROJ="C:/Users/micro/.claude/skills/long-video-to-shorts/_fixtures/_t_probe"
rm -rf "$PROJ"; mkdir -p "$PROJ/work"
cp "C:/Users/micro/.claude/skills/long-video-to-shorts/_fixtures/facecam.mp4" "$PROJ/work/source.mp4"
bash "C:/Users/micro/.claude/skills/long-video-to-shorts/scripts/probe.sh" "$PROJ"
```

- [ ] **Step 2: Run to verify it fails** — Expected: FAIL (script missing).

- [ ] **Step 3: Implement `probe.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
PROJ="${1:?usage: probe.sh <project-dir>}"
SRC="$PROJ/work/source.mp4"
[ -f "$SRC" ] || { echo "missing $SRC"; exit 2; }

ffprobe -v error -select_streams v:0 \
  -show_entries stream=width,height,avg_frame_rate:format=duration \
  -of json "$SRC" > "$PROJ/work/probe.json"

# 1 fps contact sheet, tiled 6 columns, thumbnails 240px wide
ffmpeg -y -i "$SRC" -vf "fps=1,scale=240:-1,tile=6x0" -frames:v 1 \
  "$PROJ/work/contactsheet.png" 2>/dev/null || \
ffmpeg -y -i "$SRC" -vf "fps=1,scale=240:-1,tile=6x4" -frames:v 1 "$PROJ/work/contactsheet.png"
echo "probe.json + contactsheet.png written to $PROJ/work/"
```

- [ ] **Step 4: Run to verify it passes**

Run harness. Expected: `work/probe.json` shows `width:1920,height:1080`; `work/contactsheet.png` exists (open with Read to confirm it's a valid tiled image).

- [ ] **Step 5: CHECKPOINT** — both artifacts present, probe.json parseable.

---

### Task 3: `cut.sh` — precise segment extraction

**Files:**
- Create: `scripts/cut.sh`

**Interfaces:**
- Consumes: `$1` src video, `$2` start (HH:MM:SS.mmm), `$3` end, `$4` out path.
- Produces: `$4` — accurate re-encoded segment (frame-accurate; not stream-copy).

- [ ] **Step 1: Test harness**

```bash
F="C:/Users/micro/.claude/skills/long-video-to-shorts/_fixtures"
bash "$F/../scripts/cut.sh" "$F/facecam.mp4" 00:00:02.0 00:00:05.0 "$F/_t_cut.mp4"
ffprobe -v error -show_entries format=duration -of csv=p=0 "$F/_t_cut.mp4"
```

- [ ] **Step 2: Run to verify it fails** — Expected: FAIL (missing script).

- [ ] **Step 3: Implement `cut.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
SRC="${1:?src}"; START="${2:?start}"; END="${3:?end}"; OUT="${4:?out}"
# accurate seek: -ss/-to AFTER -i, re-encode
ffmpeg -y -i "$SRC" -ss "$START" -to "$END" \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -avoid_negative_ts make_zero "$OUT"
echo "$OUT"
```

- [ ] **Step 4: Run to verify it passes** — Expected: duration ≈ `3.0` (±0.1s).

- [ ] **Step 5: CHECKPOINT** — segment duration within tolerance of requested window.

---

### Task 4: `reframe_facecam.sh` — crop to 9:16 at a given face center

**Files:**
- Create: `scripts/reframe_facecam.sh`

**Interfaces:**
- Consumes: `$1` in clip, `$2` face_center_x (0..1), `$3` out path.
- Produces: `$3` — exactly `1080x1920`. Crop window height = full source height; width = `h*9/16`; x centered on `face_center_x`, clamped to frame. If source narrower than the 9:16 window (already-portrait), fall back to width-crop + pad.

- [ ] **Step 1: Test harness**

```bash
S="C:/Users/micro/.claude/skills/long-video-to-shorts/scripts"
F="C:/Users/micro/.claude/skills/long-video-to-shorts/_fixtures"
bash "$S/reframe_facecam.sh" "$F/facecam.mp4" 0.66 "$F/_t_face916.mp4"
ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$F/_t_face916.mp4"
```

- [ ] **Step 2: Run to verify it fails** — Expected: FAIL.

- [ ] **Step 3: Implement `reframe_facecam.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
IN="${1:?in}"; CX="${2:?center_x 0..1}"; OUT="${3:?out}"
read IW IH < <(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$IN" | tr ',' ' ')

# desired 9:16 crop width from full height
CW=$(python -c "import math;h=$IH;w=int(round(h*9/16));print(w-(w%2))")
if [ "$CW" -le "$IW" ]; then
  # normal case: crop full-height 9:16 window centered on CX, clamped
  X=$(python -c "iw=$IW;cw=$CW;cx=$CX;x=int(round(iw*cx-cw/2));print(max(0,min(x,iw-cw)))")
  ffmpeg -y -i "$IN" -vf "crop=${CW}:${IH}:${X}:0,scale=1080:1920:flags=lanczos,setsar=1" \
    -c:v libx264 -pix_fmt yuv420p -c:a aac "$OUT"
else
  # source too narrow: scale to width 1080, pad to 1920 tall
  ffmpeg -y -i "$IN" -vf "scale=1080:-2,pad=1080:1920:0:(oh-ih)/2:color=black,setsar=1" \
    -c:v libx264 -pix_fmt yuv420p -c:a aac "$OUT"
fi
echo "$OUT"
```

- [ ] **Step 4: Run to verify it passes** — Expected: `1080,1920`.

- [ ] **Step 5: CHECKPOINT** — output is exactly 1080x1920; visually (Read a sampled frame) the "face" box sits inside the frame.

---

### Task 5: `reframe_gameplay.sh` — blurred-pad to 9:16

**Files:**
- Create: `scripts/reframe_gameplay.sh`

**Interfaces:**
- Consumes: `$1` in clip, `$2` out path.
- Produces: `$2` — `1080x1920`, source scaled to width 1080 centered, with a blurred cover copy filling top/bottom.

- [ ] **Step 1: Test harness**

```bash
S="C:/Users/micro/.claude/skills/long-video-to-shorts/scripts"
F="C:/Users/micro/.claude/skills/long-video-to-shorts/_fixtures"
bash "$S/reframe_gameplay.sh" "$F/gameplay.mp4" "$F/_t_game916.mp4"
ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$F/_t_game916.mp4"
```

- [ ] **Step 2: Run to verify it fails** — Expected: FAIL.

- [ ] **Step 3: Implement `reframe_gameplay.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
IN="${1:?in}"; OUT="${2:?out}"
ffmpeg -y -i "$IN" -filter_complex "\
[0:v]split=2[bg][fg];\
[bg]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,gblur=sigma=24[bg2];\
[fg]scale=1080:-2:flags=lanczos[fg2];\
[bg2][fg2]overlay=(W-w)/2:(H-h)/2,setsar=1[v]" \
  -map "[v]" -map 0:a? -c:v libx264 -pix_fmt yuv420p -c:a aac "$OUT"
echo "$OUT"
```

- [ ] **Step 4: Run to verify it passes** — Expected: `1080,1920`.

- [ ] **Step 5: CHECKPOINT** — output 1080x1920; Read a sampled frame to confirm centered content over blurred bg.

---

### Task 6: `captions_burn.sh` — transcript slice → ASS karaoke → burn-in (gameplay branch)

**Files:**
- Create: `scripts/captions_burn.sh`
- Create: `scripts/ass_from_words.cjs`

**Interfaces:**
- Consumes: `$1` in 9:16 clip, `$2` transcript.json (full-video), `$3` clip start seconds, `$4` clip end seconds, `$5` out path, `$6` font path.
- Produces: `$5` — clip with burned centered word-group captions, active word highlighted. `ass_from_words.cjs` reads transcript with the field names recorded in `_fixtures/ENV_NOTES.md`, filters words in `[start,end]`, rebases to clip-relative time, groups 3–4 words/line, emits ASS with `\k` karaoke timing.

- [ ] **Step 1: Write `ass_from_words.cjs`** (uses schema from ENV_NOTES.md — adjust field accessors accordingly)

```js
// usage: node ass_from_words.cjs <transcript.json> <startSec> <endSec> <fontName> > out.ass
const fs = require('fs');
const [, , tp, s0, s1, fontName] = process.argv;
const start = parseFloat(s0), end = parseFloat(s1);
const data = JSON.parse(fs.readFileSync(tp, 'utf8'));
// transcribe.py emits a FLAT words[] array: {text,start,end} (see ENV_NOTES.md)
let words = (data.words || []).map(w => ({ t: (w.text || '').trim(), a: w.start, b: w.end }))
                              .filter(w => w.t);
words = words.filter(w => w.b > start && w.a < end)
             .map(w => ({ t: w.t, a: Math.max(0, w.a - start), b: Math.max(0, w.b - start) }));
const cs = x => { const c=Math.round(x*100); const h=Math.floor(c/360000); const m=Math.floor(c%360000/6000); const s=Math.floor(c%6000/100); const cc=c%100; return `${h}:${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}.${String(cc).padStart(2,'0')}`; };
const esc = t => t.replace(/[{}\\]/g,'');
// group 3-4 words per line
const lines = []; for (let i=0;i<words.length;i+=4) lines.push(words.slice(i,i+4));
let ass = `[Script Info]
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
WrapStyle: 2
[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Cap,${fontName},74,&H00FFFFFF,&H0000C8FF,&H00101010,&H99000000,1,0,1,5,2,2,60,60,300,1
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
`;
for (const grp of lines) {
  if (!grp.length) continue;
  const a = grp[0].a, b = grp[grp.length-1].b;
  const txt = grp.map(w => { const k = Math.max(1, Math.round((w.b - w.a) * 100)); return `{\\kf${k}}${esc(w.t)} `; }).join('');
  ass += `Dialogue: 0,${cs(a)},${cs(b)},Cap,,0,0,0,,${txt.trim()}\n`;
}
process.stdout.write(ass);
```

- [ ] **Step 2: Write test harness**

```bash
S="C:/Users/micro/.claude/skills/long-video-to-shorts/scripts"
F="C:/Users/micro/.claude/skills/long-video-to-shorts/_fixtures"
FONT="$(ls C:/Users/micro/.claude/skills/long-video-to-shorts/assets/fonts/*.ttf | head -1)"
# make a 9:16 gameplay clip first
bash "$S/reframe_gameplay.sh" "$F/gameplay.mp4" "$F/_t_g916.mp4"
bash "$S/captions_burn.sh" "$F/_t_g916.mp4" "$F/transcript_sample.json" 0 8 "$F/_t_gcap.mp4" "$FONT"
ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$F/_t_gcap.mp4"
```

- [ ] **Step 3: Run to verify it fails** — Expected: FAIL (captions_burn.sh missing).

- [ ] **Step 4: Implement `captions_burn.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
IN="${1:?in}"; TR="${2:?transcript.json}"; S0="${3:?start sec}"; S1="${4:?end sec}"; OUT="${5:?out}"; FONT="${6:?font ttf}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_ASS="${OUT%.mp4}.ass"
FONTNAME="$(basename "$FONT" .ttf)"
node "$HERE/ass_from_words.cjs" "$TR" "$S0" "$S1" "$FONTNAME" > "$TMP_ASS"
# fontsdir so libass finds the bundled ttf; escape path for the ass filter on Windows
FONTDIR="$(dirname "$FONT")"
ASS_ESC="$(echo "$TMP_ASS" | sed 's/\\/\//g; s/:/\\:/g')"
FDIR_ESC="$(echo "$FONTDIR" | sed 's/\\/\//g; s/:/\\:/g')"
ffmpeg -y -i "$IN" -vf "subtitles='${ASS_ESC}':fontsdir='${FDIR_ESC}'" \
  -c:v libx264 -pix_fmt yuv420p -c:a copy "$OUT"
echo "$OUT"
```

- [ ] **Step 5: Run to verify it passes** — Expected: `1080,1920`; Read a sampled frame (`ffmpeg -ss 2 -i _t_gcap.mp4 -vframes 1 f.png`) to confirm caption text is visible and centered.

- [ ] **Step 6: CHECKPOINT** — ASS generated from real transcript slice; captions burned; frame shows text. If the Windows path escaping for the `subtitles` filter misbehaves, document the working escape form in `references/captions-gameplay.md`.

---

### Task 7: `hook_title.sh` — optional top headline banner

**Files:**
- Create: `scripts/hook_title.sh`

**Interfaces:**
- Consumes: `$1` in 9:16 clip, `$2` title text, `$3` out path, `$4` font path.
- Produces: `$3` — same clip with a wrapped title banner in the top ~15%. Text pre-wrapped to ≤ ~18 chars/line (max 2 lines) in the script; drawn with a semi-opaque rounded box.

- [ ] **Step 1: Test harness**

```bash
S="C:/Users/micro/.claude/skills/long-video-to-shorts/scripts"
F="C:/Users/micro/.claude/skills/long-video-to-shorts/_fixtures"
FONT="$(ls C:/Users/micro/.claude/skills/long-video-to-shorts/assets/fonts/*.ttf | head -1)"
bash "$S/reframe_gameplay.sh" "$F/gameplay.mp4" "$F/_t_h916.mp4"
bash "$S/hook_title.sh" "$F/_t_h916.mp4" "Le vrai piège des débutants" "$F/_t_hook.mp4" "$FONT"
ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$F/_t_hook.mp4"
```

- [ ] **Step 2: Run to verify it fails** — Expected: FAIL.

- [ ] **Step 3: Implement `hook_title.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
IN="${1:?in}"; TITLE="${2:?title}"; OUT="${3:?out}"; FONT="${4:?font}"
# wrap to <=18 chars/line, max 2 lines (fold on spaces)
WRAP="$(printf '%s' "$TITLE" | fold -s -w 18 | head -2)"
FONT_ESC="$(echo "$FONT" | sed 's/\\/\//g; s/:/\\:/g')"
TXT_ESC="$(printf '%s' "$WRAP" | sed "s/'/\\\\\\\\'/g; s/:/\\\\:/g")"
ffmpeg -y -i "$IN" -vf "drawtext=fontfile='${FONT_ESC}':text='${TXT_ESC}':\
x=(w-text_w)/2:y=140:fontsize=58:fontcolor=white:line_spacing=12:\
box=1:boxcolor=black@0.55:boxborderw=28:borderw=2:bordercolor=black@0.8" \
  -c:v libx264 -pix_fmt yuv420p -c:a copy "$OUT"
echo "$OUT"
```

- [ ] **Step 4: Run to verify it passes** — Expected: `1080,1920`; Read a top-frame crop to confirm the banner text renders (accented chars intact).

- [ ] **Step 5: CHECKPOINT** — banner visible, French accents render correctly.

---

### Task 8: `build_clip.sh` — orchestrate one clip end-to-end

**Files:**
- Create: `scripts/build_clip.sh`

**Interfaces:**
- Consumes: project dir, and one clip's fields (via flags): `--start --end --kind --title --hook --face-cx --caption-mode --out`. Uses `work/source.mp4` and `work/transcript.json`.
- Produces: for `kind=screen`: full pipeline `cut → reframe_gameplay → captions_burn → (hook_title) → OUT`. For `kind=facecam` with `--caption-mode embedded`: `cut → reframe_facecam → OUT_reframed` and PRINTS a handoff line instructing the agent to run `embedded-captions` on `OUT_reframed`, then `hook_title`. With `--caption-mode ass` (facecam without matte): same as screen but face-crop.

- [ ] **Step 1: Test harness (screen branch, fully scriptable)**

```bash
S="C:/Users/micro/.claude/skills/long-video-to-shorts/scripts"
F="C:/Users/micro/.claude/skills/long-video-to-shorts/_fixtures"
PROJ="$F/_t_build"; rm -rf "$PROJ"; mkdir -p "$PROJ/work" "$PROJ/shorts"
cp "$F/gameplay.mp4" "$PROJ/work/source.mp4"
cp "$F/transcript_sample.json" "$PROJ/work/transcript.json"
bash "$S/build_clip.sh" "$PROJ" --start 00:00:01.0 --end 00:00:07.0 --kind screen \
  --title "Le vrai piège des débutants" --hook true --caption-mode ass \
  --out "$PROJ/shorts/01_test.mp4"
ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$PROJ/shorts/01_test.mp4"
```

- [ ] **Step 2: Run to verify it fails** — Expected: FAIL.

- [ ] **Step 3: Implement `build_clip.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
PROJ="${1:?project dir}"; shift
START=""; END=""; KIND="screen"; TITLE=""; HOOK="true"; FACE_CX="0.5"; CAPMODE="ass"; OUT=""
while [ $# -gt 0 ]; do case "$1" in
  --start) START="$2";shift 2;; --end) END="$2";shift 2;; --kind) KIND="$2";shift 2;;
  --title) TITLE="$2";shift 2;; --hook) HOOK="$2";shift 2;; --face-cx) FACE_CX="$2";shift 2;;
  --caption-mode) CAPMODE="$2";shift 2;; --out) OUT="$2";shift 2;; *) echo "unknown $1";exit 2;; esac; done
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$PROJ/work/source.mp4"; TR="$PROJ/work/transcript.json"
FONT="$(ls "$HERE/../assets/fonts/"*.ttf | head -1)"
TMP="$PROJ/work/_clip_$$"; mkdir -p "$TMP"

# seconds for caption windowing
to_sec(){ python -c "import sys;p=sys.argv[1].split(':');print(float(p[0])*3600+float(p[1])*60+float(p[2]))" "$1"; }
S0=$(to_sec "$START"); S1=$(to_sec "$END")

bash "$HERE/cut.sh" "$SRC" "$START" "$END" "$TMP/cut.mp4" >/dev/null

if [ "$KIND" = "facecam" ]; then
  bash "$HERE/reframe_facecam.sh" "$TMP/cut.mp4" "$FACE_CX" "$TMP/reframed.mp4" >/dev/null
else
  bash "$HERE/reframe_gameplay.sh" "$TMP/cut.mp4" "$TMP/reframed.mp4" >/dev/null
fi

if [ "$KIND" = "facecam" ] && [ "$CAPMODE" = "embedded" ]; then
  cp "$TMP/reframed.mp4" "${OUT%.mp4}_reframed.mp4"
  echo "HANDOFF: run embedded-captions on ${OUT%.mp4}_reframed.mp4, then hook_title.sh -> $OUT"
  exit 0
fi

# ASS caption path (screen, or facecam-without-matte)
bash "$HERE/captions_burn.sh" "$TMP/reframed.mp4" "$TR" "$S0" "$S1" "$TMP/capped.mp4" "$FONT" >/dev/null

if [ "$HOOK" = "true" ] && [ -n "$TITLE" ]; then
  bash "$HERE/hook_title.sh" "$TMP/capped.mp4" "$TITLE" "$OUT" "$FONT" >/dev/null
else
  cp "$TMP/capped.mp4" "$OUT"
fi
rm -rf "$TMP"
echo "$OUT"
```

- [ ] **Step 4: Run to verify it passes** — Expected: `shorts/01_test.mp4` is 1080x1920 with captions + hook banner.

- [ ] **Step 5: Test the facecam+embedded handoff branch**

```bash
bash "$S/build_clip.sh" "$PROJ" --start 00:00:01.0 --end 00:00:06.0 --kind facecam \
  --caption-mode embedded --face-cx 0.66 --out "$PROJ/shorts/02_face.mp4"
```
Expected: prints a `HANDOFF:` line and writes `02_face_reframed.mp4` (1080x1920), exit 0.

- [ ] **Step 6: CHECKPOINT** — screen branch produces a finished short; facecam-embedded branch produces the reframed clip + handoff instruction.

---

### Task 9: `clips.schema.json` + reference docs

**Files:**
- Create: `clips.schema.json`
- Create: `references/highlight-selection.md`
- Create: `references/reframe.md`
- Create: `references/captions-gameplay.md`
- Create: `references/troubleshooting.md`

**Interfaces:**
- Produces: the `clips.json` contract (matches DESIGN.md §6) and the doctrine docs the agent reads during the PICK and BUILD stages.

- [ ] **Step 1: Write `clips.schema.json`** (JSON Schema draft-07)

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "clips.json",
  "type": "object",
  "required": ["source", "language", "clips"],
  "properties": {
    "source": { "type": "string" },
    "language": { "type": "string", "default": "fr" },
    "clips": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "start", "end", "kind", "title"],
        "properties": {
          "id": { "type": "string" },
          "start": { "type": "string", "pattern": "^\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?$" },
          "end": { "type": "string", "pattern": "^\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?$" },
          "kind": { "enum": ["facecam", "screen"] },
          "title": { "type": "string" },
          "hook": { "type": "boolean", "default": true },
          "reason": { "type": "string" },
          "face_center_x": { "type": "number", "minimum": 0, "maximum": 1 },
          "caption_identity": { "type": "string" }
        }
      }
    }
  }
}
```

- [ ] **Step 2: Write `references/highlight-selection.md`**

Content (real rubric, not placeholder): scoring dimensions — Hook (opens with a question/claim in first ~3s), Self-containment (no "as I said earlier"/dangling pronouns), Payoff (punchline, reveal, tension→release), Emotion/energy, Clip length 12–60s snapping to sentence boundaries. Procedure: read `work/transcript.json`; mark candidate windows by sentence spans; score each 0–3 on the dimensions; keep everything ≥ threshold; write `clips.json`; present a table (id, range, title, reason) for user approval. Rule: never start/end mid-sentence; extend to the nearest sentence boundary using word timestamps.

- [ ] **Step 3: Write `references/reframe.md`**

Content: the 9:16 window math (`crop_w = height*9/16`, clamp x), how the agent sets `face_center_x` (sample `ffmpeg -ss <mid> -i clip -vframes 1 f.png`, Read it, estimate face center as fraction of width), gameplay blurred-pad rationale, and the "already portrait" fallback. Include the exact ffmpeg commands from Tasks 4–5.

- [ ] **Step 4: Write `references/captions-gameplay.md`**

Content: ASS style spec (font size 74, white fill, amber active-word via `\kf`, outline 5, bottom-third margin 300), the working Windows path-escaping form for the `subtitles` filter (as verified in Task 6), and how to tweak grouping (words per line).

- [ ] **Step 5: Write `references/troubleshooting.md`**

Content: FR Whisper model resolution (the verified command from ENV_NOTES.md), silent-audio hallucination guard (refuse), source already has burned captions (refuse/skip embed), hard-cut/multi-speaker facecam (split or fall back to ASS captions), yt-dlp missing (`python -m pip install -U yt-dlp`), accented text in drawtext (fontfile must support Latin-1; use bundled Inter/DejaVu).

- [ ] **Step 6: CHECKPOINT** — schema validates the DESIGN.md example clip; all four references contain concrete commands (grep them for `ffmpeg`/`transcribe`), no "TODO".

---

### Task 10: `SKILL.md` — doctrine, flow, decision gate, invocation

**Files:**
- Create: `SKILL.md`

**Interfaces:**
- Consumes: all scripts + references above.
- Produces: the entry document with YAML frontmatter (name/description/triggers) that routes a "make shorts from this long video" request into the 6-stage flow.

- [ ] **Step 1: Write frontmatter + trigger description**

`name: long-video-to-shorts`; description covering triggers: "make shorts / clips from a long video", "faire des shorts / clips à partir d'une vidéo", "Opus Clip", "reels from a video", "découper une vidéo en clips verticaux". State: local, French default, two branches.

- [ ] **Step 2: Write the operational flow (TL;DR pipeline)**

The 6 stages with exact commands per stage:
1. `bash scripts/intake.sh <file-or-url> <project>`
2. `bash scripts/probe.sh <project>` → Read the contact sheet → classify facecam/screen per region
3. `python scripts/transcribe.py <project>/work/source.mp4 <project>/work/transcript.json --lang fr --model small` (set `HF_HUB_DISABLE_SYMLINKS_WARNING=1`; use `--model medium` for hard audio)
4. Read `references/highlight-selection.md`; read transcript; write `<project>/work/clips.json`; present the table → **USER GATE**
5. For each approved clip: `bash scripts/build_clip.sh <project> --start .. --end .. --kind .. --title .. --hook .. --face-cx .. --caption-mode .. --out <project>/shorts/NN_slug.mp4`. For facecam: after the reframed handoff, run the **`embedded-captions`** skill on `*_reframed.mp4`, then `scripts/hook_title.sh`.
6. Write `<project>/shorts/manifest.md` (per short: title, range, hook, suggested hashtags).

- [ ] **Step 3: Write the decision gate + rules**

Refuse/split conditions (from DESIGN.md §11 + troubleshooting.md). Caption-mode routing: facecam→embedded (default), screen→ass. Face-center via agent vision. Never ship fabricated captions over silence.

- [ ] **Step 4: Write an end-to-end example**

A worked example: input `interview.mp4` (facecam) → 4 shorts, showing the clips.json and the exact build commands, ending in `shorts/` + manifest.

- [ ] **Step 5: CHECKPOINT (full dry run)**

Run the whole pipeline on a fixture as an integration test:
```bash
P="C:/Users/micro/.claude/skills/long-video-to-shorts/_fixtures/_t_e2e"; rm -rf "$P"; mkdir -p "$P"
S="C:/Users/micro/.claude/skills/long-video-to-shorts/scripts"
bash "$S/intake.sh" "C:/Users/micro/.claude/skills/long-video-to-shorts/_fixtures/gameplay.mp4" "$P"
bash "$S/probe.sh" "$P"
HF_HUB_DISABLE_SYMLINKS_WARNING=1 python "$S/transcribe.py" "$P/work/source.mp4" "$P/work/transcript.json" --lang fr --model small
# hand-author a 1-clip clips.json, then:
bash "$S/build_clip.sh" "$P" --start 00:00:01.0 --end 00:00:07.0 --kind screen \
  --title "Test bout en bout" --hook true --caption-mode ass --out "$P/shorts/01.mp4"
ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$P/shorts/01.mp4"
```
Expected: `shorts/01.mp4` is 1080x1920 with captions + hook. This proves the screen branch end-to-end.

- [ ] **Step 6: CHECKPOINT** — SKILL.md complete; integration dry run produces a finished short.

---

## Self-Review

**Spec coverage:** DESIGN.md §4 flow → Tasks 1–8 + SKILL.md (T10); §5 branches → T4/T5 (reframe), T6 (gameplay captions), T8 + SKILL.md (facecam→embedded handoff); §6 clips.json → T9 schema; §7 structure → all tasks create the listed files; §8 agent responsibilities → references (T9); §9 defaults → SKILL.md + build_clip flags; §10 deps incl. FR-Whisper risk → **T0 Step 5 (gated)** + yt-dlp check in T1; §11 failure handling → troubleshooting.md (T9) + SKILL.md gate (T10). No uncovered section.

**Placeholder scan:** No "TBD/TODO". The one deliberate adjustable is `ass_from_words.cjs` field accessors, explicitly tied to the schema recorded in T0's `ENV_NOTES.md` — a real dependency, not a placeholder.

**Type consistency:** `work/source.mp4`, `work/transcript.json`, `work/clips.json` names consistent across T1/T2/T3/T8/T10. `build_clip.sh` flags (`--start/--end/--kind/--title/--hook/--face-cx/--caption-mode/--out`) match SKILL.md stage-5 invocation. `face_center_x` (schema) → `--face-cx` (flag) mapping stated in T8/T10. Output always 1080x1920 across T4/T5/T6/T7/T8.

**Note on TDD adaptation:** shell scripts are verified by running them on `_fixtures/` and asserting output via `ffprobe` + occasional frame Reads; "commit" steps are CHECKPOINTS (no git repo here).
