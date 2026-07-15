# ENV_NOTES — verified facts (2026-07-15)

## Transcription backend (RESOLVED — plan revision)

`hyperframes transcribe` requires **whisper-cpp**, which is NOT built on this machine
(needs cmake). `hyperframes tts` requires **kokoro-onnx**, also not installed.

**Decision:** the skill uses its own **`scripts/transcribe.py`** backed by
**faster-whisper** (CTranslate2). Verified working on **Python 3.14.6**:

```
python -m pip install faster-whisper   # installs clean (only an unrelated click warning)
python scripts/transcribe.py <input> <out.json> --lang fr --model small
```

- French detected with probability 1.0 on the SAPI fixture; word-level timestamps produced.
- Model `small` (~484 MB) auto-downloads to `~/.cache/huggingface` on first run.
  Set `HF_HUB_DISABLE_SYMLINKS_WARNING=1` to silence the Windows symlink warning.
- For higher French accuracy on hard audio, use `--model medium` or `--model large-v3`.

## transcript.json schema (what ass_from_words.cjs / captions read)

```json
{
  "language": "fr",
  "language_probability": 1.0,
  "duration": 10.5,
  "words":    [{"text": "Bonjour,", "start": 0.0, "end": 0.68}, ...],
  "segments": [{"start": 0.0, "end": 2.4, "text": "Bonjour, ceci est un test."}, ...]
}
```

Word field names are **`text` / `start` / `end`** (flat `words[]` array — no nested
`segments[].words`). `ass_from_words.cjs` reads `data.words[]` directly.

## Fixtures (in this dir)

- `fr_speech.wav` — French speech via Windows SAPI voice **Microsoft Hortense Desktop**
  (`Add-Type System.Speech`; kokoro TTS was unavailable). ~10s, mono.
- `facecam.mp4` — 1920x1080, 8s, synthetic "face" box right-of-center (~x=0.66) + FR audio.
- `gameplay.mp4` — 1920x1080, 8s, `testsrc2` moving pattern + FR audio.
- `transcript_sample.json` — real faster-whisper output for `fr_speech.wav` (23 words).

## Tooling confirmed present

- ffmpeg / ffprobe 8.1.1 (Gyan full build)
- node v24.17.0
- python 3.14.6 + faster-whisper (installed)
- curl 8.19.0
- Font: `assets/fonts/DejaVuSans-Bold.ttf` (downloaded, full Latin accent coverage)

## TTS for fixtures (Windows-native, no pip)

```powershell
Add-Type -AssemblyName System.Speech
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
$s.SelectVoice("Microsoft Hortense Desktop")
$s.SetOutputToWaveFile("fr_speech.wav")
$s.Speak("...texte francais...")
$s.Dispose()
```
