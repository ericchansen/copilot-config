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

    def test_user_agent_matches_plugin_version(self) -> None:
        helper = load_helper()
        plugin_json = json.loads(
            (Path(__file__).parents[1] / "plugin.json").read_text(encoding="utf-8")
        )

        self.assertEqual(helper.PLUGIN_VERSION, plugin_json["version"])

        captured_header: list[str | None] = []

        def fake_urlopen(request, timeout):
            captured_header.append(request.get_header("User-agent"))
            return FakeResponse()

        with patch.object(helper, "urlopen", fake_urlopen):
            helper.request_json(
                "facets",
                {"facets": "make", "facet_value_limit": "1"},
                "vis_live_unit_test_credential",
                timeout=1.0,
                max_attempts=1,
            )

        self.assertEqual(captured_header, [f"visor/{plugin_json['version']}"])

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


class FakeDetailResponse:
    """Fake response mimicking a `{data: {...}}` object endpoint."""

    def __init__(self, body: bytes) -> None:
        self._body = body
        self.headers: dict[str, str] = {}

    def __enter__(self):
        return self

    def __exit__(self, *_args) -> None:
        return None

    def read(self) -> bytes:
        return self._body


class VisorApiObjectEndpointTests(unittest.TestCase):
    """Coverage for the six documented endpoints beyond facets/listings."""

    def _run_command(self, helper, args, urls: list[str]):
        def fake_urlopen(request, timeout):
            urls.append(request.full_url)
            return FakeDetailResponse(b'{"data":{"id":"abc123"}}')

        with patch.object(helper, "urlopen", fake_urlopen):
            parser = helper.build_parser()
            namespace = parser.parse_args(args)
            api_key = "vis_live_unit_test_credential"
            if namespace.command == "listing":
                return helper.run_listing_detail(namespace, api_key)
            if namespace.command == "vin":
                return helper.run_vin(namespace, api_key)
            if namespace.command == "dealer":
                return helper.run_dealer_detail(namespace, api_key)
            raise AssertionError(f"unhandled command {namespace.command}")

    def test_listing_detail_encodes_id_into_path(self) -> None:
        helper = load_helper()
        urls: list[str] = []
        output = self._run_command(
            helper,
            ["listing", "--listing-id", "abc 123#x"],
            urls,
        )
        self.assertTrue(output["ok"])
        self.assertIn("listings/abc%20123%23x", urls[0])

    def test_vin_lookup_builds_expected_path(self) -> None:
        helper = load_helper()
        urls: list[str] = []
        output = self._run_command(helper, ["vin", "--vin", "1HGCM82633A004352"], urls)
        self.assertTrue(output["ok"])
        self.assertIn("vins/1HGCM82633A004352", urls[0])

    def test_dealer_detail_builds_expected_path(self) -> None:
        helper = load_helper()
        urls: list[str] = []
        output = self._run_command(helper, ["dealer", "--dealer-id", "dealer-1"], urls)
        self.assertTrue(output["ok"])
        self.assertIn("dealers/dealer-1", urls[0])

    def test_detail_query_params_match_openapi_contract(self) -> None:
        helper = load_helper()

        for command, identifier_flag in (
            ("listing", "--listing-id"),
            ("vin", "--vin"),
        ):
            with self.subTest(command=command):
                urls: list[str] = []
                output = self._run_command(
                    helper,
                    [command, identifier_flag, "abc123", "--param", "include=options"],
                    urls,
                )
                self.assertTrue(output["ok"])
                self.assertIn("include=options", urls[0])

        parser = helper.build_parser()
        namespace = parser.parse_args(
            ["dealer", "--dealer-id", "dealer-1", "--param", "include=options"]
        )
        with self.assertRaises(helper.ClientError) as raised:
            helper.run_dealer_detail(namespace, "vis_live_unit_test_credential")
        self.assertEqual(raised.exception.error_type, "validation_error")

    def test_path_segment_rejects_empty_separators_and_dot_segments(self) -> None:
        helper = load_helper()
        with self.assertRaises(helper.ClientError) as raised:
            helper.path_segment("", "vin")
        self.assertEqual(raised.exception.error_type, "validation_error")

        for invalid in ("a/b", r"a\b", ".", "..", "  ..  "):
            with self.subTest(invalid=invalid):
                with self.assertRaises(helper.ClientError) as raised:
                    helper.path_segment(invalid, "vin")
                self.assertEqual(raised.exception.error_type, "validation_error")

    def test_path_segment_strips_whitespace_before_validating_and_encoding(self) -> None:
        helper = load_helper()

        self.assertEqual(helper.path_segment("  abc123  ", "vin"), "abc123")
        self.assertEqual(helper.path_segment("\tdealer-1\n", "dealer_id"), "dealer-1")

        with self.assertRaises(helper.ClientError) as raised:
            helper.path_segment("   ", "vin")
        self.assertEqual(raised.exception.error_type, "validation_error")

    def test_listing_detail_rejects_path_separator_in_id(self) -> None:
        helper = load_helper()
        parser = helper.build_parser()
        namespace = parser.parse_args(["listing", "--listing-id", "abc/../secret"])
        with self.assertRaises(helper.ClientError) as raised:
            helper.run_listing_detail(namespace, "vis_live_unit_test_credential")
        self.assertEqual(raised.exception.error_type, "validation_error")

    def test_dealers_search_validates_params_and_paginates_fields(self) -> None:
        helper = load_helper()

        def fake_urlopen(request, timeout):
            self.assertIn("dealers?", request.full_url)
            return FakeDetailResponse(
                b'{"data":[{"id":"d1"}],"pagination":{"total":1,"next_offset":null}}'
            )

        with patch.object(helper, "urlopen", fake_urlopen):
            parser = helper.build_parser()
            namespace = parser.parse_args(["dealers", "--param", "state=CA"])
            output = helper.run_dealers(namespace, "vis_live_unit_test_credential")

        self.assertTrue(output["ok"])
        self.assertEqual(output["data"], [{"id": "d1"}])

        parser = helper.build_parser()
        namespace = parser.parse_args(["dealers", "--param", "dealer_type=franchise"])
        with self.assertRaises(helper.ClientError) as raised:
            helper.run_dealers(namespace, "vis_live_unit_test_credential")
        self.assertEqual(raised.exception.error_type, "validation_error")

    def test_dealers_search_rejects_malformed_pagination(self) -> None:
        helper = load_helper()

        def fake_urlopen(request, timeout):
            # `pagination` is a list instead of the required object shape.
            return FakeDetailResponse(b'{"data":[{"id":"d1"}],"pagination":[]}')

        with patch.object(helper, "urlopen", fake_urlopen):
            parser = helper.build_parser()
            namespace = parser.parse_args(["dealers"])
            with self.assertRaises(helper.ClientError) as raised:
                helper.run_dealers(namespace, "vis_live_unit_test_credential")

        self.assertEqual(raised.exception.error_type, "response_error")

    def test_dealer_listings_uses_nested_path_and_shared_pagination(self) -> None:
        helper = load_helper()
        urls: list[str] = []

        def fake_urlopen(request, timeout):
            urls.append(request.full_url)
            return FakeDetailResponse(
                b'{"data":[],"pagination":{"total":0,"next_offset":null}}'
            )

        with patch.object(helper, "urlopen", fake_urlopen):
            parser = helper.build_parser()
            namespace = parser.parse_args(["dealer-listings", "--dealer-id", "d-9"])
            output = helper.run_dealer_listings(namespace, "vis_live_unit_test_credential")

        self.assertTrue(output["ok"])
        self.assertIn("dealers/d-9/listings", urls[0])

    def test_usage_command_requires_object_data(self) -> None:
        helper = load_helper()

        def fake_urlopen(request, timeout):
            self.assertIn("/v1/usage", request.full_url)
            return FakeDetailResponse(b'{"data":{"requests":10}}')

        with patch.object(helper, "urlopen", fake_urlopen):
            parser = helper.build_parser()
            namespace = parser.parse_args(["usage"])
            output = helper.run_usage(namespace, "vis_live_unit_test_credential")

        self.assertTrue(output["ok"])
        self.assertEqual(output["response"]["data"], {"requests": 10})


if __name__ == "__main__":
    unittest.main()
