# Design — `long-video-to-shorts`

**Date:** 2026-07-15
**Status:** Approved (brainstorming complete) → next: implementation plan
**Owner skill dir:** `C:\Users\micro\.claude\skills\long-video-to-shorts\`

## 1. Purpose

Turn ONE long video into N short 9:16 captioned clips ("shorts"), fully local and
free — a home-made Opus Clip. The human stays in the loop at exactly one gate:
they approve the selected moments before any expensive render.

Non-goals (YAGNI): no cloud services, no paid APIs, no virality-score ML model
(the agent judges moments directly), no multi-speaker diarization, no per-frame
face tracking.

## 2. Inputs & outputs

- **Input:** a local video file (`.mp4/.mov/.mkv/...`) OR a YouTube URL.
- **Output:** `shorts/` folder with `NN_slug.mp4` (9:16, ≤ 60s, captioned) +
  `manifest.md` (per short: title/hook, time range, suggested caption + hashtags).

## 3. Confirmed decisions

| Topic | Decision |
|---|---|
| Content types | Face-cam **and** screen/gameplay (two render branches) |
| Face-cam reframe | Fixed 9:16 smart-crop; face located by the AGENT's own vision on a sampled frame (no OpenCV/mediapipe — nothing to break on Python 3.14) |
| Gameplay reframe | Full 16:9 centered + blurred vertical pad to fill 9:16 (nothing cropped) |
| Language | French by default (`whisper -l fr`); auto-switch to EN when detected |
| Output volume | As many shorts as genuinely hold up; each ≤ 60s; user approves the shortlist first |
| Hook title | ON by default — short punchy headline banner at top of each short; editable/removable per clip |
| Intake | Local files **and** YouTube URLs (via `yt-dlp`) |

## 4. Pipeline (6 stages)

```
1. INTAKE     yt-dlp if URL else copy → normalize to work/source.mp4
2. PROBE      ffprobe + 1fps contact sheet → AGENT classifies regions facecam|screen
3. TRANSCRIBE hyperframes transcribe -l fr → work/transcript.json (word-level)
4. PICK       AGENT reads transcript → proposes shortlist → writes clips.json
              ⏸ USER GATE: keep / drop / adjust ranges & titles
5. BUILD      per approved clip: cut → reframe(9:16) → captions → (hook) → shorts/NN.mp4
6. DELIVER    manifest.md with titles, ranges, hooks, hashtag suggestions
```

## 5. Render branches (stage 5)

|  | Face-cam | Screen / gameplay |
|---|---|---|
| Reframe | `reframe_facecam.sh`: crop 9:16 window at `face_center_x` | `reframe_gameplay.sh`: scale 16:9 to width, blurred copy as top/bottom pad |
| Captions | Hand the 9:16 clip to the **`embedded-captions`** skill (subject matte + animated captions; identity chosen by agent, overridable) | `captions_burn.sh`: slice transcript → ASS karaoke (centered word group, active word highlighted) → ffmpeg burn-in (no subject to matte) |
| Hook title | `hook_title.sh`: optional top banner, drawtext/ASS | same |

**Ordering for face-cam:** reframe to 9:16 FIRST, then run `embedded-captions` on
the vertical clip so matte + captions are authored in the final frame.

## 6. `clips.json` contract

Schema file: `clips.schema.json`. Shape:

```json
{
  "source": "work/source.mp4",
  "language": "fr",
  "clips": [
    {
      "id": "01",
      "start": "00:04:12.0",
      "end": "00:04:58.5",
      "kind": "facecam",
      "title": "Le vrai piège des débutants",
      "hook": true,
      "reason": "moment autonome, punchline à 4:51, forte tension",
      "face_center_x": 0.62,
      "caption_identity": "anchor"
    }
  ]
}
```

- `kind`: `facecam` | `screen`.
- `face_center_x`: 0..1 fraction of source width (facecam only).
- `caption_identity`: an `embedded-captions` CATALOG id (facecam only); gameplay ignores it.
- `hook`: whether to render the top title banner (default true).

## 7. Skill file structure

```
long-video-to-shorts/
├── SKILL.md                    # doctrine, flow, decision gate, rules, invocation
├── DESIGN.md                   # this document
├── clips.schema.json           # clips.json contract
├── references/
│   ├── highlight-selection.md  # rubric the agent uses to score/pick moments
│   ├── reframe.md              # ffmpeg crop/pad recipes + 9:16 window math
│   ├── captions-gameplay.md    # ASS karaoke style spec + burn-in command
│   └── troubleshooting.md      # FR whisper model, silent audio, hard cuts, etc.
├── scripts/
│   ├── intake.sh               # yt-dlp if URL else copy; produce work/source.mp4
│   ├── probe.sh                # ffprobe + 1fps contact sheet for classification
│   ├── cut.sh                  # extract precise [start,end] segment (re-encode)
│   ├── reframe_facecam.sh      # crop 9:16 at given x-center
│   ├── reframe_gameplay.sh     # scale + blurred pad to 9:16
│   ├── captions_burn.sh        # transcript slice → ASS karaoke → ffmpeg burn
│   ├── hook_title.sh           # optional top title banner
│   └── build_clip.sh           # orchestrate cut→reframe→captions→hook for one clip
├── assets/
│   └── fonts/                  # free fonts for gameplay captions + hook banner
└── ...
```

## 8. Agent responsibilities (documented in references/)

- **Moment selection** (`highlight-selection.md`): prefer segments that (a) open with
  a hook in the first ~3s, (b) are self-contained (no dangling references), (c) carry
  a punchline / tension / payoff, (d) don't cut mid-reference. Score, then propose.
- **Face / action location:** sample frames with ffmpeg, look at them, set
  `face_center_x` (facecam) or the crop/pad choice (screen).
- **Caption identity:** recommend one from the `embedded-captions` CATALOG; user can override.
- **Titles/hooks:** write short, punchy FR headlines.

## 9. Defaults & configurables

- Language: `fr` default; agent may set `en` per source when clearly English.
- Duration cap: 60s per short (hard). Min useful length ~12s.
- Volume: no fixed count — every segment that holds up, agent lists all, user trims.
- Hook banner: on by default, per-clip `hook:false` to disable.

## 10. Dependencies

- **Present & verified:** ffmpeg 8.1.1, ffprobe, node 24, `hyperframes` CLI 0.7.58
  (provides `transcribe`), `embedded-captions` skill installed locally.
- **To install at build time:** `yt-dlp` (intake from URL).
- **RISK to resolve as task #1:** French Whisper model. `hyperframes transcribe`
  advertises mostly `.en` models + `large-v3` (multilingual). Verify `transcribe -l fr`
  actually produces French; if only English models are present, install the multilingual
  ggml model (e.g. `large-v3` or a multilingual `small`) so FR transcription works.
  Fallback: `large-v3` multilingual. Not blocking, but gated before the build proceeds.

## 11. Failure handling / decision gate (inherited from embedded-captions rules)

Refuse or split when: multiple speakers with hard cuts (facecam captions), no speech /
near-silent audio (Whisper hallucination), source already has burned-in captions,
transcript is gibberish. Surface these to the user rather than shipping fabricated captions.
