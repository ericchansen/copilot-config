# Vehicle shortlist evidence gates

Apply these gates before a buy recommendation. Preserve evidence URLs and
timestamps.

| Gate | Pass evidence | Failure or unverified handling | Critical |
| --- | --- | --- | --- |
| Source-active | Current structured row says active | Mark stale/unverified; do not recommend | Yes |
| Identity | VIN, year, model, trim agree across row and VDP | Reject VIN/model mismatch | Yes |
| VDP reachable | Exact dealer VDP retrieved directly when permitted | Keep only as a lead; snippets are not proof | Yes |
| Dealer availability | Dealer page or timestamped dealer confirmation supports status | Label stock/transit/build and unconfirmed | Yes |
| Broad-buyer price | Itemized nonconditional price and fees | Mark conditional; withhold precise value | Yes |
| Title/brand | Exact-VIN NMVTIS-approved evidence | Say not verified; never claim clean title | Used: yes |
| Accident/owner history | Dated reputable exact-VIN history report | Say not verified; never claim no accidents | Used: yes |
| Auction evidence | Exact-VIN source and disposition understood | Escalate unexplained auction/damage evidence | Used: yes |
| Recall | Dated NHTSA exact-VIN lookup | Mark lookup unavailable or open recall | Yes |
| Independent inspection | Acceptable seller-independent report | Recommendation conditional or withheld | Used: yes |
| Cohort value | Comparable local cohort and OTD normalization | Do not claim good value | Yes |

## Direct dealer-page validation

Fetch the exact VDP through direct HTTP when legally and technically permitted.
Do not bypass authentication, anti-bot controls, robots policy, or access
restrictions. Confirm that VIN, year/model/trim, price, mileage, dealer, and
availability agree with the source row.

Before any programmatic request:

- Parse the URL and accept only `https` with no embedded username or password.
- Resolve the hostname immediately before connecting. Reject localhost names
  and every IPv4/IPv6 address that is loopback, private, link-local, multicast,
  unspecified, reserved, or otherwise non-public.
- Disable automatic redirects when possible. Apply the same scheme, user-info,
  DNS, and IP checks to every redirect target before following it, with an
  explicit redirect cap supported by the tool. If redirects cannot be inspected
  and capped, do not fetch.
- Never copy Visor/API credentials, cookies, authorization headers, or other
  origin credentials to a dealer/VDP origin.

If direct HTTP cannot retrieve or verify the page, mark the gate unverified.
Never substitute a search-result snippet or cached third-party page as proof.

## Direct HTTP validation record

Capture:

```json
{
  "validated_at": "YYYY-MM-DDTHH:MM:SSZ",
  "requested_url": null,
  "final_url": null,
  "http_status": null,
  "vin_match": null,
  "vehicle_match": null,
  "price_match": null,
  "mileage_match": null,
  "dealer_match": null,
  "availability_text": null,
  "price_conditions": [],
  "evidence_excerpt": null,
  "blocked_or_unverifiable_reason": null
}
```

Do not store cookies, authorization headers, personal data, or unrelated page
content.

## Conditional-price normalization

For each advertised discount, classify:

- broadly available
- financing-only
- lease-only
- loyalty/conquest
- military/first-responder/student
- trade/trade-in
- unknown eligibility

Exclude ineligible or unknown conditional discounts from the broad-buyer price.
Add mandatory dealer fees and add-ons. Keep tax/title/registration separate for
the shopper's jurisdiction.

## Suspicious-discount checklist

Before treating a low price as value, verify:

- exact trim, drivetrain, powertrain, model year, and equipment
- mileage and odometer units
- title brands, structural or flood damage, accidents, and lemon/buyback status
- rental, fleet, commercial, or auction history
- unresolved recalls
- price conditions and mandatory add-ons
- duplicate or stale listing
- stock versus transit/build status
- VIN and VDP consistency
- independent inspection findings

An unexplained outlier is a risk flag, not a bargain conclusion.

## Confidence

- **High:** identity, VDP, availability, broad-buyer pricing, required history,
  recall, and inspection evidence support the recommendation.
- **Medium:** the candidate is promising, but one noncritical check remains.
- **Low:** multiple material facts are unverified; present only as a lead.
- **Withheld:** a critical gate failed or could not be verified.

Used candidates cannot receive High confidence before an acceptable independent
inspection. An active API row alone is Low confidence at best.

## Recall and title sources

- [NHTSA recalls](https://www.nhtsa.gov/recalls)
- [NHTSA recalls API documentation](https://www.nhtsa.gov/nhtsa-datasets-and-apis)
- [NMVTIS consumer access and approved providers](https://vehiclehistory.bja.ojp.gov/nmvtis_vehiclehistory)

Commercial history reports can add accident, owner, service, and auction
evidence, but describe exactly what the dated report says. Do not generalize a
missing event into proof that no event occurred.
