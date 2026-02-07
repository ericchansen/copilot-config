---
name: summon-the-knights-of-the-round-table
description: "Multi-model brainstorming to challenge assumptions and reach consensus. Use when needing to double-check work, validate plans, or get diverse perspectives on decisions. Invokes Claude Opus 4.5, GPT-5.2-Codex, and Gemini 3 Pro with randomized roles to debate and find common ground."
---

# Summon Knights of the Round Table

Collaborate with multiple AI models to challenge assumptions, identify blind spots, and reach well-reasoned conclusions through structured debate.

## The Knights

Three models sit at the round table:

| Knight | Model ID |
|--------|----------|
| **Claude Opus** | `claude-opus-4.5` |
| **GPT-5.2-Codex** | `gpt-5.2-codex` |
| **Gemini 3 Pro** | `gemini-3-pro-preview` |

## Workflow

### 1. Gather Context

- Read the current plan.md if it exists
- Check recent git commits: `git --no-pager log --oneline -10`
- View recent file changes: `git --no-pager diff HEAD~3 --stat`
- Identify the key decisions or changes to review

### 2. Frame the Question

Formulate a clear question or set of concerns to review. Examples:
- "Is this the right architecture approach for X?"
- "Are these the correct priorities for the next sprint?"
- "What risks or blind spots exist in this plan?"
- "Should we tackle issue A before issue B?"

### 3. Assign Roles (Randomized)

Each invocation, **randomly shuffle** which knight gets which role. Do NOT always assign the same role to the same model. Use a random number or current timestamp seconds to pick a permutation.

The three roles are:

| Role | Prompt Suffix |
|------|--------------|
| **Devil's Advocate** | "Play devil's advocate. What could go wrong? What assumptions might be flawed? Poke holes in this." |
| **Explorer** | "What alternative approaches exist? What are we missing? Think outside the box and suggest unconventional options." |
| **Steelman** | "Steelman this approach. What's strong about it? Build the best possible case, then note what would need to be true for it to succeed." |

**How to randomize:** Pick a number 0–5 (e.g. use the current second mod 6) to select one of the 6 permutations:

| # | Devil's Advocate | Explorer | Steelman |
|---|-----------------|----------|----------|
| 0 | Claude Opus | GPT-5.2-Codex | Gemini 3 Pro |
| 1 | Claude Opus | Gemini 3 Pro | GPT-5.2-Codex |
| 2 | GPT-5.2-Codex | Claude Opus | Gemini 3 Pro |
| 3 | GPT-5.2-Codex | Gemini 3 Pro | Claude Opus |
| 4 | Gemini 3 Pro | Claude Opus | GPT-5.2-Codex |
| 5 | Gemini 3 Pro | GPT-5.2-Codex | Claude Opus |

**Announce the role assignments** at the start so the user can see which knight drew which role.

### 4. First Round — Divergent Perspectives

Query all three models **in parallel** using the task tool with model override. Each gets the shared context + question + their assigned role prompt.

```
Use task tool with:
  agent_type: "general-purpose"
  model: [assigned model ID]
  prompt: [context + question + role prompt suffix]
```

### 5. Synthesis Round

Compare the three responses:
- Identify points of agreement across all three (high confidence)
- Identify points of agreement between two of three (moderate confidence)
- Identify points of unique disagreement (need resolution)
- Identify unique insights from each

### 6. Resolution Round

If disagreements exist, query all three models again with the conflicting viewpoints:

```
prompt: "Knight A (role) said [X]. Knight B (role) said [Y]. Knight C (role) said [Z]. 
        These points conflict: [specific conflicts].
        Which perspective is strongest and why? 
        Can they be reconciled? What's the best path forward?"
```

### 7. Reach Consensus

Synthesize the final consensus:
- List agreed-upon conclusions
- Note any unresolved tensions with recommendations
- Provide actionable next steps

## Output Format

Present results as:

```markdown
## ⚔️ Round Table Review: [Topic]

### Role Assignments
| Knight | Role |
|--------|------|
| [Model] | Devil's Advocate |
| [Model] | Explorer |
| [Model] | Steelman |

### Context Reviewed
- [What was analyzed]

### Key Findings

**Unanimous Agreements (High Confidence):**
1. [Point all three models agreed on]

**Majority Agreements (2 of 3):**
1. [Point two models agreed on — dissenter's reason noted]

**Resolved Disagreements:**
1. [Initial conflict] → [Resolution reached]

**Open Questions:**
1. [Unresolved tension — recommendation]

### Recommended Actions
1. [Specific action]
2. [Specific action]
```

## Example Invocations

"Summon knights of the round table to check our checkout implementation approach"

"Summon knights of the round table to validate our architecture decision for the new API"

"Summon knights of the round table to review this refactoring plan"
