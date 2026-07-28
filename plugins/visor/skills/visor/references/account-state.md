# Visor account state (favorites, hides, saved searches, preferences)

Visor's authenticated shopping account state — favorites, hidden listings,
saved searches, and shopping preferences (ZIP, filters, display, show-sold
defaults) — is **not** exposed by the documented Public API
(`https://api.visor.vin/v1`). It only exists behind the signed-in web app's
private, undocumented internal endpoints.

## Why this skill does not automate it

Visor's [Terms of Use](https://visor.vin/terms) ("Prohibited Activities")
bar automated/scripted access, reverse engineering of the Services, and
scraping outside channels Visor provides for that purpose — the documented
Public API is that channel. This applies regardless of who owns the account:
the restriction is about *how* the Services are accessed (automated tooling
vs. a person using the app), not whose data is retrieved. This skill
therefore never launches or attaches to a browser, reads cookies or session
storage, or reverse-engineers the app's request protocol to reach this data.

## What to do instead

| Situation | Action |
| --- | --- |
| User asks "what are my favorites/hidden listings/saved searches?" | Tell them this skill can't retrieve it automatically; ask them to check `https://visor.vin/account/favorites` (or the equivalent account page) themselves and share the results if useful. |
| User wants to change a shopping preference (ZIP, filters, display, show-sold) | Point them to the Visor app's account settings; do not attempt it programmatically. |
| User wants ongoing/automatic account-data integration | Explain that this would require an official authenticated endpoint or explicit written permission from Visor, which does not currently exist. |

## Discovering current support

Run `capabilities` (see [../scripts/visor_api.py](../scripts/visor_api.py))
for a machine-readable list of every supported Public API operation and the
unsupported account surface, including the reason and terms link. The
`favorites`, `hides`, `saved-searches`, and `preferences` subcommands exist
only as explicit stubs: they fail immediately with a structured
`unsupported_operation` error (`surface: "account"`) and never touch a
network, browser, or credential store. A failure here must never be
presented as an empty successful result — always surface it to the user.
