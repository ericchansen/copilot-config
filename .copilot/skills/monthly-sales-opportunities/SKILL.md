---
name: monthly-sales-opportunities
description: >-
  Generate monthly SE Opportunity Update reports for your pod. Use when the user asks to
  create, generate, or write their monthly sales opportunity update, monthly SE report,
  opportunity review, or monthly account summary. Also use when the user mentions preparing
  their monthly update for their pod lead, SE manager, or solution area review.
---

# Monthly Sales Opportunities

Generate a structured monthly SE Opportunity Update report matching the standard SDP pod template. The report covers Portfolio Summary, top opportunity details, MACC account snapshots, and a Contribution/Impact summary. Output is intermediate markdown, then converted to `.docx` for OneNote paste.

> **Real examples** may exist in the local `examples/` folder alongside this skill. Reference those for tone, depth, and formatting calibration — but never include real customer data in generated artifacts stored in source control.

## Workflow

### Step 1: Gather Inputs from the User

Ask the user for the following. If stored memories exist from a prior session (e.g., accounts, solution area, pod number), offer those as defaults.

1. **Reporting month** — e.g., "January 2026" (default: previous calendar month)
2. **Solution area** — e.g., "Apps & AI", "Data", "Infrastructure" (no default unless stored)
3. **Pod name/number** — e.g., "Pod 22" (no default unless stored)
4. **Accounts to cover** — list of customer accounts (no default unless stored)
5. **Number of top opportunities** — default: 3 (the template calls for top 3)

After the first successful run, **store the user's answers in memory** (solution area, pod number, accounts) so they can be offered as defaults next time.

### Step 2: Query WorkIQ for Monthly Evidence

> **Prerequisite:** The user must be connected to the Microsoft corporate VPN and have run `az login --tenant 72f988bf-86f1-41af-91ab-2d7cd011db47` for MSX MCP tools to work.

Run the following WorkIQ queries to gather raw material. Adapt the account names based on the user's input from Step 1.

**Query 1 — Overall Month Summary:**
> "What are my key accomplishments, customer engagements, and contributions for [MONTH YEAR]? Include meetings, emails, Teams conversations, and documents related to [ACCOUNT1], [ACCOUNT2], [ACCOUNT3]. Focus on technical work, customer blockers resolved, architecture guidance, and deal progression."

**Query 2 — Per-Account Deep Dive (repeat for each account):**
> "For [ACCOUNT NAME] during [MONTH YEAR], what specific meetings, emails, and Teams conversations did I participate in? What technical topics were discussed? Were there any decisions made, blockers resolved, or deliverables created? Include links where possible."

**Query 3 — Contribution & Internal Work:**
> "What internal contributions did I make during [MONTH YEAR]? Include hiring interviews, guild participation, enablement sessions, workshops, internal tools or artifacts created, and any cross-team collaboration."

### Step 2.5: Query MSX MCP for Structured Deal Data

Use the **msx-mcp** MCP tools to pull precise opportunity and pipeline data. This replaces the guesswork WorkIQ does for MSX-specific data (opportunity stages, revenue, deal teams).

**Tool 1 — Pipeline Overview:**
Call `get_pipeline_summary` (no args) to get the user's full pipeline broken down by sales stage with dollar totals. Use this for the Portfolio Summary roll-up metrics.

**Tool 2 — Top Opportunity Suggestions:**
Call `suggest_top_opportunities` with `count` matching the user's requested number of opportunities (default 3) and `criteria: "by_value"`. This returns ranked opportunities with forecast comments and rationale — use as the starting point for which opportunities to feature.

**Tool 3 — Opportunity Details (repeat per featured opportunity):**
For each opportunity the user confirms they want to feature, call `get_opportunity_details` with the `opportunity_id` from the suggestion results. This provides MSX ID, sales stage, estimated value, billed revenue, forecast comments, deal type, and sales play.

**Tool 4 — Account Team Context:**
Call `get_account_team` (no args) to get the user's account assignments, roles, and solution areas. Use for the Owner & V-Team fields.

**Tool 5 — Deal Team for V-Team (optional):**
Call `get_my_deals` to see all deal team memberships. Cross-reference with the featured opportunities to identify who else is on each deal.

**Merging MSX + WorkIQ Data:**
- MSX MCP provides: opportunity names, MSX IDs, sales stages, dollar values, forecast comments, deal teams, account roles
- WorkIQ provides: meeting evidence, email context, Teams conversations, deliverables, internal contributions
- Use MSX data for structured fields (dollar amounts, stages, IDs); use WorkIQ for narrative evidence (what happened, what was discussed)

### Step 3: Generate Intermediate Markdown

Using the WorkIQ results and the template structure below, generate a markdown file. Save it to the session `files/` directory as `monthly-update-YYYY-MM.md`.

**Rules:**
- Follow the exact template structure from the **Report Template** section below
- Fill in every field you have evidence for from WorkIQ
- For fields WorkIQ cannot answer, use the placeholder format: `[___]`
- Common placeholder fields: MSX Opportunity ID, exact ACR dollar figures, MCEM stage number, MACC enrollment details, partner assignments
- Be specific and evidence-based — do not fabricate customer data or metrics
- Match the tone of a professional SE update: concise, factual, technically grounded
- Organize Opportunity Details by impact/importance, not alphabetically

### Step 4: Review with the User

Present the markdown draft to the user. Ask:
- "Are the top 3 opportunities correct, or should I swap any out?"
- "Any placeholder fields you can fill in now?"
- "Anything to add or remove from the Contribution/Impact section?"

Iterate on the markdown until the user is satisfied.

### Step 5: Convert to .docx

Once the markdown is finalized:

1. **Invoke the `docx` skill** to convert the markdown to a Word document
2. Save as `monthly-update-YYYY-MM.docx` in the session `files/` directory
3. The user will copy-paste the docx content into OneNote

---

## Report Template

The report has 4 major sections. Each section uses a **Field / Description / Input** table format.

### Section 1: Portfolio Summary

| Field | Description | Input / Insight |
|-------|-------------|-----------------|
| Month & Coverage | Reporting month and accounts covered | [MONTH]. [ACCOUNT LIST]. |
| Top 3 Highlights | Key wins or movements | 1. [Account: highlight] 2. [Account: highlight] 3. [Account: highlight] |
| Roll-Up Metrics | Quick stats on performance | [ACR, attainment %, MoM growth, YoY growth, or other relevant metrics] |
| Other 1 | Any other business / Comments | [Optional — EBCs, pipeline notes, territory changes, etc.] |
| Other 2 | Any other business / Comments | [Optional] |

### Section 2: Opportunity Details (repeat per opportunity — top 3)

| Field | Description | Input / Insight |
|-------|-------------|-----------------|
| Account / Opp Name / MSX ID | Customer and opportunity | [Account] – [Opportunity Name] [MSX ID] |
| Solution Play & FY26 Workloads | Solution Play + Azure Services | [Solution Play]; Workloads: [Azure services list] |
| Sales Stage & TD Status | MCEM Stage + TD win/loss/progressing | MCEM Stage [N] - [Phase]; [status]. |
| Dollar Movement | U2C or Closed | [U2C/Closed amount]; [committed/uncommitted]. |
| Close Plan (30–60d) | Key next steps | [Next steps in the next 30-60 days] |
| Risks / Blockers | Type, impact, owner | [Risk description]. Competition: [competitors]. |
| MACC Signal | MACC impact (if applicable) | [Consumed under MACC / Will add to MACC / N/A] |
| Asks / Help Needed | Specific support | [What you need from leadership, product teams, etc.] |
| Owner & V-Team | SE + Contributors | Owner: [name]; SE: [names]; Partner: [if applicable] |
| Other 1 | Any other business / Comments | [Optional] |
| Other 2 | Any other business / Comments | [Optional] |

### Section 3: MACC Account Snapshot (if applicable)

| Field | Description | Input / Insight |
|-------|-------------|-----------------|
| MACC Basics | Enrollment, term, growth | [Enrollment type; term length; growth %] |
| Execution View | PBO vs. Budget | [PBO %; Coverage %] |
| Consumption Plan Moves | Adds/skips in MSX | [Milestone changes] |
| Investments & Programs | ECIF, Unified, Marketplace | [Investment details] |
| Risks & Mitigation | Shortfall plan | [Risk description and mitigation plan] |
| Asks / Help Needed | Specific support | [Requests] |
| Other 1 | Any other business / Comments | [Optional] |
| Other 2 | Any other business / Comments | [Optional] |

### Section 4: Contribution / Impact Summary

| Customer | Engagement Type | Contribution w/ Impact |
|----------|----------------|----------------------|
| [Customer or Internal team] | [Type — see descriptors below] | [What you did + what impact it had. Include artifacts left behind.] |

**Engagement Type Descriptors:**
- Architecture Design
- Envisioning Workshop
- Technical Briefing
- Proof of Concept (POC)
- Always-On Hiring
- Insiders Assistance
- Pace Setters Contribution
- Implementation Guidance
- Modernization Workshop
- AI Architecture / Enablement
- Discovery Calls
- Guild / Community Leadership

**Contribution w/ Impact Guidelines:**
- Describe the contribution AND the impact it made
- Note any artifacts left behind (architecture diagrams, presentations, code samples)
- Include audience size for events/sessions
- Be honest about your role level: "attended," "contributed to," "led," "created"

---

## Example (Fabricated Data)

Below is a fabricated example using fictional companies. This illustrates the expected tone, depth, and structure.

### Portfolio Summary

| Field | Description | Input / Insight |
|-------|-------------|-----------------|
| Month & Coverage | Reporting month and accounts covered | January 2026. Contoso Ltd, Zava Corp, Northwind Traders. |
| Top 3 Highlights | Key wins or movements | 1. Contoso: Azure OpenAI-powered customer service agent moving to production; strong exec sponsorship. 2. Zava Corp: Multi-model AI assistant migration from AWS to Azure Foundry gaining momentum. 3. Northwind: AKS modernization POC completed successfully; partner engaged for implementation. |
| Roll-Up Metrics | Quick stats on performance | Strong technical engagement across all accounts. Multiple active AI and modernization opportunities trending toward TD win in Feb/March. |
| Other 1 | Any other business / Comments | Contoso EBC occurring second week of February; expected to influence direction of all Contoso workloads. |
| Other 2 | Any other business / Comments | |

### Opportunity 1

| Field | Description | Input / Insight |
|-------|-------------|-----------------|
| Account / Opp Name / MSX ID | Customer and opportunity | Contoso Ltd – Azure AI Customer Service Agent 7-XXXXXXXXXXX |
| Solution Play & FY26 Workloads | Solution Play + Azure Services | Innovate with Azure AI Apps & Agents; Service Transformation with AI. Workloads: AOAI, AI Search, Cosmos DB, App Service. |
| Sales Stage & TD Status | MCEM Stage + TD win/loss/progressing | MCEM Stage 3 - Prove & Plan; progressing. |
| Dollar Movement | U2C or Closed | $22,000 ACR consumed; uncommitted for billed revenue. |
| Close Plan (30–60d) | Key next steps | Support production readiness review. Coordinate with Contoso platform team on security review. Target TD win by end of February. |
| Risks / Blockers | Type, impact, owner | Data residency requirements may require architecture changes. Competition from AWS Bedrock. |
| MACC Signal | MACC impact (if applicable) | Will consume under MACC. |
| Asks / Help Needed | Specific support | Product team support for Responsible AI review acceleration. |
| Owner & V-Team | SE + Contributors | Owner: Sarah Chen; SE: [Your Name], Alex Rivera |
| Other 1 | Any other business / Comments | Strong internal champion in Contoso's VP of Digital. |
| Other 2 | Any other business / Comments | ACR projected to grow from ~1,200 in Dec → ~2,000 in January. |

### Contribution / Impact Summary

| Customer | Engagement Type | Contribution w/ Impact |
|----------|----------------|----------------------|
| Contoso Ltd | Architecture Design; Technical Briefing | Delivered architecture review for AI agent deployment. Defined requirements in shared Loop document. Coordinated product team alignment on Responsible AI blockers. |
| Zava Corp | AI Architecture; Foundry Enablement | Guided multi-model strategy (AOAI + Anthropic via Foundry). Clarified deployment paths and API gateway patterns for model routing. |
| Northwind Traders | POC; Modernization Workshop | Supported AKS modernization POC. Delivered container migration guidance and helped partner (Fabrikam Consulting) scope implementation. |
| MCAPS (Internal) | Always-On Hiring | Interviewed 2 candidates for SE roles. |

---

## Placeholder Reference

When WorkIQ can't provide a value, use these placeholders so the user can fill them in:

| Placeholder | Meaning |
|-------------|---------|
| `[___]` | Generic unknown — fill in manually |
| `[MSX ID: ___]` | MSX Opportunity ID needed (try `get_opportunity_details`) |
| `[ACR: $___]` | ACR dollar figure needed (check MSX `estimatedvalue` / `msp_billedrevenue`) |
| `[MCEM Stage: ___]` | MCEM stage number needed (try `get_opportunity_details` for `msp_activesalesstage`) |
| `[U2C: $___]` | Uncommitted-to-close amount needed |
| `[MACC: ___]` | MACC enrollment details needed |
| `[Partner: ___]` | Partner assignment needed |

## Usage Notes

- Run monthly, ideally in the second week of the month (covering the prior month)
- **VPN required:** Connect to Microsoft corporate VPN before running (MSX Dataverse is IP-restricted)
- **Azure CLI auth:** Run `az login --tenant 72f988bf-86f1-41af-91ab-2d7cd011db47` before the first run each session
- Save output to session `files/` for historical reference
- The docx output is optimized for copy-paste into OneNote
- Organize opportunities by impact/importance, not alphabetically
- MSX MCP provides structured data (IDs, stages, values); WorkIQ provides narrative evidence (meetings, emails)
- Be conservative with claims — only include what MSX or WorkIQ can evidence
- When in doubt, leave a placeholder rather than fabricate
