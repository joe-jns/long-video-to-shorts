# Gameplay / screen captions (ASS karaoke burn-in)

The `embedded-captions` skill needs a human subject to matte, so it does **not**
apply to screen/gameplay. For those we burn clean karaoke captions with ffmpeg
via `captions_burn.sh` → `ass_from_words.cjs`.

## Pipeline

```
ass_from_words.cjs  transcript.json + [startSec,endSec] -> subs.ass
captions_burn.sh    burn subs.ass into the 9:16 clip
```

`ass_from_words.cjs` reads the FLAT `words[]` array (`{text,start,end}`), keeps
words inside `[start,end]`, rebases them to clip-relative time, and emits the
**word-pop** style: words are packed into **single lines** by a character budget
(`build_clip.sh` passes ~16), and each word gets its own "active" state where it
**scales up (122%) and turns yellow** while spoken. Consecutive captions never
overlap (each state ends exactly when the next begins).

## Style (edit in `ass_from_words.cjs`)

- Font family **DejaVu Sans**, Bold, size **84**, white fill, black outline 6, shadow 3.
- Active-word colour yellow `&H0000FFFF`; active word `\fscx122\fscy122`.
- **Fixed vertical anchor** `{\an5\pos(540,1360)}` on every caption → no vertical
  jump, and single-line packing (`packByChars`, budget ~16, max 3 words) → never
  wraps. These two together are what keep the captions rock-steady.
- To reposition, change the `\pos(540, Y)` Y value. To change accent colour, edit
  `YELLOW`. To allow longer lines, raise the `maxChars` arg from `build_clip.sh`.

## Hook banner (`hook_title.sh` → `hook_ass.cjs`)

"Clean" style (H2), ASS-based: **top-CENTER aligned**, **no box**, big bold white
(size 88), thick black outline + soft shadow, wrapped to ≤16 chars/line (max 2 lines).

- **Accent word:** mark the main word with `*asterisks*` in the title, e.g.
  `"Feeling awkward is *normal*"` → `normal` renders in yellow (matches the caption
  accent). Pass marked titles via `build_clip.sh --title`.
- **Timed:** the hook shows for ~4s then disappears (5th arg to `hook_title.sh`,
  clamped 2–6s; default 4). It is NOT on screen for the whole clip.

## Windows path gotcha (SOLVED — don't reintroduce)

The ffmpeg `subtitles` filter fails on drive-colon paths (`C:/...`). Do **not**
try to escape the colon. `captions_burn.sh` instead copies the `.ass` + font into
a temp dir and runs ffmpeg from **inside** it with relative paths
(`subtitles=subs.ass:fontsdir=.`). The libass line
`Error opening memory font 'subs.ass'` is a harmless quirk — as long as you see
`fontselect: (DejaVu Sans, 700, 0) -> DejaVuSans-Bold`, the font loaded.

## Font family override

`captions_burn.sh` passes family `DejaVu Sans` (env `CAPTION_FONT_FAMILY` to
override). If you swap the bundled font, set this to the new font's **family**
name (not the filename), and keep a matching `.ttf` in `assets/fonts/`.

## Tuning

- Words per line: `build_clip.sh` passes `3`; raise to 4 for denser captions.
- To reposition, change `MarginV` in the style line.
