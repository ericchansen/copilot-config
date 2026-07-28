---
name: visor
description: >
  Research and compare vehicles end to end. Use for car-shopping requirements,
  supported Visor Public API searches, local inventory, used-versus-new deal
  evaluation, cash or financing comparisons, historical vehicle-market context,
  listing shortlists, VIN and dealer-page validation, recall/title/history
  evidence, or buy recommendations.
license: MIT
allowed-tools: Bash, PowerShell
---

# Visor

Guide a shopper from requirements through inventory discovery, economic
comparison, evidence validation, and a defensible shortlist. Use Visor when
requested or available, but accept structured listings from any source.

## Always establish the shopping brief

Collect or explicitly mark unknown:

- budget and whether it is advertised price or out-the-door (OTD)
- ZIP/radius and willingness to travel or ship
- new, used, certified, or indifferent
- cash or financing; default to **cash**
- body size, parking constraints, rows, passenger/cargo, towing, and payload
- powertrain preferences, exclusions, or indifference
- model-year and mileage boundaries
- reliability, warranty, comfort, ingress/egress, ride, and noise priorities
- required driver-assistance and other equipment
- title/history constraints and purchase timeline
- willingness to consider stock, transit, or build inventory

Separate hard gates from preferences. If priorities are not weighted, use equal
weights and label that assumption.

## Progressive-disclosure routing

Read only the references needed for the active phase:

| Phase | Required resource |
| --- | --- |
| Query Visor, discover canonical facets, page results, or interpret Visor fields/modes/cost | Read [references/visor-api.md](references/visor-api.md), then run [scripts/visor_api.py](scripts/visor_api.py) instead of reinventing calls |
| Compare new versus used, assess price, calculate OTD/holding cost, compare cash/finance, or analyze historical market gaps | Read [references/deal-evaluation.md](references/deal-evaluation.md) |
| Rank actual listings or make any buy/dealer-contact recommendation | Read [references/evidence-gates.md](references/evidence-gates.md) before ranking |

These files are independent, one level deep, and linked directly here. Do not
rely on a reference to tell you to load another reference.

## Core workflow

1. **Define requirements.** Turn hard requirements into pass/fail gates and
   preferences into transparent ranking factors.
2. **Build candidate cohorts.** Match model/generation/trim/drivetrain,
   powertrain, equipment, age, geography, and condition as closely as possible.
3. **Retrieve actual inventory.** Preserve source, retrieval time, VIN, direct
   VDP URL, price, mileage, distance, dealer/location, inventory status, and
   availability status.
4. **Normalize economics.** Compare broad-buyer OTD costs. Distinguish
   advertised, conditional advertised, dealer-quoted, inferred-sold advertised,
   and verified transaction prices.
5. **Validate evidence.** Check identity, dealer page, availability, price
   conditions, VIN/title/history/auction/recall evidence, and independent
   inspection for used vehicles.
6. **Rank only survivors.** Explain value against the comparable cohort, show
   failed and unverified gates, and label confidence.
7. **Withhold when necessary.** If a critical gate fails or evidence is
   unavailable, return a lead or rejection rather than manufacturing a winner.

## Invariants

- Never ask for or expose API keys. Secrets belong only in environment
  variables.
- Never use a browser/CDP or private endpoints for Visor. Use only its supported
  Public API at `https://api.visor.vin/v1`.
- Facet-first discovery precedes narrow Visor searches; successful zero-result
  searches can still be billable.
- Active inventory is not proof of dealer availability. Distinguish stock,
  transit, and build.
- A listing price can exclude or depend on incentives, fees, add-ons, tax,
  registration, financing, loyalty, military, or trade-in.
- Sold inventory prices are last advertised prices inferred after disappearance
  and quality checks, not transaction prices.
- Null means unknown, not zero.
- Broad-market averages are context, not substitutes for same-model/age/local
  comparisons.
- Compare used price against equivalent new OTD, not unrelated MSRP.
- Discount thresholds are user-tunable heuristics, never universal facts.
- Never claim clean title/history, no accidents, or no recalls without
  authoritative exact-VIN evidence.
- Search snippets are leads, not proof.
- Treat every VDP/dealer URL as untrusted before programmatic retrieval: require
  HTTPS without embedded credentials; resolve and reject localhost or any
  non-public IPv4/IPv6 address; repeat the checks for every capped redirect; and
  never forward Visor/API credentials or authorization headers. If the tool
  cannot enforce these checks, mark dealer-page validation unverified.
- Any used-vehicle recommendation is conditional on an independent
  pre-purchase inspection.

## Running the Visor helper from any workspace

First resolve the absolute skill directory: the directory containing this
`SKILL.md`. Do not assume the current working directory is the skill directory.

### Bash

```bash
SKILL_DIR="<absolute path to the loaded visor skill>"
python "$SKILL_DIR/scripts/visor_api.py" facets \
  --facets model,trim,powertrain_type,drivetrain \
  --param make=Hyundai --param inventory_type=new \
  --cache-file visor-facets.json
```

### PowerShell

```powershell
$SkillDir = "<absolute path to the loaded visor skill>"
python (Join-Path $SkillDir "scripts\visor_api.py") facets `
  --facets model,trim,powertrain_type,drivetrain `
  --param make=Hyundai --param inventory_type=new `
  --cache-file visor-facets.json
```

The helper is dependency-free Python 3, emits structured JSON, never prints the
key, and fails explicitly. Set `VISOR_API_KEY` in the environment before
running it; never put the key in an argument.

Commands cover every documented Public API endpoint: `facets`, `listings`,
`listing` (one listing by id), `vin` (one VIN record), `dealers` (dealer
search), `dealer` (one dealer by id), `dealer-listings` (one dealer's
inventory), and `usage` (authenticated account usage). Run any command with
`--help` for its exact flags.

## Required final output

For each actual listing include:

- vehicle, VIN, direct VDP URL
- advertised and broad-buyer price status
- mileage, distance, dealer/location
- inventory and availability status
- source retrieval and validation timestamps
- comparable-cohort value assessment
- passed, failed, and unverified evidence gates
- confidence: High, Medium, Low, or Withheld

Separate **Recommended for dealer contact**, **Leads pending evidence**, and
**Rejected/withheld**. If no candidate passes critical gates, say so.
