---
name: summon-the-knights-of-the-round-table
description: "Multi-model brainstorming to challenge assumptions and reach consensus. Use when needing to double-check work, validate plans, or get diverse perspectives on decisions. Invokes GPT-5.2-Codex and Gemini 3 Pro to debate and find common ground."
---

# Summon Knights of the Round Table

Collaborate with multiple AI models to challenge assumptions, identify blind spots, and reach well-reasoned conclusions through structured debate.

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

### 3. First Round - Divergent Perspectives

Query both models with the context and question. Use the task tool with model override.

**GPT-5.2-Codex Query:**
```
Use task tool with:
  agent_type: "general-purpose"
  model: "gpt-5.2-codex"
  prompt: [context + question + "Play devil's advocate. What could go wrong? What assumptions might be flawed?"]
```

**Gemini 3 Pro Query:**
```
Use task tool with:
  agent_type: "general-purpose"
  model: "gemini-3-pro-preview"
  prompt: [context + question + "What alternative approaches exist? What are we missing?"]
```

### 4. Synthesis Round

Compare the two responses:
- Identify points of agreement (likely valid)
- Identify points of disagreement (need resolution)
- Identify unique insights from each

### 5. Resolution Round

If disagreements exist, query both models again with the conflicting viewpoints:

**Both models:**
```
prompt: "Model A said [X]. Model B said [Y]. These conflict. 
        Which perspective is stronger and why? 
        Can they be reconciled? What's the best path forward?"
```

### 6. Reach Consensus

Synthesize the final consensus:
- List agreed-upon conclusions
- Note any unresolved tensions with recommendations
- Provide actionable next steps

## Output Format

Present results as:

```markdown
## Consensus Review: [Topic]

### Context Reviewed
- [What was analyzed]

### Key Findings

**Agreements (High Confidence):**
1. [Point both models agreed on]
2. [Point both models agreed on]

**Resolved Disagreements:**
1. [Initial conflict] → [Resolution reached]

**Open Questions:**
1. [Unresolved tension - recommendation]

### Recommended Actions
1. [Specific action]
2. [Specific action]
```

## Example Invocations

"Summon knights of the round table to check our checkout implementation approach"

"Summon knights of the round table to validate our architecture decision for the new API"

"Summon knights of the round table to review this refactoring plan"
