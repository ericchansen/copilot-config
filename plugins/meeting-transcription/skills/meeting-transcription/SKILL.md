---
name: meeting-transcription
description: Locally transcribe recorded meetings, diarize and identify speakers, and create Google-Docs-ready meeting notes with decisions and owner-specific action items. Use for meeting videos or audio, speaker-attributed transcripts, meeting summaries, and minutes.
license: MIT
allowed-tools: PowerShell
---

# Meeting transcription and notes

Use the bundled local pipeline for recorded meetings. Media, access tokens, model
files, and inference stay on the user's machine.

Resolve every script path relative to this `SKILL.md` file. Do not assume that the
skill is installed under a particular Copilot, Claude, Codex, or opencode directory.
In the examples below, replace `<skill-base-directory>` with the directory that
contains this file.

## Prerequisites

The pipeline requires:

- PowerShell, `uv`, `ffmpeg`, and `ffprobe` on `PATH`.
- An NVIDIA CUDA GPU supported by PyTorch.
- Hugging Face access to the gated pyannote diarization models. Authenticate with
  `hf auth login` or set `HF_TOKEN`; never paste a token into a command, config file,
  transcript, or repository.

Setup creates a reusable virtual environment under
`$HOME/.local/share/meeting-transcription` by default. Set
`MEETING_TRANSCRIPTION_HOME` to use another user-owned location. Do not create a
virtual environment, download models, or save meeting artifacts inside a repository.

## Start or resume the pipeline

Run:

```powershell
$skillRoot = "<skill-base-directory>"
$scripts = Join-Path $skillRoot "scripts"
& (Join-Path $scripts "Invoke-MeetingTranscription.ps1") `
    -VideoPath (Join-Path (Join-Path $HOME "Videos") "meeting.mkv") `
    -MinSpeakers 2 `
    -MaxSpeakers 12
```

The command is resumable. It preserves extracted audio, raw WhisperX formats, logs,
the speaker map, compact speaker-review frames, and rendered transcripts. Use
`-ForceTranscription` only when the source or transcription settings changed. Use
`-ResetSpeakerMap` only when intentionally discarding prior speaker decisions. If a
new diarized transcript no longer matches the fingerprint stored in
`speaker-map.json`, the pipeline writes a fresh speaker review and stops rather than
silently applying names to potentially different clusters. Review the new evidence,
then rerun with `-ResetSpeakerMap`, or use
`-AcceptSpeakerMapForChangedTranscript` only after confirming that the cluster
identities are still valid.

Speaker maps created by older versions do not contain a transcript fingerprint and
therefore require the same one-time review and explicit reset or acceptance.

Do not use hotwords. They can hallucinate terms during quiet audio. If the user
supplies an expected participant count, use a narrow speaker range around that count.
Otherwise use a conservative range and let diarization over-segment rather than force
unrelated voices together.

## Resolve speakers

1. Read `speaker-review.md`. Use direct address, roles, and conversational context
   before relying on visual clues.
2. Inspect only one compact image from `speaker-frames` per tool call. Never load
   multiple full-resolution frames into one model request.
3. Edit `speaker-map.json`:
   - Set high-confidence cluster names in `speaker_map`.
   - Keep uncertain identities explicit, such as `Unidentified speaker 2`.
   - Use `overrides` for time-bounded diarization fragments that belong to another
     speaker.
   - Use `sections` to mark reconnection, breaks, or off-meeting intervals.
4. Re-render after resolving every cluster:

```powershell
$skillRoot = "<skill-base-directory>"
$scripts = Join-Path $skillRoot "scripts"
$toolRoot = if ($env:MEETING_TRANSCRIPTION_HOME) {
    $env:MEETING_TRANSCRIPTION_HOME
} else {
    Join-Path (Join-Path (Join-Path $HOME ".local") "share") "meeting-transcription"
}
$venv = Join-Path $toolRoot ".venv"
$python = @(
    (Join-Path (Join-Path $venv "Scripts") "python.exe")
    (Join-Path (Join-Path $venv "bin") "python")
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$meetingOutput = Join-Path (Join-Path $HOME "Videos") "meeting transcript"
$rawOutput = Join-Path $meetingOutput "raw"

& $python (Join-Path $scripts "render_transcript.py") `
    --transcript (Join-Path $rawOutput "meeting.audio-16k-mono.json") `
    --config (Join-Path $meetingOutput "speaker-map.json") `
    --output-stem (Join-Path $meetingOutput "meeting - Speaker Transcript") `
    --require-names
```

Do not guess a participant identity. Preserve an unidentified label when evidence is
insufficient; `--require-names` should remain blocked until each cluster has an
evidence-supported name or explicit unidentified label.

## Create meeting notes

Read the named Markdown transcript in chronological chunks. Produce
`<meeting> - Meeting Notes.md` beside the transcript, formatted for direct paste into
Google Docs.

Use this structure:

- Title, date/time, attendees, and draft disclaimer.
- Concise meeting summary.
- One section per agenda topic.
- Neutral discussion summary.
- A clearly labeled decision only when a motion, vote, consensus, or explicit
  direction supports it.
- Action items directly beneath the relevant topic, naming the owner and deliverable.
- Final motions and decisions list.

Distinguish carefully:

- A suggestion is not an action item.
- A proposed motion without a completed vote is not a decision.
- A volunteered task is an action item.
- A request accepted by the assignee is an action item.
- Tentative dates remain tentative.
- Informal audio during breaks, reconnection, or after adjournment is omitted unless
  the user explicitly requests it.

Verify every action item and decision against transcript evidence. Ensure that no raw
`SPEAKER_XX` labels remain in the final named transcript or meeting notes.
