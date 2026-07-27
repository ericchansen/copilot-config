"""Focused security and request-construction tests for the Visor helper."""

from __future__ import annotations

import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import patch


SCRIPT_PATH = (
    Path(__file__).parents[1]
    / "skills"
    / "visor"
    / "scripts"
    / "visor_api.py"
)


def load_helper():
    spec = importlib.util.spec_from_file_location("vehicle_shopping_visor_api", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load visor_api.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class FakeResponse:
    def __init__(self) -> None:
        self.headers = {
            "X-Usage-Class": "facet_search",
            "X-Usage-Cost-Micros": "250",
        }

    def __enter__(self):
        return self

    def __exit__(self, *_args) -> None:
        return None

    def read(self) -> bytes:
        return b'{"data":{"total":0,"facets":{"make":[]}}}'


class VisorApiSecurityTests(unittest.TestCase):
    def test_authorization_header_is_internal_and_output_is_redacted(self) -> None:
        helper = load_helper()
        test_key = "vis_" + "live_" + "unit_test_credential"
        captured_header: list[str | None] = []

        def fake_urlopen(request, timeout):
            self.assertEqual(timeout, 1.0)
            captured_header.append(request.get_header("Authorization"))
            return FakeResponse()

        stdout = io.StringIO()
        stderr = io.StringIO()
        with (
            patch.object(helper, "urlopen", fake_urlopen),
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            payload, usage = helper.request_json(
                "facets",
                {"facets": "make", "facet_value_limit": "1"},
                test_key,
                timeout=1.0,
                max_attempts=1,
            )
        helper.emit_json(
            {"ok": True, "response": payload, "usage": usage},
            file=stdout,
        )

        self.assertEqual(captured_header, [f"Bearer {test_key}"])
        structured = json.dumps({"response": payload, "usage": usage})
        self.assertNotIn(test_key, structured)
        self.assertNotIn(test_key, stdout.getvalue())
        self.assertNotIn(test_key, stderr.getvalue())

    def test_raw_argv_key_is_rejected_before_argparse_without_echo(self) -> None:
        environment = dict(
            os.environ,
            PYTHONDONTWRITEBYTECODE="1",
            VISOR_API_KEY="placeholder",
        )
        for key_type in ("live", "test"):
            with self.subTest(key_type=key_type):
                test_key = "vis_" + key_type + "_argv_test_credential"
                result = subprocess.run(
                    [sys.executable, "-B", str(SCRIPT_PATH), "--api-key", test_key],
                    capture_output=True,
                    check=False,
                    env=environment,
                    text=True,
                )

                self.assertEqual(result.returncode, 1)
                self.assertNotIn(test_key, result.stdout)
                self.assertNotIn(test_key, result.stderr)
                self.assertNotIn("vis_" + key_type + "_", result.stdout + result.stderr)
                error = json.loads(result.stderr)
                self.assertEqual(error["error"]["type"], "credential_error")

    def test_cache_write_is_atomic_and_ignores_predictable_temp_path(self) -> None:
        helper = load_helper()
        with tempfile.TemporaryDirectory() as temp_dir:
            cache_file = Path(temp_dir) / "facets.json"
            predictable = cache_file.with_name(f"{cache_file.name}.tmp")
            predictable.write_text("do not replace", encoding="utf-8")
            output = {"ok": True, "query": {"facets": "make"}}

            with patch.object(
                helper.os,
                "replace",
                wraps=helper.os.replace,
            ) as replace_mock:
                helper.write_cache(cache_file, output)

            source, destination = replace_mock.call_args.args
            self.assertEqual(Path(source).parent, cache_file.parent)
            self.assertNotEqual(Path(source), predictable)
            self.assertEqual(Path(destination), cache_file)
            self.assertFalse(Path(source).exists())
            self.assertEqual(
                predictable.read_text(encoding="utf-8"),
                "do not replace",
            )
            cached = json.loads(cache_file.read_text(encoding="utf-8"))
            self.assertTrue(cached["ok"])
            self.assertIn("retrieved_epoch", cached)

    def test_cache_write_failure_cleans_only_created_temp(self) -> None:
        helper = load_helper()
        with tempfile.TemporaryDirectory() as temp_dir:
            cache_file = Path(temp_dir) / "facets.json"
            predictable = cache_file.with_name(f"{cache_file.name}.tmp")
            predictable.write_text("keep me", encoding="utf-8")

            with patch.object(
                helper.os,
                "replace",
                side_effect=OSError("replace failed"),
            ):
                with self.assertRaises(helper.ClientError) as raised:
                    helper.write_cache(cache_file, {"ok": True})

            self.assertEqual(raised.exception.error_type, "cache_error")
            self.assertFalse(cache_file.exists())
            self.assertEqual(predictable.read_text(encoding="utf-8"), "keep me")
            self.assertEqual(
                sorted(path.name for path in Path(temp_dir).iterdir()),
                [predictable.name],
            )

    def test_cache_read_invalid_utf8_returns_structured_error(self) -> None:
        helper = load_helper()
        with tempfile.TemporaryDirectory() as temp_dir:
            cache_file = Path(temp_dir) / "facets.json"
            cache_file.write_bytes(b"\xff\xfe\x00")

            with self.assertRaises(helper.ClientError) as raised:
                helper.read_cache(cache_file, {"facets": "make"}, 60)

            self.assertEqual(raised.exception.error_type, "cache_error")

    def test_cache_write_unserializable_output_returns_structured_error(self) -> None:
        helper = load_helper()
        with tempfile.TemporaryDirectory() as temp_dir:
            cache_file = Path(temp_dir) / "facets.json"

            with self.assertRaises(helper.ClientError) as raised:
                helper.write_cache(cache_file, {"invalid": object()})

            self.assertEqual(raised.exception.error_type, "cache_error")
            self.assertFalse(cache_file.exists())
            self.assertEqual(list(Path(temp_dir).iterdir()), [])


if __name__ == "__main__":
    unittest.main()
