# Diagram and Figure Prompting

Use this reference for educational diagrams, infographics, systems figures, architecture views, and other images where layout communicates facts.

## 1. Establish the factual model

Inventory the content before describing its appearance:

- **First-class facts:** concepts and relationships the figure must teach.
- **Client-specific facts:** behaviors or components that apply only to a named client, host, or implementation.
- **Optional supporting files:** examples, scripts, references, assets, or other payload that may exist but is not structurally required.
- **External lifecycle/runtime concerns:** marketplaces, deployment, install/update policy, services, runtimes, trust boundaries, and resources that interact with the subject but are not contained by it.

Record a source for each consequential fact. If the source model is unresolved, stop and resolve it before generating. A visual boundary asserts ownership or containment, so an item inside a boundary must factually belong inside it. Use outside regions and labeled connectors for external concerns.

## 2. Specify the information architecture

Write the prompt in this order:

1. **Deliverable:** artifact type, destination, and required output.
2. **Audience and learning objective:** what a viewer should understand within five seconds.
3. **Facts and semantic boundary:** required facts, applicability qualifiers, and explicit inside/outside rules.
4. **Canvas and safe areas:** dimensions, margins, protected title/footer bands, and crop rules.
5. **Overall silhouette:** the composition recognizable at thumbnail scale, such as a cutaway, layered stack, journey, or hub-and-spoke.
6. **Region geometry:** grid, percentages, bands, nesting, alignment, and whitespace.
7. **Reading order and hierarchy:** one dominant path and the visual priority of regions.
8. **Element inventory:** exact required elements, counts, grouping, and placement.
9. **Connector topology:** origin, destination, direction, label, attachment point, route, and crossing constraints for every connector.
10. **Text and icon system:** exact quoted labels, line wrapping, type levels, and a visible label for each unfamiliar icon.
11. **Shape and color semantics:** one stable meaning for each repeated shape, border, fill, badge, and color. Never rely on color alone.
12. **Reference roles:** identify what each image controls and what it must not control.
13. **Invariants and exclusions:** preserve facts and accepted geometry before listing unwanted artifacts.
14. **Acceptance criteria:** measurable checks for inventory, counts, spelling, topology, containment, legibility, contrast, safe areas, and cropping.

Icons are redundant cues: they speed recognition after the adjacent text establishes meaning. Avoid unlabeled decorative symbols. Avoid generic dashboards and walls of equal cards when the content has hierarchy, flow, or containment.

## 3. Lock complex layouts before styling

For a complex or text-heavy figure, create a deterministic wireframe/content master with:

- every region and boundary;
- all exact labels and final line wrapping;
- every connector and attachment point;
- legends, applicability markers, and annotations;
- the final aspect ratio and safe areas.

Review this master for factual completeness and topology before image generation. Then use reference-guided editing and name each role in the prompt:

- **Image 1 - layout/copy master:** controls geometry, copy, topology, and boundaries.
- **Image 2 - style reference:** controls only palette, texture, illustration treatment, or lighting.
- **Image 3+ - subject/identity references:** control only the named element.

The model should apply visual finish, not invent the information architecture.

## 4. Iterate under quota

Generate variants sequentially. Keep content, labels, and topology invariant while changing one declared variable such as silhouette or style. Open every candidate and verify:

- required and forbidden element counts;
- exact spelling and one occurrence per required phrase;
- connector direction, labels, destinations, attachment points, and crossings;
- truthful containment and external boundaries;
- hierarchy and five-second comprehension;
- icon labels and non-color cues;
- safe areas, requested dimensions, and no cropping.

When one criterion fails, edit the accepted candidate with one requested correction and an explicit preserve list. Broad regeneration can destroy already-correct text and topology.

## Weak and strong examples

**Weak**

> Make a modern infographic explaining a software package. Use icons, blue cards, and arrows. Keep it clean.

This does not define the lesson, facts, hierarchy, containment, topology, exact copy, or a testable result. It invites a generic card grid.

**Strong**

> Create one 16:9 educational systems figure for developers. Learning objective: within five seconds, viewers distinguish the packaged core from host-specific additions and external runtime services. Use Image 1 only as the layout/copy master. Preserve its three nested package bands, exact quoted labels, two outside service nodes, and four labeled left-to-right connectors. The package occupies 60% of the safe width and is the dominant silhouette. Teal fill means portable core; violet outline plus a visible "Host-specific" badge means client-specific; gray means external. Every unfamiliar icon has an adjacent text label. Do not add cards, controls, metrics, logos, or unlabeled arrows. Accept only if all nine labels appear exactly once, all four arrows terminate at the specified nodes, external nodes remain outside the package boundary, and nothing enters the 5% safe margin.

## Sources

- [OpenAI GPT Image prompting guide](https://developers.openai.com/cookbook/examples/multimodal/image-gen-models-prompting-guide) - structured prompts, exact text, placement constraints, and iterative edits.
- [Microsoft Foundry image generation documentation](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/dall-e) - Azure image generation concepts and API use.
- [Microsoft architecture design diagrams](https://learn.microsoft.com/en-us/azure/well-architected/architect-role/design-diagrams) - scope, boundaries, consistency, and accessible notation.
- [C4 model notation](https://c4model.com/diagrams/notation) - explicit element and relationship labels.
- [Fluent 2 layout](https://fluent2.microsoft.design/layout) and [typography](https://fluent2.microsoft.design/typography) - proximity, whitespace, hierarchy, and readable type.
- [Nielsen Norman Group icon usability](https://www.nngroup.com/articles/icon-usability/) - persistent text labels for unfamiliar or ambiguous icons.
