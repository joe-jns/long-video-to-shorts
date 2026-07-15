#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

# 1) French speech (~8s) via hyperframes tts (French voice ff_siwis)
npx --no-install hyperframes tts "Bonjour, ceci est un test. Voici le vrai piège des débutants en montage vidéo." \
  -v ff_siwis -l fr-fr -o fr_speech.wav || echo "TTS failed — will fall back to silent audio"

# audio input: tts wav if present else anullsrc
if [ -f fr_speech.wav ]; then AUD=(-i fr_speech.wav)
else AUD=(-f lavfi -i anullsrc=r=44100:cl=stereo); fi

# 2) facecam fixture: 1920x1080, a centered "face" (skin box + eyes) shifted right of center
ffmpeg -y -f lavfi -i "color=c=0x223344:s=1920x1080:d=8:r=30" "${AUD[@]}" \
  -filter_complex "[0:v]drawbox=x=1120:y=340:w=360:h=360:color=0xE0B080:t=fill,\
drawbox=x=1200:y=470:w=40:h=40:color=black:t=fill,drawbox=x=1360:y=470:w=40:h=40:color=black:t=fill[v]" \
  -map "[v]" -map 1:a -shortest -c:v libx264 -pix_fmt yuv420p -c:a aac facecam.mp4

# 3) gameplay fixture: 1920x1080 moving test pattern
ffmpeg -y -f lavfi -i "testsrc2=s=1920x1080:d=8:r=30" "${AUD[@]}" \
  -map 0:v -map 1:a -shortest -c:v libx264 -pix_fmt yuv420p -c:a aac gameplay.mp4

echo "Fixtures ready:"; ls -la facecam.mp4 gameplay.mp4 fr_speech.wav 2>/dev/null || true
