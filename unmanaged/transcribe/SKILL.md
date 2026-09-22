---
name: transcribe
description: Transcribe a voice message, audio file, or video's audio to text locally, then report what was actually asked. Use when the user has a voice note, audio message, recording, meeting audio, or video to turn into text, or says "transcribe this", "what does this audio say", "my manager sent a voice message". Runs entirely on-device — no upload, no API key.
---

# Transcribe audio to text

Turns an audio/video file into text on-device with `mlx-whisper`, then reports the
**asks** before the transcript — the point is that the user does not have to re-listen
to find what they were told to do.

## Run it

```sh
~/.claude/skills/transcribe/transcribe.sh <file>
```

With no file argument it picks the newest audio/video from `~/Downloads` or `~/Desktop`
(last 2 days) — that is the normal case for a voice message just saved off a messenger.

Flags:
- `--lang ru` — skip auto-detect; use when the speaker's language is known (faster, more accurate on short clips)
- `--translate` — transcribe non-English speech straight into English (auto-switches off the
  turbo model, which is distilled for transcription and silently returns the source language)
- `--srt` — timestamped subtitles instead of plain text (use for long recordings the user will want to seek in)
- `--model mlx-community/whisper-large-v3` — slower, slightly better; the default `-turbo` is right for voice messages

The script writes the result next to the source in `~/Downloads/<name>.txt` and prints it
after a `--- TRANSCRIPT ---` marker. First run ever downloads the model (~1.5 GB, cached
afterwards); later runs are faster than real time.

## How to report the result

Whisper output is a wall of unpunctuated-ish prose. Do not just paste it back. Answer in
this order:

1. **Asks** — every request, commitment, or deadline directed at the user, as a checklist.
   Quote the deadline verbatim when one is stated. If the audio contains no ask, say so
   explicitly rather than inventing one.
2. **Everything else worth keeping** — decisions, numbers, names, context. Skip filler.
3. **Full transcript** — lightly cleaned (paragraph breaks, obvious filler words dropped).
   Never reword the substance; if a passage is garbled, mark it `[unclear]` instead of guessing.

For a recording over ~10 minutes, put the transcript in a file and reference it rather
than printing the whole thing.

## Notes

- Works on any format ffmpeg reads: `.ogg`/`.opus` (Telegram, WhatsApp), `.m4a` (iPhone,
  Voice Memos), `.amr`, `.mp3`, `.mp4`, `.mov`.
- No speaker diarization. For a two-person recording, attribute only where the audio makes
  it obvious, and say the transcript is unlabeled.
- Accented or fast speech in a second language transcribes noticeably better with `--lang`
  set explicitly.
