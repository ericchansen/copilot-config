"""Focused security and request-construction tests for the Visor helper."""

from __future__ import annotations

import argparse
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

    def test_zero_cache_ttl_forces_fresh_without_reading_cache(self) -> None:
        helper = load_helper()
        with tempfile.TemporaryDirectory() as temp_dir:
            cache_file = Path(temp_dir) / "facets.json"
            cache_file.write_bytes(b"\xff\xfe\x00")

            self.assertIsNone(
                helper.read_cache(cache_file, {"facets": "model"}, ttl_seconds=0)
            )

        parser = helper.build_parser()
        namespace = parser.parse_args(
            [
                "facets",
                "--facets",
                "model",
                "--cache-ttl-seconds",
                "0",
            ]
        )
        self.assertEqual(namespace.cache_ttl_seconds, 0)

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


class VisorApiCapabilitiesAndAccountTests(unittest.TestCase):
    """Capability discovery and account-surface stubs (no browser/private access)."""

    ACCOUNT_COMMANDS = ("favorites", "hides", "saved-searches", "preferences")

    def test_capabilities_lists_all_public_operations_as_supported(self) -> None:
        helper = load_helper()
        payload = helper.capabilities_payload()

        self.assertTrue(payload["ok"])
        public_commands = {op["command"] for op in payload["public_api"]["operations"]}
        self.assertEqual(
            public_commands,
            {
                "facets",
                "listings",
                "listing",
                "vin",
                "dealers",
                "dealer",
                "dealer-listings",
                "usage",
            },
        )
        self.assertTrue(all(op["supported"] for op in payload["public_api"]["operations"]))
        self.assertEqual(payload["public_api"]["base_url"], helper.BASE_URL)
        self.assertIn("VISOR_API_KEY", payload["public_api"]["auth"])
        self.assertIn("Bearer", payload["public_api"]["auth"])

    def test_capabilities_marks_every_account_operation_unsupported_with_reason(self) -> None:
        helper = load_helper()
        payload = helper.capabilities_payload()

        account = payload["account"]
        self.assertFalse(account["supported"])
        self.assertEqual(account["surface"], "account")
        self.assertEqual(account["reason"], "unsupported_operation")
        self.assertEqual(account["terms_url"], helper.TERMS_URL)
        self.assertTrue(account["terms_url"].startswith("https://visor.vin/terms"))
        self.assertTrue(account["next_actions"])

        account_commands = {op["command"] for op in account["operations"]}
        self.assertEqual(account_commands, set(self.ACCOUNT_COMMANDS))
        self.assertTrue(all(op["supported"] is False for op in account["operations"]))

    def test_capabilities_command_succeeds_without_visor_api_key(self) -> None:
        environment = {
            key: value for key, value in os.environ.items() if key != "VISOR_API_KEY"
        }
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        result = subprocess.run(
            [sys.executable, "-B", str(SCRIPT_PATH), "capabilities"],
            capture_output=True,
            check=False,
            env=environment,
            text=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertTrue(payload["ok"])
        self.assertFalse(payload["account"]["supported"])

    def test_account_operations_raise_unsupported_operation_without_touching_network(
        self,
    ) -> None:
        helper = load_helper()

        def forbidden_urlopen(request, timeout):
            raise AssertionError(
                "account stub must never open a network connection: "
                f"attempted {request.full_url!r}"
            )

        for command in self.ACCOUNT_COMMANDS:
            with self.subTest(command=command):
                with patch.object(helper, "urlopen", forbidden_urlopen):
                    with self.assertRaises(helper.ClientError) as cm:
                        helper.run_account_unsupported(command)

                exc = cm.exception
                self.assertEqual(exc.error_type, "unsupported_operation")
                self.assertEqual(exc.details["surface"], "account")
                self.assertEqual(exc.details["terms_url"], helper.TERMS_URL)
                self.assertIn(command, exc.message)

    def test_account_commands_fail_closed_via_cli_without_api_key_or_leakage(self) -> None:
        environment = {
            key: value for key, value in os.environ.items() if key != "VISOR_API_KEY"
        }
        environment["PYTHONDONTWRITEBYTECODE"] = "1"

        for command in self.ACCOUNT_COMMANDS:
            with self.subTest(command=command):
                result = subprocess.run(
                    [sys.executable, "-B", str(SCRIPT_PATH), command],
                    capture_output=True,
                    check=False,
                    env=environment,
                    text=True,
                )

                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")
                error = json.loads(result.stderr)
                self.assertFalse(error["ok"])
                self.assertEqual(error["error"]["type"], "unsupported_operation")
                self.assertEqual(error["error"]["surface"], "account")
                self.assertIn("terms", error["error"]["terms_url"])

                # Never claim empty success, never mention credential/browser
                # sourcing for a capability this skill does not implement.
                combined = (result.stdout + result.stderr).lower()
                for forbidden in ("cookie", "chrome", "firefox", "cdp", "vis_live", "vis_test"):
                    self.assertNotIn(forbidden, combined)

    def test_account_stub_help_text_is_grammatical(self) -> None:
        helper = load_helper()
        parser = helper.build_parser()
        subparsers_action = next(
            action
            for action in parser._actions
            if isinstance(action, argparse._SubParsersAction)
        )

        for command in self.ACCOUNT_COMMANDS:
            with self.subTest(command=command):
                subparser = subparsers_action.choices[command]
                help_text = subparser.format_help()
                self.assertNotIn(". require", help_text)
                self.assertNotIn(".require", help_text)

    def test_usage_command_dispatches_via_main_without_falling_back(self) -> None:
        def fake_urlopen(request, timeout):
            self.assertIn("/v1/usage", request.full_url)
            return FakeDetailResponse(b'{"data":{"requests":10}}')

        stdout = io.StringIO()
        with (
            patch.object(sys, "argv", [str(SCRIPT_PATH), "usage"]),
            patch.dict(os.environ, {"VISOR_API_KEY": "vis_live_unit_test_credential"}),
            redirect_stdout(stdout),
        ):
            # `emit_json`'s `file=sys.stdout` default binds at module-exec
            # time, so the helper must be loaded inside the redirect scope
            # for the patched stream to take effect.
            helper = load_helper()
            with patch.object(helper, "urlopen", fake_urlopen):
                exit_code = helper.main()

        self.assertEqual(exit_code, 0)
        self.assertTrue(json.loads(stdout.getvalue())["ok"])

    def test_unrecognized_command_raises_internal_error_instead_of_usage_fallback(
        self,
    ) -> None:
        helper = load_helper()

        class FakeArgs:
            command = "not-a-real-command"

        class FakeParser:
            def parse_args(self):
                return FakeArgs()

        def forbidden_urlopen(request, timeout):
            raise AssertionError("an unrecognized command must never reach the network")

        stderr = io.StringIO()
        with (
            patch.object(helper, "build_parser", return_value=FakeParser()),
            patch.object(helper, "urlopen", forbidden_urlopen),
            patch.object(sys, "argv", [str(SCRIPT_PATH), "not-a-real-command"]),
            patch.dict(os.environ, {"VISOR_API_KEY": "vis_live_unit_test_credential"}),
            redirect_stderr(stderr),
        ):
            exit_code = helper.main()

        self.assertEqual(exit_code, 1)
        error = json.loads(stderr.getvalue())
        self.assertFalse(error["ok"])
        self.assertEqual(error["error"]["type"], "internal_error")


if __name__ == "__main__":
    unittest.main()
