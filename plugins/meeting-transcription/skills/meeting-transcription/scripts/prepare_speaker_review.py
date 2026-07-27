import argparse
import hashlib
import json
import re
import subprocess
from collections import defaultdict
from pathlib import Path


def clock(seconds: float) -> str:
    seconds = max(0, int(seconds))
    hours, remainder = divmod(seconds, 3600)
    minutes, seconds = divmod(remainder, 60)
    return f"{hours:02}:{minutes:02}:{seconds:02}"


def clean(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def choose_samples(
    items: list[tuple[int, dict]], count: int = 5
) -> list[tuple[int, dict]]:
    ranked = sorted(
        items,
        key=lambda item: (
            len(clean(item[1].get("text", "")).split()),
            float(item[1]["end"]) - float(item[1]["start"]),
        ),
        reverse=True,
    )
    selected = []
    for item in ranked:
        midpoint = (float(item[1]["start"]) + float(item[1]["end"])) / 2
        if all(
            abs(
                midpoint
                - (float(existing[1]["start"]) + float(existing[1]["end"])) / 2
            )
            >= 20
            for existing in selected
        ):
            selected.append(item)
        if len(selected) == count:
            break
    return sorted(selected, key=lambda item: float(item[1]["start"]))


def write_text_atomic(path: Path, text: str) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(text, encoding="utf-8")
    temporary.replace(path)


def write_json_atomic(path: Path, data: dict) -> None:
    write_text_atomic(path, json.dumps(data, indent=2) + "\n")


def transcript_fingerprint(segments: list[dict]) -> str:
    relevant_data = [
        {
            "start": float(segment["start"]),
            "end": float(segment["end"]),
            "speaker": segment.get("speaker") or "UNLABELED",
            "text": clean(segment.get("text", "")),
        }
        for segment in segments
    ]
    payload = json.dumps(
        relevant_data, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def load_or_create_config(
    path: Path,
    title: str,
    labels: list[str],
    fingerprint: str,
    reset: bool,
    accept_transcript_change: bool,
) -> tuple[dict, bool]:
    if reset or not path.exists():
        config = {
            "title": title,
            "participants": [],
            "sections": [{"start": 0, "title": "Meeting"}],
            "speaker_map": {label: "" for label in labels},
            "overrides": [],
            "transcript_fingerprint": fingerprint,
        }
        write_json_atomic(path, config)
        return config, False

    config = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(config, dict):
        raise SystemExit(f"Speaker map must contain a JSON object: {path}")

    stored_fingerprint = str(config.get("transcript_fingerprint") or "").strip()
    transcript_changed = stored_fingerprint != fingerprint
    if transcript_changed and not accept_transcript_change:
        return config, True

    speaker_map = config.setdefault("speaker_map", {})
    if not isinstance(speaker_map, dict):
        raise SystemExit(f"'speaker_map' must be a JSON object: {path}")

    changed = False
    for label in labels:
        if label not in speaker_map:
            speaker_map[label] = ""
            changed = True

    for key, default in (
        ("title", title),
        ("participants", []),
        ("sections", [{"start": 0, "title": "Meeting"}]),
        ("overrides", []),
        ("transcript_fingerprint", fingerprint),
    ):
        if key not in config:
            config[key] = default
            changed = True

    if config["transcript_fingerprint"] != fingerprint:
        config["transcript_fingerprint"] = fingerprint
        changed = True

    if changed:
        write_json_atomic(path, config)
    return config, False


def run_media_command(
    command: list[str],
    tool: str,
    failure_message: str,
    cleanup: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            command,
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as error:
        if cleanup:
            cleanup.unlink(missing_ok=True)
        raise SystemExit(
            f"{tool} was not found. Install ffmpeg and ensure {tool} is available "
            "on PATH."
        ) from error
    except subprocess.CalledProcessError as error:
        if cleanup:
            cleanup.unlink(missing_ok=True)
        details = clean(error.stderr or error.stdout or "")
        message = f"{failure_message} (exit {error.returncode})"
        if details:
            message += f": {details}"
        raise SystemExit(message) from error


def extract_frame(video: Path, timestamp: float, destination: Path) -> None:
    command = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-y",
        "-ss",
        f"{timestamp:.3f}",
        "-i",
        str(video),
        "-frames:v",
        "1",
        "-vf",
        "scale=1280:-2",
        "-q:v",
        "9",
        str(destination),
    ]
    destination.unlink(missing_ok=True)
    run_media_command(
        command,
        "ffmpeg",
        "ffmpeg could not extract the speaker frame",
        cleanup=destination,
    )


def has_video_stream(media: Path) -> bool:
    command = [
        "ffprobe",
        "-v",
        "error",
        "-select_streams",
        "v:0",
        "-show_entries",
        "stream=index",
        "-of",
        "csv=p=0",
        str(media),
    ]
    result = run_media_command(
        command,
        "ffprobe",
        "ffprobe could not inspect the media",
    )
    return bool(result.stdout.strip())


def frame_name(label: str) -> str:
    safe_label = re.sub(r"[^A-Za-z0-9_.-]+", "_", label).strip("._")
    return f"{safe_label or 'UNLABELED'}.jpg"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--video", type=Path, required=True)
    parser.add_argument("--transcript", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--reset-speaker-map", action="store_true")
    parser.add_argument("--accept-transcript-change", action="store_true")
    args = parser.parse_args()

    data = json.loads(args.transcript.read_text(encoding="utf-8"))
    segments = data.get("segments", [])
    if not segments:
        raise SystemExit("The transcript contains no segments.")

    groups: dict[str, list[tuple[int, dict]]] = defaultdict(list)
    for index, segment in enumerate(segments):
        label = segment.get("speaker") or "UNLABELED"
        groups[label].append((index, segment))

    args.output_dir.mkdir(parents=True, exist_ok=True)
    frames_dir = args.output_dir / "speaker-frames"
    frames_dir.mkdir(exist_ok=True)
    config_path = args.output_dir / "speaker-map.json"
    media_has_video = has_video_stream(args.video)

    _, transcript_changed = load_or_create_config(
        config_path,
        args.video.stem,
        sorted(groups),
        transcript_fingerprint(segments),
        args.reset_speaker_map,
        args.accept_transcript_change,
    )

    coverage_end = max(float(segment["end"]) for segment in segments)
    lines = [
        "# Speaker Review",
        "",
        f"**Recording:** {args.video.name}  ",
        f"**Duration covered:** {clock(coverage_end)}  ",
        f"**Diarization clusters:** {len(groups)}  ",
        f"**Transcript segments:** {len(segments)}",
        "",
        "Resolve names from direct address and context first. Inspect compact frames one at "
        "a time when context is insufficient. Record global names and any time-bounded "
        "exceptions in `speaker-map.json`.",
        "",
    ]

    for label in sorted(groups):
        items = groups[label]
        duration = sum(float(item["end"]) - float(item["start"]) for _, item in items)
        samples = choose_samples(items)
        lines.extend(
            [
                f"## {label}",
                "",
                f"- Segments: {len(items)}",
                f"- Speaking time: {duration:.1f} seconds",
                f"- First/last: {clock(float(items[0][1]['start']))} / "
                f"{clock(float(items[-1][1]['end']))}",
            ]
        )

        if media_has_video and label != "UNLABELED" and samples:
            best = max(
                samples,
                key=lambda item: float(item[1]["end"]) - float(item[1]["start"]),
            )
            timestamp = (float(best[1]["start"]) + float(best[1]["end"])) / 2
            frame = frames_dir / frame_name(label)
            extract_frame(args.video, timestamp, frame)
            lines.append(
                f"- Review frame: `speaker-frames/{frame.name}` at {clock(timestamp)}"
            )
        lines.append("")

        for index, segment in samples:
            lines.append(
                f"**[{clock(float(segment['start']))}]** "
                f"{clean(segment.get('text', ''))}"
            )
            before = segments[index - 1] if index > 0 else None
            after = segments[index + 1] if index + 1 < len(segments) else None
            if before:
                lines.append(
                    f"- Before ({before.get('speaker') or 'UNLABELED'}): "
                    f"{clean(before.get('text', ''))}"
                )
            if after:
                lines.append(
                    f"- After ({after.get('speaker') or 'UNLABELED'}): "
                    f"{clean(after.get('text', ''))}"
                )
            lines.append("")

    review_path = args.output_dir / "speaker-review.md"
    write_text_atomic(review_path, "\n".join(lines).rstrip() + "\n")
    print(f"Wrote {review_path}")
    print(f"Preserved {config_path}")
    if transcript_changed:
        raise SystemExit(
            "The diarized transcript changed, so the existing speaker map was not "
            "applied. Review the new speaker evidence, then rerun with "
            "--reset-speaker-map or --accept-transcript-change."
        )


if __name__ == "__main__":
    main()
