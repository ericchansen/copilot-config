import argparse
import json
import math
import re
from pathlib import Path


def clean(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def clock(seconds: float, milliseconds: bool = False) -> str:
    total_ms = max(0, round(seconds * 1000))
    hours, remainder = divmod(total_ms, 3_600_000)
    minutes, remainder = divmod(remainder, 60_000)
    seconds, millis = divmod(remainder, 1000)
    if milliseconds:
        return f"{hours:02}:{minutes:02}:{seconds:02},{millis:03}"
    return f"{hours:02}:{minutes:02}:{seconds:02}"


def number(value: object, context: str) -> float:
    if isinstance(value, bool):
        raise SystemExit(f"{context} must be a number.")
    try:
        parsed = float(value)
    except (TypeError, ValueError) as error:
        raise SystemExit(f"{context} must be a number.") from error
    if not math.isfinite(parsed):
        raise SystemExit(f"{context} must be finite.")
    return parsed


def config_items(config: dict, key: str) -> list[dict]:
    value = config.get(key, [])
    if not isinstance(value, list):
        raise SystemExit(f"Configuration '{key}' must be a list.")
    for index, item in enumerate(value, start=1):
        if not isinstance(item, dict):
            raise SystemExit(f"Configuration '{key}' item {index} must be an object.")
    return value


def sections_for(config: dict) -> list[dict]:
    sections = []
    for index, section in enumerate(config_items(config, "sections"), start=1):
        title_value = section.get("title")
        if not isinstance(title_value, str) or not title_value.strip():
            raise SystemExit(f"Section {index} must have a non-empty 'title'.")
        sections.append(
            {
                "start": number(section.get("start"), f"Section {index} 'start'"),
                "title": title_value.strip(),
            }
        )
    return sorted(sections, key=lambda item: item["start"])


def overrides_for(config: dict) -> list[dict]:
    overrides = []
    for index, override in enumerate(config_items(config, "overrides"), start=1):
        start = number(override.get("start"), f"Override {index} 'start'")
        end = number(override.get("end"), f"Override {index} 'end'")
        if end <= start:
            raise SystemExit(f"Override {index} 'end' must be greater than 'start'.")
        name_value = override.get("name")
        if not isinstance(name_value, str) or not name_value.strip():
            raise SystemExit(f"Override {index} must have a non-empty 'name'.")
        speaker_value = override.get("speaker")
        if speaker_value is not None and not isinstance(speaker_value, str):
            raise SystemExit(
                f"Override {index} 'speaker' must be a string when provided."
            )
        overrides.append(
            {
                "start": start,
                "end": end,
                "name": name_value.strip(),
                "speaker": (speaker_value or "").strip(),
            }
        )
    return overrides


def section_for(timestamp: float, sorted_sections: list[dict]) -> str:
    title = "Meeting"
    for section in sorted_sections:
        if timestamp >= section["start"]:
            title = section["title"]
    return title


def unidentified_name(label: str) -> str:
    match = re.fullmatch(r"SPEAKER_(\d+)", label)
    if match:
        return f"Unidentified speaker {int(match.group(1)) + 1}"
    return "Unidentified speaker"


def speaker_for(
    segment: dict, config: dict, overrides: list[dict]
) -> tuple[str, bool]:
    label = segment.get("speaker") or "UNLABELED"
    start = float(segment["start"])
    end = float(segment["end"])
    for override in overrides:
        source_matches = not override.get("speaker") or override["speaker"] == label
        range_matches = start < override["end"] and end > override["start"]
        if source_matches and range_matches:
            return override["name"], True
    mapped = str(config.get("speaker_map", {}).get(label, "")).strip()
    if mapped and not re.fullmatch(r"SPEAKER_\d+", mapped):
        return mapped, True
    return unidentified_name(label), False


def prepare(source: list[dict], config: dict) -> list[dict]:
    if not isinstance(config, dict):
        raise SystemExit("Configuration root must be an object.")
    if not isinstance(config.get("speaker_map", {}), dict):
        raise SystemExit("Configuration 'speaker_map' must be an object.")

    segments = []
    sections = sections_for(config)
    overrides = overrides_for(config)
    for source_index, segment in enumerate(source, start=1):
        text = clean(segment.get("text", ""))
        if not text:
            continue
        start = float(segment["start"])
        speaker, speaker_resolved = speaker_for(segment, config, overrides)
        segments.append(
            {
                "source_index": source_index,
                "start": start,
                "end": float(segment["end"]),
                "speaker": speaker,
                "speaker_resolved": speaker_resolved,
                "section": section_for(start, sections),
                "text": text,
            }
        )
    return segments


def merge_turns(segments: list[dict]) -> list[dict]:
    turns = []
    for segment in segments:
        previous = turns[-1] if turns else None
        merge = (
            previous
            and previous["speaker"] == segment["speaker"]
            and previous["section"] == segment["section"]
            and segment["start"] - previous["end"] <= 2
            and segment["end"] - previous["start"] <= 45
            and len(previous["text"]) + len(segment["text"]) <= 900
        )
        if merge:
            previous["end"] = max(previous["end"], segment["end"])
            previous["text"] += " " + segment["text"]
        else:
            turns.append(dict(segment))
    return turns


def participants(config: dict, segments: list[dict]) -> list[str]:
    configured = [
        str(name).strip()
        for name in config.get("participants", [])
        if str(name).strip()
    ]
    if configured:
        return configured
    return sorted(
        {
            segment["speaker"]
            for segment in segments
            if segment["speaker_resolved"]
        }
    )


def render_markdown(config: dict, segments: list[dict], turns: list[dict]) -> str:
    people = participants(config, segments)
    lines = [
        f"# {config.get('title') or 'Meeting'} - Speaker Transcript",
        "",
        f"**Coverage:** {clock(segments[0]['start'])}-{clock(segments[-1]['end'])}  ",
        f"**Source:** {len(segments)} aligned diarization segments",
        "",
        "This automated transcript may contain recognition, punctuation, or speaker "
        "attribution errors.",
        "",
        "## Participants",
        "",
        ", ".join(people) if people else "Speaker identification pending.",
        "",
    ]
    current_section = None
    for turn in turns:
        if turn["section"] != current_section:
            current_section = turn["section"]
            lines.extend([f"## {current_section}", ""])
        lines.extend(
            [
                f"**[{clock(turn['start'])}-{clock(turn['end'])}] "
                f"{turn['speaker']}:** {turn['text']}",
                "",
            ]
        )
    return "\n".join(lines).rstrip() + "\n"


def render_text(config: dict, segments: list[dict], turns: list[dict]) -> str:
    people = participants(config, segments)
    lines = [
        f"{config.get('title') or 'MEETING'} - SPEAKER TRANSCRIPT",
        f"Coverage: {clock(segments[0]['start'])}-{clock(segments[-1]['end'])}",
        f"Source: {len(segments)} aligned diarization segments",
        "",
        "Participants: " + (", ".join(people) if people else "Identification pending"),
        "",
    ]
    current_section = None
    for turn in turns:
        if turn["section"] != current_section:
            current_section = turn["section"]
            lines.extend([current_section.upper(), "-" * len(current_section), ""])
        lines.extend(
            [
                f"[{clock(turn['start'])}-{clock(turn['end'])}] "
                f"{turn['speaker']}: {turn['text']}",
                "",
            ]
        )
    return "\n".join(lines).rstrip() + "\n"


def render_srt(segments: list[dict]) -> str:
    blocks = []
    for index, segment in enumerate(segments, start=1):
        blocks.append(
            "\n".join(
                [
                    str(index),
                    f"{clock(segment['start'], True)} --> "
                    f"{clock(segment['end'], True)}",
                    f"{segment['speaker']}: {segment['text']}",
                ]
            )
        )
    return "\n\n".join(blocks) + "\n"


def write_atomic(path: Path, text: str) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(text, encoding="utf-8")
    temporary.replace(path)


def output_path(stem: Path, suffix: str) -> Path:
    return stem.parent / f"{stem.name}{suffix}"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--transcript", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--output-stem", type=Path, required=True)
    parser.add_argument("--require-names", action="store_true")
    args = parser.parse_args()

    source_data = json.loads(args.transcript.read_text(encoding="utf-8"))
    config = json.loads(args.config.read_text(encoding="utf-8"))
    source_segments = source_data.get("segments", [])
    segments = prepare(source_segments, config)
    if not segments:
        raise SystemExit("No non-empty transcript segments were found.")
    if any(
        segments[index]["start"] < segments[index - 1]["start"]
        for index in range(1, len(segments))
    ):
        raise SystemExit("Transcript segments are not chronological.")

    unresolved = sorted(
        {
            segment["speaker"]
            for segment in segments
            if not segment["speaker_resolved"]
        }
    )
    if args.require_names and unresolved:
        raise SystemExit("Unresolved speaker labels: " + ", ".join(unresolved))

    turns = merge_turns(segments)
    args.output_stem.parent.mkdir(parents=True, exist_ok=True)
    outputs = {
        output_path(args.output_stem, ".md"): render_markdown(
            config, segments, turns
        ),
        output_path(args.output_stem, ".txt"): render_text(config, segments, turns),
        output_path(args.output_stem, ".srt"): render_srt(segments),
    }
    for path, text in outputs.items():
        write_atomic(path, text)

    report = {
        "source_segments": len(source_segments),
        "rendered_segments": len(segments),
        "readable_turns": len(turns),
        "coverage_start": segments[0]["start"],
        "coverage_end": segments[-1]["end"],
        "unresolved_speakers": unresolved,
        "outputs": [str(path) for path in outputs],
    }
    write_atomic(
        output_path(args.output_stem, " - render-report.json"),
        json.dumps(report, indent=2) + "\n",
    )
    print(
        f"Rendered {len(segments)} source segments as {len(turns)} turns; "
        f"{len(unresolved)} speaker labels unresolved."
    )


if __name__ == "__main__":
    main()
