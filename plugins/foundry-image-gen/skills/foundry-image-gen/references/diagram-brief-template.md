# Diagram Brief and Prompt Template

Complete every required field before generation. Remove instructional notes from the final prompt, but retain the section headings.

```text
DELIVERABLE
Create [artifact type] for [destination/use].
Output: [dimensions/aspect ratio/file expectations].

AUDIENCE AND LESSON
Audience: [who].
Learning objective: Within five seconds, the viewer understands [one sentence].

FACTS AND SEMANTIC BOUNDARY
First-class facts:
- [fact + source]
Client-specific facts:
- [fact + applicability + source]
Optional supporting files:
- [item + status]
External lifecycle/runtime concerns:
- [external item + relationship]
Containment rules:
- Inside [boundary]: [items that factually belong there].
- Outside [boundary]: [external items].

CANVAS AND SAFE AREAS
Canvas: [width x height].
Safe margin: [pixels or percentage].
Protected bands: [title/footer/citation].
Nothing may be cropped or enter [protected area].

OVERALL SILHOUETTE AND READING ORDER
Silhouette: [cutaway/layered stack/journey/hub-and-spoke/other].
Dominant region: [region + percentage].
Reading order: [single path].
Hierarchy: [primary, secondary, tertiary].

REGION GEOMETRY
- [region]: [position, width/height, grid span, nesting, alignment].
- [region]: [position, width/height, grid span, nesting, alignment].

ELEMENT INVENTORY
- [exact count] x [element], grouped as [rule], placed [location].

CONNECTOR TOPOLOGY
- [origin] -> [destination], label "[exact verb]", attach [points], route [path].
No [crossings/double-headed arrows/unlabeled lines].

EXACT LABELS AND TYPOGRAPHY
- "[exact text]" - [location, level, alignment, max lines].
Render every quoted phrase verbatim, exactly once.
Use [type hierarchy]. Unfamiliar icons always have adjacent visible labels.

ICON AND SHAPE SYSTEM
- [shape/icon] means [one semantic meaning].
Icons reinforce labels and never replace them.

COLOR SEMANTICS
- [color + hex if required] means [one semantic meaning].
Pair every color distinction with [label/border/pattern/shape].

REFERENCE ROLES
- Image 1: [layout/copy master]; controls [properties], must not control [properties].
- Image 2: [style reference]; controls [properties], must not control [properties].
- Image N: [named subject/identity]; controls only [element].

INVARIANTS AND EXCLUSIONS
Preserve: [facts, copy, counts, topology, boundaries, accepted areas].
Exclude: [specific artifacts, unsupported metaphors, logos, decorative noise].
Do not use a dashboard/card grid unless the deliverable is genuinely a dashboard.

QA AND ACCEPTANCE
- Exactly [counts].
- Every required label is exact, readable, and appears once.
- Every connector has the specified direction, label, and destination.
- Every boundary passes the containment rules.
- [hierarchy/contrast/grayscale/learning-objective check].
- All content remains inside the safe area with no crop.

VARIANTS
Generate [count] sequential variants.
Keep [invariants] fixed. Vary only [one declared variable].
```

For a corrective edit, replace `VARIANTS` with:

```text
SURGICAL CORRECTION
Use Image 1 as the accepted current figure.
Change only: [one failed property].
Preserve exactly: [copy, counts, geometry, topology, boundaries, style, accepted regions].
Acceptance: [one measurable test for the correction plus all prior invariants].
```
