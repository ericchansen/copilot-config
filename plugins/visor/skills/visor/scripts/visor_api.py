#!/usr/bin/env python3
"""Dependency-free client for Visor's supported Public API."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


BASE_URL = "https://api.visor.vin/v1"
DEFAULT_FIELDS = ",".join(
    [
        "year",
        "make",
        "model",
        "trim",
        "version",
        "powertrain_type",
        "drivetrain",
        "price",
        "msrp",
        "miles",
        "inventory_type",
        "inventory_status",
        "availability_status",
        "vdp_url",
        "dealer_id",
        "dealer_name",
        "city",
        "state",
        "postal_code",
        "distance_miles",
        "listed_at",
        "sold_date",
    ]
)

COMMON_FILTERS = {
    "make",
    "model",
    "model_code",
    "trim",
    "year",
    "state",
    "dealer_id",
    "dealer_type",
    "availability_status",
    "inventory_type",
    "body_type",
    "transmission",
    "drivetrain",
    "assembly_location",
    "assembly_country",
    "fuel_type",
    "powertrain_type",
    "engine",
    "version",
    "exterior_color",
    "interior_color",
    "base_exterior_color",
    "base_interior_color",
    "seating_capacity",
    "cylinders",
    "doors",
    "options_packages",
    "features",
    "keywords",
    "vin_pattern",
    "exclude_make",
    "exclude_model",
    "exclude_trim",
    "exclude_year",
    "exclude_state",
    "exclude_inventory_type",
    "exclude_body_type",
    "exclude_transmission",
    "exclude_drivetrain",
    "exclude_version",
    "exclude_engine",
    "exclude_assembly_location",
    "exclude_assembly_country",
    "exclude_exterior_color",
    "exclude_interior_color",
    "exclude_base_exterior_color",
    "exclude_base_interior_color",
    "exclude_options_packages",
    "exclude_features",
    "exclude_fuel_type",
    "exclude_powertrain_type",
    "exclude_keywords",
    "listed_after",
    "min_price",
    "max_price",
    "min_mileage",
    "max_mileage",
    "min_msrp",
    "max_msrp",
    "min_days_on_market",
    "max_days_on_market",
    "latitude",
    "longitude",
    "postal_code",
    "radius",
    "bbox",
}
LISTING_PARAMS = COMMON_FILTERS | {"sort", "include"}
FACET_PARAMS = COMMON_FILTERS
MODE_PARAMS = {"inventory_status", "sold_within_days", "snapshot_date"}
USAGE_HEADERS = {
    "x-usage-class",
    "x-pricing-version",
    "x-usage-cost-micros",
    "x-ratelimit-tier",
    "x-ratelimit-limit-10s",
    "x-ratelimit-remaining-10s",
    "x-ratelimit-limit-60s",
    "x-ratelimit-remaining-60s",
}


class ClientError(Exception):
    """An expected configuration, validation, transport, or API failure."""

    def __init__(self, error_type: str, message: str, **details: Any) -> None:
        super().__init__(message)
        self.error_type = error_type
        self.message = message
        self.details = details


class JsonArgumentParser(argparse.ArgumentParser):
    """Emit machine-readable failures for invalid command-line arguments."""

    def error(self, message: str) -> None:
        error = {
            "ok": False,
            "error": {
                "type": "argument_error",
                "message": message,
            },
        }
        emit_json(error, file=sys.stderr)
        self.exit(2)


KEY_PATTERN = re.compile(r"vis_(?:live|test)_[A-Za-z0-9._-]+")


def redact_text(value: str) -> str:
    return KEY_PATTERN.sub("[REDACTED]", value)


def emit_json(value: Any, file: Any = sys.stdout) -> None:
    rendered = json.dumps(value, indent=2, sort_keys=True)
    print(redact_text(rendered), file=file)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def parse_params(values: list[str], allowed: set[str]) -> dict[str, str]:
    params: dict[str, str] = {}
    for value in values:
        if "=" not in value:
            raise ClientError(
                "validation_error",
                f"Invalid --param {value!r}; expected NAME=VALUE.",
            )
        name, param_value = value.split("=", 1)
        name = name.strip()
        if name in MODE_PARAMS:
            raise ClientError(
                "validation_error",
                f"Use the dedicated mode option instead of --param {name}.",
            )
        if name not in allowed:
            raise ClientError(
                "validation_error",
                f"Unsupported parameter for this command: {name}.",
            )
        if not param_value:
            raise ClientError(
                "validation_error",
                f"Parameter {name} must not be empty.",
            )
        if name in params:
            raise ClientError(
                "validation_error",
                f"Parameter {name} was supplied more than once.",
            )
        params[name] = param_value
    return params


def selected_headers(headers: Any) -> dict[str, str]:
    result: dict[str, str] = {}
    for name, value in headers.items():
        normalized = name.lower()
        if normalized in USAGE_HEADERS or normalized == "retry-after":
            result[normalized] = value
    return result


def decode_json(raw: bytes, context: str) -> Any:
    try:
        return json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ClientError(
            "response_error",
            f"{context} returned malformed JSON.",
        ) from exc


def request_json(
    endpoint: str,
    params: dict[str, str],
    api_key: str,
    timeout: float,
    max_attempts: int,
) -> tuple[Any, dict[str, str]]:
    url = f"{BASE_URL}/{endpoint}?{urlencode(params)}"
    for attempt in range(1, max_attempts + 1):
        authorization_header = f"Bearer {api_key}"
        request = Request(
            url,
            headers={
                "Accept": "application/json",
                "Authorization": authorization_header,
                "User-Agent": "visor/0.1.0",
            },
            method="GET",
        )
        try:
            with urlopen(request, timeout=timeout) as response:
                payload = decode_json(response.read(), endpoint)
                return payload, selected_headers(response.headers)
        except HTTPError as exc:
            raw = exc.read()
            try:
                body = decode_json(raw, endpoint)
            except ClientError:
                body = {"message": "The API returned a non-JSON error body."}
            retryable = exc.code in {429, 503}
            if retryable and attempt < max_attempts:
                retry_after = exc.headers.get("Retry-After")
                try:
                    delay = float(retry_after) if retry_after else 2 ** (attempt - 1)
                except ValueError:
                    delay = 2 ** (attempt - 1)
                time.sleep(min(max(delay, 0.0), 60.0))
                continue
            raise ClientError(
                "api_error",
                f"Visor returned HTTP {exc.code}.",
                status=exc.code,
                response=body,
                headers=selected_headers(exc.headers),
            ) from exc
        except URLError as exc:
            raise ClientError(
                "transport_error",
                f"Unable to reach the Visor Public API: {exc.reason}",
            ) from exc
        except TimeoutError as exc:
            raise ClientError(
                "transport_error",
                "The Visor Public API request timed out.",
            ) from exc
    raise ClientError("internal_error", "Retry loop exited unexpectedly.")


def read_cache(
    cache_file: Path,
    query: dict[str, str],
    ttl_seconds: int,
) -> dict[str, Any] | None:
    try:
        cached = json.loads(cache_file.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ClientError(
            "cache_error",
            f"Unable to read valid JSON from cache file {cache_file}.",
        ) from exc
    if cached.get("query") != query:
        return None
    cached_at = cached.get("retrieved_epoch")
    if not isinstance(cached_at, (int, float)):
        return None
    if time.time() - cached_at > ttl_seconds:
        return None
    output = dict(cached)
    output.pop("retrieved_epoch", None)
    output["cached"] = True
    output["request_count"] = 0
    return output


def write_cache(cache_file: Path, output: dict[str, Any]) -> None:
    cache_file.parent.mkdir(parents=True, exist_ok=True)
    cached = dict(output)
    cached["retrieved_epoch"] = time.time()
    descriptor: int | None = None
    temporary: Path | None = None
    try:
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{cache_file.name}.",
            suffix=".tmp",
            dir=cache_file.parent,
        )
        temporary = Path(temporary_name)
        handle = os.fdopen(
            descriptor,
            "w",
            encoding="utf-8",
            newline="\n",
        )
        descriptor = None
        with handle:
            json.dump(cached, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        temporary.replace(cache_file)
    except (OSError, TypeError, ValueError) as exc:
        raise ClientError(
            "cache_error",
            f"Unable to write cache file {cache_file}.",
        ) from exc
    finally:
        if descriptor is not None:
            try:
                os.close(descriptor)
            except OSError:
                pass
        if temporary is not None:
            try:
                temporary.unlink(missing_ok=True)
            except OSError:
                pass


def run_facets(args: argparse.Namespace, api_key: str) -> dict[str, Any]:
    params = parse_params(args.param, FACET_PARAMS)
    params.update(mode_params(args))
    params["facets"] = args.facets
    params["facet_value_limit"] = str(args.facet_value_limit)
    if args.metric:
        params["metric"] = args.metric
    if args.facet_sort:
        params["sort"] = args.facet_sort

    cache_file = Path(args.cache_file) if args.cache_file else None
    if cache_file:
        cached = read_cache(cache_file, params, args.cache_ttl_seconds)
        if cached is not None:
            return cached

    payload, usage = request_json(
        "facets",
        params,
        api_key,
        args.timeout,
        args.max_attempts,
    )
    if not isinstance(payload, dict) or not isinstance(payload.get("data"), dict):
        raise ClientError(
            "response_error",
            "Facet response did not contain the expected data object.",
        )
    output = {
        "ok": True,
        "retrieved_at": utc_now(),
        "source": f"{BASE_URL}/facets",
        "docs": "https://api.visor.vin/docs",
        "cached": False,
        "request_count": 1,
        "query": params,
        "usage": [usage],
        "response": payload,
    }
    if cache_file:
        write_cache(cache_file, output)
    return output


def mode_params(args: argparse.Namespace) -> dict[str, str]:
    if args.mode == "active":
        if args.sold_within_days or args.snapshot_date:
            raise ClientError(
                "validation_error",
                "Active mode cannot use sold or snapshot options.",
            )
        return {"inventory_status": "active"}
    if args.mode == "sold":
        if args.snapshot_date:
            raise ClientError(
                "validation_error",
                "Sold mode cannot use --snapshot-date.",
            )
        params = {"inventory_status": "sold"}
        if args.sold_within_days:
            params["sold_within_days"] = str(args.sold_within_days)
        return params
    if not args.snapshot_date:
        raise ClientError(
            "validation_error",
            "Snapshot mode requires --snapshot-date YYYY-MM-DD.",
        )
    if args.sold_within_days:
        raise ClientError(
            "validation_error",
            "Snapshot mode cannot use --sold-within-days.",
        )
    try:
        datetime.strptime(args.snapshot_date, "%Y-%m-%d")
    except ValueError as exc:
        raise ClientError(
            "validation_error",
            "--snapshot-date must use YYYY-MM-DD.",
        ) from exc
    return {"snapshot_date": args.snapshot_date}


def run_listings(args: argparse.Namespace, api_key: str) -> dict[str, Any]:
    base_params = parse_params(args.param, LISTING_PARAMS)
    base_params.update(mode_params(args))
    base_params["fields"] = args.fields
    base_params["limit"] = str(args.limit)

    rows: list[Any] = []
    usage: list[dict[str, str]] = []
    page_offsets: list[int] = []
    offset = args.offset
    next_offset: Any = offset
    total: Any = None
    pages_fetched = 0

    while pages_fetched < args.pages and next_offset is not None:
        page_params = dict(base_params)
        page_params["offset"] = str(offset)
        page_offsets.append(offset)
        payload, headers = request_json(
            "listings",
            page_params,
            api_key,
            args.timeout,
            args.max_attempts,
        )
        if not isinstance(payload, dict):
            raise ClientError(
                "response_error",
                "Listing response was not a JSON object.",
            )
        page_rows = payload.get("data")
        pagination = payload.get("pagination")
        if not isinstance(page_rows, list) or not isinstance(pagination, dict):
            raise ClientError(
                "response_error",
                "Listing response did not match {data,pagination}.",
            )
        rows.extend(page_rows)
        usage.append(headers)
        pages_fetched += 1
        total = pagination.get("total", total)
        next_offset = pagination.get("next_offset")
        if next_offset is None:
            break
        try:
            offset = int(next_offset)
        except (TypeError, ValueError) as exc:
            raise ClientError(
                "response_error",
                "pagination.next_offset was not an integer or null.",
            ) from exc

    return {
        "ok": True,
        "retrieved_at": utc_now(),
        "source": f"{BASE_URL}/listings",
        "docs": "https://api.visor.vin/docs",
        "mode": args.mode,
        "request_count": pages_fetched,
        "query": base_params,
        "usage": usage,
        "data": rows,
        "pagination": {
            "requested_offset": args.offset,
            "page_offsets": page_offsets,
            "pages_fetched": pages_fetched,
            "rows_returned": len(rows),
            "total_at_request_time": total,
            "next_offset": next_offset,
        },
    }


def positive_int(value: str) -> int:
    try:
        parsed = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("must be an integer") from exc
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return parsed


def nonnegative_int(value: str) -> int:
    try:
        parsed = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("must be an integer") from exc
    if parsed < 0:
        raise argparse.ArgumentTypeError("must be zero or greater")
    return parsed


def positive_float(value: str) -> float:
    try:
        parsed = float(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("must be a number") from exc
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return parsed


def bounded_int(minimum: int, maximum: int):
    def parse(value: str) -> int:
        parsed = positive_int(value)
        if parsed < minimum or parsed > maximum:
            raise argparse.ArgumentTypeError(
                f"must be between {minimum} and {maximum}",
            )
        return parsed

    return parse


def build_parser() -> argparse.ArgumentParser:
    parser = JsonArgumentParser(
        description="Query Visor's supported Public API without exposing credentials.",
    )
    parser.add_argument("--timeout", type=positive_float, default=30.0)
    parser.add_argument("--max-attempts", type=bounded_int(1, 5), default=3)
    subparsers = parser.add_subparsers(dest="command", required=True)

    facets = subparsers.add_parser("facets", help="Discover canonical facet values.")
    facets.add_argument("--facets", required=True)
    facets.add_argument(
        "--facet-value-limit",
        type=bounded_int(1, 100),
        default=100,
    )
    facets.add_argument("--metric")
    facets.add_argument(
        "--facet-sort",
        choices=["count", "-count", "metric", "-metric"],
    )
    facets.add_argument("--param", action="append", default=[], metavar="NAME=VALUE")
    facets.add_argument(
        "--mode",
        choices=["active", "sold", "snapshot"],
        default="active",
    )
    facets.add_argument("--sold-within-days", type=positive_int)
    facets.add_argument("--snapshot-date")
    facets.add_argument("--cache-file")
    facets.add_argument(
        "--cache-ttl-seconds",
        type=positive_int,
        default=86400,
    )

    listings = subparsers.add_parser(
        "listings",
        help="Search active, sold, or snapshot inventory.",
    )
    listings.add_argument(
        "--mode",
        choices=["active", "sold", "snapshot"],
        default="active",
    )
    listings.add_argument("--sold-within-days", type=positive_int)
    listings.add_argument("--snapshot-date")
    listings.add_argument("--fields", default=DEFAULT_FIELDS)
    listings.add_argument("--limit", type=bounded_int(1, 100), default=100)
    listings.add_argument("--offset", type=nonnegative_int, default=0)
    listings.add_argument("--pages", type=bounded_int(1, 100), default=1)
    listings.add_argument("--param", action="append", default=[], metavar="NAME=VALUE")
    return parser


def main() -> int:
    if any(KEY_PATTERN.search(argument) for argument in sys.argv[1:]):
        emit_json(
            {
                "ok": False,
                "error": {
                    "type": "credential_error",
                    "message": (
                        "A command argument resembles a Visor API key; "
                        "use VISOR_API_KEY only."
                    ),
                },
            },
            file=sys.stderr,
        )
        return 1

    parser = build_parser()
    args = parser.parse_args()
    try:
        api_key = os.environ.get("VISOR_API_KEY", "")
        if not api_key:
            raise ClientError(
                "configuration_error",
                "VISOR_API_KEY is not set in the environment.",
            )
        if args.command == "facets":
            output = run_facets(args, api_key)
        else:
            output = run_listings(args, api_key)
    except ClientError as exc:
        error = {
            "ok": False,
            "error": {
                "type": exc.error_type,
                "message": exc.message,
                **exc.details,
            },
        }
        emit_json(error, file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        error = {
            "ok": False,
            "error": {
                "type": "interrupted",
                "message": "Request interrupted.",
            },
        }
        emit_json(error, file=sys.stderr)
        return 130

    emit_json(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
