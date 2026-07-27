# Visor Public API reference

Use the live documentation as the authority:

- [Documentation](https://api.visor.vin/docs)
- [Documentation index](https://api.visor.vin/docs/llms.txt)
- [Public OpenAPI](https://api.visor.vin/v1/openapi.json)
- [Filters and facets](https://api.visor.vin/docs/filters-and-facets.md)
- [How the data works](https://api.visor.vin/docs/data-works.md)
- [Errors and retries](https://api.visor.vin/docs/errors-and-retries.md)
- [Usage tiers](https://api.visor.vin/docs/usage-tiers.md)

## Stable endpoints

| Endpoint | Purpose |
| --- | --- |
| `GET /v1/facets` | Discover canonical categorical values, ranges, and stats |
| `GET /v1/listings` | Search active, sold, or historical snapshot inventory |
| `GET /v1/listings/{listing_id}` | Retrieve one listing detail record |
| `GET /v1/vins/{vin}` | Retrieve the current or latest known VIN record |
| `GET /v1/dealers` | Search public dealer summaries |
| `GET /v1/dealers/{dealer_id}` | Retrieve one dealer |
| `GET /v1/dealers/{dealer_id}/listings` | Search attributed dealer inventory |
| `GET /v1/usage` | Summarize authenticated account usage |

Normal endpoints require `Authorization: Bearer` with the `VISOR_API_KEY`
environment value. Responses use stable `snake_case`.

## Listing search essentials

- `limit`: default 50, maximum 100
- `offset`: zero-based page offset
- `pagination.next_offset`: next page cursor; stop when null
- `fields`: comma-separated projection; never a filter
- `include`: optional `price_history` and `options`
- `inventory_type`: `new`, `used`, `certified`; `cpo` aliases `certified`
- `inventory_status`: `active` or `sold`
- `sold_within_days`: positive recent-sold window
- `snapshot_date`: historical active inventory date, `YYYY-MM-DD`
- `availability_status`: `stock`, `transit`, or `build`
- `postal_code` plus `radius`: local search, maximum radius 500 miles
- `sort=distance`: requires geography
- `distance_miles`: must be requested in `fields`

Common categorical filters include `make`, `model`, `model_code`, `trim`,
`year`, `version`, `body_type`, `drivetrain`, `transmission`, `fuel_type`,
`powertrain_type`, colors, `seating_capacity`, `options_packages`, `features`,
and `dealer_type`. Common numeric filters include `min_price`, `max_price`,
`min_mileage`, `max_mileage`, `min_msrp`, `max_msrp`,
`min_days_on_market`, and `max_days_on_market`.

Use the OpenAPI document instead of this summary when adding a parameter.
Unknown parameters and unknown projected fields are rejected.

## Facets

`facets` is required. Useful discovery sequences:

1. `facets=make,inventory_type`
2. apply `make`, then `facets=model,powertrain_type`
3. apply canonical `model`, then `facets=trim,drivetrain,year`
4. apply the chosen cohort, then `facets=price,miles,availability_status`

Categorical buckets are under `data.facets`. Numeric buckets are under
`data.range_facets`; summary statistics are under `data.stats`. Check bucket
`count` before relying on a metric. Small samples can return
`null_reason=insufficient_sample`.

## Meaning limits

- Active inventory is current API evidence, not dealer confirmation.
- Sold inventory is inferred after a listing has been absent from a dealer feed
  for at least three days and passes quality checks.
- Sold price is last advertised price, not the negotiated transaction price.
- `price` may exclude conditional incentives and out-the-door costs.
- `days_on_market` is an observation-based estimate, not dealer-certified lot
  age.
- Null means Visor does not have a confident value.
- Totals are point-in-time paging aids. Use `snapshot_date` for repeatable
  historical active inventory.

## Billing and retry behavior

Successful requests are billed per request, not per returned row; successful
zero-result searches are billable. Validation, authentication, permission,
billing, rate-limit, platform errors, and detail 404s are not successful paid
responses according to the error documentation.

Retry only:

- `429`: honor `Retry-After`
- `503`: bounded exponential backoff

Do not retry `400`, `401`, `402`, `403`, or normal `404` responses.
