#!/usr/bin/env bash
# Transcribe an audio/video file to text, fully locally (mlx-whisper on Apple Silicon).
# Usage: transcribe.sh [file] [--lang xx] [--translate] [--srt] [--model NAME]
set -euo pipefail

MODEL="mlx-community/whisper-large-v3-turbo"
MODEL_EXPLICIT=0
LANG=""
TASK="transcribe"
FORMAT="txt"
SRC=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang) LANG="$2"; shift 2 ;;
    --translate) TASK="translate"; shift ;;
    --srt) FORMAT="srt"; shift ;;
    --model) MODEL="$2"; MODEL_EXPLICIT=1; shift 2 ;;
    -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
    *) SRC="$1"; shift ;;
  esac
done

# No file given: take the newest audio/video in Downloads or Desktop (last 2 days).
if [[ -z "$SRC" ]]; then
  SRC=$(find "$HOME/Downloads" "$HOME/Desktop" -maxdepth 1 -type f -mtime -2 \
    \( -iname '*.ogg' -o -iname '*.oga' -o -iname '*.opus' -o -iname '*.m4a' -o -iname '*.mp3' \
       -o -iname '*.wav' -o -iname '*.aac' -o -iname '*.mp4' -o -iname '*.mov' -o -iname '*.amr' \
       -o -iname '*.aiff' -o -iname '*.flac' -o -iname '*.webm' \) \
    -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -1)
  [[ -n "$SRC" ]] || { echo "no audio file given and none found in ~/Downloads or ~/Desktop" >&2; exit 1; }
  echo "picked: $SRC" >&2
fi

[[ -f "$SRC" ]] || { echo "not a file: $SRC" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg missing: brew install ffmpeg" >&2; exit 1; }
command -v uvx    >/dev/null || { echo "uvx missing: brew install uv" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
BASE=$(basename "${SRC%.*}")

ffmpeg -loglevel error -y -i "$SRC" -ar 16000 -ac 1 -c:a pcm_s16le "$WORK/in.wav"

DUR=$(ffprobe -loglevel error -show_entries format=duration -of csv=p=0 "$WORK/in.wav" 2>/dev/null || echo 0)
printf 'source: %s\nduration: %.0fs\n' "$SRC" "$DUR" >&2

# large-v3-turbo is distilled for transcription only and silently returns the source
# language on a translate task; fall back to full large-v3 when translating.
if [[ "$TASK" == "translate" && "$MODEL" == *"turbo"* && "$MODEL_EXPLICIT" == "0" ]]; then
  MODEL="mlx-community/whisper-large-v3-mlx"
  echo "translate: switching to $MODEL (turbo cannot translate)" >&2
fi

ARGS=(--model "$MODEL" --task "$TASK" --output-dir "$WORK" --output-format "$FORMAT" --verbose False)
[[ -n "$LANG" ]] && ARGS+=(--language "$LANG")

uvx --from mlx-whisper mlx_whisper "$WORK/in.wav" "${ARGS[@]}" >&2

OUT="$HOME/Downloads/${BASE}.${FORMAT}"
cp "$WORK/in.${FORMAT}" "$OUT"
echo "saved: $OUT" >&2
echo "--- TRANSCRIPT ---"
cat "$OUT"
