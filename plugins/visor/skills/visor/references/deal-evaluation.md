# Deal evaluation and market context

Compare real acquisition and ownership economics without confusing sticker,
listing, and transaction prices. Accept structured listings from Visor or any
other source; this skill does not require Visor.

## Ground rules

- Default the payment path to **CASH**. Add financing only when the user requests
  it or supplies loan terms.
- Compare equivalent cohorts: same model and generation, trim, drivetrain,
  powertrain, seating, material packages/equipment, and similar geography.
- Compare a used vehicle against the equivalent new **out-the-door (OTD)** cost,
  not an unrelated base-model MSRP or national average.
- Label advertised/listing prices separately from verified transaction prices.
- Never state a universal "used must be 20-25% cheaper" rule as fact. Thresholds
  are user-tunable decision heuristics, and every recommendation needs
  sensitivity analysis.
- Broad-market trends provide context; same-model, age, condition, equipment,
  and local comps determine the deal.

## Required inputs

Collect or mark unknown:

- exact vehicle identity and cohort attributes
- new negotiated price and used advertised price
- taxes, title/registration, destination, dealer/document fees, add-ons
- incentive eligibility and conditions
- used mileage, age, condition, warranty/CPO coverage, title/history evidence
- independent inspection estimate and immediate maintenance/tires
- expected holding period and annual mileage
- expected resale values or defensible ranges
- insurance quote difference; fuel/energy difference only when variants differ
- for financing only: down payment, APR, term, origination fees, and payment

Do not hide missing inputs inside a point estimate. Use a range or mark the
comparison incomplete.

## Build comparable cohorts

1. Normalize make/model/generation/year/trim/drivetrain/powertrain.
2. Match high-value equipment: safety suite, seating, tow package, battery or
   engine, wheels, premium packages, and warranty.
3. Separate materially different cohorts rather than "adjusting" them with an
   unsupported dollar guess.
4. Prefer local same-model comps. Expand radius or model years only when the
   sample is too small, and label the relaxation.
5. Remove or flag duplicate VINs, conditional prices, anomalous mileage, damage,
   title issues, fleet/rental history, and stale listings.
6. Report sample count, median, range, retrieval time, and whether observations
   are listings or transactions.

## Compute equivalent OTD costs

Use jurisdiction-specific tax rules when known.

```text
new_taxable_subtotal =
  negotiated_new_price
  + taxable_dealer_fees
  + taxable_add_ons
  - eligible_broad_incentives

new_otd =
  new_taxable_subtotal
  + sales_tax
  + destination_not_already_in_price
  + title_registration
  + non_taxable_fees

used_taxable_subtotal =
  advertised_used_price
  + taxable_dealer_fees
  + taxable_add_ons

used_acquisition_otd =
  used_taxable_subtotal
  + sales_tax
  + title_registration
  + non_taxable_fees
  + independent_inspection
  + immediate_maintenance
```

Do not count destination twice. Exclude incentives the shopper cannot
demonstrably receive. Keep optional protection products out unless the user
chooses them.

```text
used_discount_vs_equivalent_new =
  (new_otd - used_acquisition_otd) / new_otd
```

This is the primary used-versus-new discount. Also show the dollar difference.

## Cash and financing paths

### CASH (default)

Compare OTD cash required, the opportunity-cost assumption if the user wants
one, expected operating/repair costs, warranty value, and resale over the
holding period. Do not invent a return on cash.

### FINANCING

Calculate each vehicle separately using its actual APR and term:

```text
amount_financed = otd - down_payment
total_loan_cost = down_payment + sum(payments) + origination_fees
finance_charge = total_loan_cost - otd
```

Account for new-versus-used APR differences. Do not compare monthly payments
with different terms as though they were equivalent.

## Holding-period economics

Estimate a range:

```text
net_cost_over_holding_period =
  acquisition_or_total_loan_cost
  + maintenance_and_repairs
  + warranty_cost
  + insurance_difference
  + relevant_fuel_or_energy_difference
  - expected_resale_value
```

Include fuel only when annual mileage, efficiency, and energy prices make it
material. Keep uncertain resale, repairs, and insurance as ranges.

## Market trend evidence

Use authoritative, clickable sources and timestamp every observation:

- [FRED/BLS new vehicles CPI, CUSR0000SETA01](https://fred.stlouisfed.org/series/CUSR0000SETA01)
- [FRED/BLS used cars and trucks CPI, CUSR0000SETA02](https://fred.stlouisfed.org/series/CUSR0000SETA02)
- [BLS CPI databases](https://www.bls.gov/cpi/data.htm)
- [Cox Automotive market insights](https://www.coxautoinc.com/market-insights/)
- [Manheim Used Vehicle Value Index](https://site.manheim.com/en/services/consulting/used-vehicle-value-index.html)
- [Kelley Blue Book car news and market reporting](https://www.kbb.com/car-news/)

State the series date, geography, and whether a source measures consumer prices,
wholesale values, listings, or transactions. Do not apply a national CPI change
directly as the expected depreciation of one model.

## Sensitivity analysis

Always show at least:

- user threshold for minimum used discount
- used price or negotiated-price range
- immediate maintenance low/base/high
- resale low/base/high
- holding period alternatives
- APR alternatives when financing

If the user supplies no discount threshold, present several clearly labeled
heuristics (for example 10%, 15%, and 20%) without endorsing one as universal.
Report where the decision changes.

## Recommendation format

1. **Verdict:** new, used, close call, or insufficient evidence.
2. **Cohort quality:** exact, near, or weak; list differences.
3. **OTD comparison:** line-item new and used totals, dollar gap, discount.
4. **Holding-period range:** cash by default; financing as a separate scenario.
5. **Market context:** broad trend versus local same-model evidence.
6. **Sensitivity:** break-even price and assumptions that flip the result.
7. **Risks and unknowns:** conditional pricing, history, inspection, warranty,
   resale, or missing transaction evidence.
8. **Sources:** direct clickable links with retrieval dates.

Withhold a strong value judgment when the equivalent-new OTD, cohort quality,
or used-vehicle condition evidence is too weak.

## Reproducible worksheet

Keep unknown values null rather than coercing them to zero. Record:

- retrieval time and source URLs
- payment path, holding period, and annual mileage
- normalized cohort attributes and required equipment
- new negotiated price, destination, taxable/non-taxable fees, add-ons,
  eligible broad incentives, sales tax, title/registration, and resale range
- used advertised price, fees, add-ons, tax, title/registration, inspection,
  immediate-maintenance range, and resale range
- new and used down payment, APR, term, and origination fees when financing
- maintenance, warranty, insurance, and relevant fuel/energy differences
- the user's minimum-used-discount threshold

Classify cohort quality as:

- **Exact:** same generation, trim, drivetrain/powertrain, and material equipment.
- **Near:** one explainable noncritical difference.
- **Weak:** several differences, sparse sample, or broad-market proxy only.

Do not produce a strong buy recommendation from a weak cohort.

For a user-selected discount threshold:

```text
maximum_used_acquisition_otd =
  new_otd * (1 - user_discount_threshold)
```

Derive the maximum advertised price after subtracting used tax, fees, add-ons,
title/registration, inspection, and immediate maintenance. Where tax is a
percentage of the taxable subtotal, solve algebraically or iteratively rather
than subtracting a fixed estimate.
