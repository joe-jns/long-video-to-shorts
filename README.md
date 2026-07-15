# long-video-to-shorts

Turn **one long video into several vertical (9:16) captioned shorts** — a home-made
Opus Clip that runs **100% locally and free**. It's a [Claude Code](https://claude.com/claude-code)
skill: the agent transcribes the video, picks the strongest moments, and — after you
approve the shortlist — cuts, reframes to 9:16, and captions each clip.

https://github.com/joe-jns/long-video-to-shorts

## What it does

```
1. INTAKE      local file OR YouTube URL            -> work/source.mp4
2. PROBE       ffprobe + a 1fps contact sheet       -> the agent classifies facecam vs screen
3. TRANSCRIBE  faster-whisper (word-level)          -> work/transcript.json
4. PICK        the agent reads the transcript, proposes a shortlist -> you approve
5. BUILD       per clip: cut -> reframe(9:16) -> captions -> hook  -> shorts/NN.mp4
6. DELIVER     shorts/ + a manifest.md (titles, ranges, hashtag ideas)
```

Two content branches:

| | Face-cam | Screen / gameplay |
|---|---|---|
| Reframe | fixed 9:16 crop centered on the face (the agent locates it by vision — no ML) | full frame + blurred vertical pad |
| Captions | **word-pop** burned captions (active word scales up + turns yellow) | same |

### Caption + hook style

- **Word-pop captions**: single line (never wraps), fixed vertical anchor (never jumps),
  the currently-spoken word scales to 122% and turns yellow. Non-overlapping.
- **Hook title**: top-center, no box, big bold with outline + shadow, one accent word in
  yellow (mark it in the title with `*asterisks*`), shown ~4s then it disappears.

## Customization — `config.json`

All look-and-feel lives in `config.json` (no code edits):

```jsonc
{
  "caption_style": "word-pop",   // word-pop | capcut | clean | label | karaoke | one-word | boxed | bicolor
  "accent_color": "#FFFF00",     // brand colour for the popped word + hook accent
  "font": "assets/fonts/DejaVuSans-Bold.ttf",
  "font_family": "DejaVu Sans",  // set to the font's real family name if you swap it
  "hook_seconds": 4,             // how long the hook stays (2–6s)
  "max_download_height": 1080,   // cap YouTube downloads — 1080 is plenty; never pulls 4K
  "caption_pos_y": 1360,
  "hook_pos_y": 175,
  "safe_zone": { "top": 120, "bottom": 320, "left": 70, "right": 130 }
}
```

- **8 caption styles**, switchable in config or per clip: `build_clip.sh --style capcut`.
- **Your brand colour**: set `accent_color` (hex) — it drives both the captions and the hook.
- **Any font**: drop a `.ttf` in `assets/fonts/`, set `font` + `font_family`.
- **Platform-safe placement**: `safe_zone` keeps captions/hook clear of the TikTok/Reels
  UI (right-side buttons, bottom bar); positions are auto-clamped inside it.

### Interactive configurator (optional companion command)

Instead of editing `config.json` by hand, install the companion skill in
[`long-video-to-shorts-config/`](long-video-to-shorts-config/) — copy that folder to
`~/.claude/skills/long-video-to-shorts-config/` and run **`/long-video-to-shorts-config`**.
It asks you (keep-or-change) for the caption style, brand accent colour, font (with an
option to download a short-friendly Google font), and hook duration, then writes
`config.json` for you and can render a quick preview.

## Requirements

- [Claude Code](https://claude.com/claude-code) (this is a skill)
- **ffmpeg / ffprobe** (8.x recommended)
- **Node.js** (18+)
- **Python 3.9+** with **faster-whisper**: `python -m pip install -U faster-whisper`
- **yt-dlp** (only for URL intake): `python -m pip install -U yt-dlp`
- A bold TTF with full accent coverage — `assets/fonts/DejaVuSans-Bold.ttf` is bundled.

First run downloads a Whisper model (`small` ≈ 484 MB) to `~/.cache/huggingface`.

> Built and tested on Windows (Git Bash) with Python 3.14 + ffmpeg 8.1. The scripts are
> POSIX `bash`; they work anywhere bash + ffmpeg are available.

## Install

Drop this folder into your Claude Code skills directory:

```
~/.claude/skills/long-video-to-shorts/
```

Then just ask Claude Code: *"make shorts from this video"* (a file or a YouTube URL).

## Manual usage (without the agent)

```bash
P=~/jobs/myvideo
bash scripts/intake.sh <file-or-URL> "$P"
bash scripts/probe.sh "$P"
python scripts/transcribe.py "$P/work/source.mp4" "$P/work/transcript.json" --lang en --model small
# author a clips.json (see clips.schema.json), then per clip:
bash scripts/build_clip.sh "$P" \
  --start 00:01:03.9 --end 00:01:52.3 --kind facecam \
  --title "The *screen* trick for beginners" --hook true --caption-mode ass --face-cx 0.5 \
  --out "$P/shorts/01_screen-trick.mp4"
```

## Layout

- `SKILL.md` — the agent entry point (doctrine, flow, decision gate)
- `scripts/` — the pipeline (intake, probe, transcribe, cut, reframe, captions, hook, orchestrator)
- `references/` — how the agent selects moments, reframe math, caption/hook style, troubleshooting
- `clips.schema.json` — the shortlist contract
- `DESIGN.md` / `PLAN.md` — how it was designed and built

## Notes / gotchas

- Transcription uses **faster-whisper**, not any hosted API — nothing leaves your machine.
- The ffmpeg `subtitles` filter chokes on Windows drive-colon paths; the scripts sidestep
  it by running ffmpeg from inside a temp dir with relative paths.
- Fonts: [DejaVu Sans](https://dejavu-fonts.github.io/) (Bitstream Vera license, redistributable).

## License

MIT — see [LICENSE](LICENSE).
