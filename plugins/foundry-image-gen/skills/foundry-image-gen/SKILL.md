---
name: foundry-image-gen
description: 'Generate or edit images with GPT-Image-2, FLUX.2-flex, or MAI-Image-2.5-Pro in Microsoft Foundry via the generate_image tool. Triggers: generate image, edit image, reference image, create image, draw, illustrate, diagram, infographic, figure, visual, mockup, logo, concept art.'
license: MIT
allowed-tools: generate_image, Bash, PowerShell
---

# Foundry Image Generation

Use `generate_image` for text-to-image generation and reference-guided edits with one of three explicit Microsoft Foundry adapters. GPT-Image-2 remains the default.

## Before Every Generation

Show the user the exact prompt, each reference image's role, and the variant count before calling the tool. Skip this checkpoint only when the user explicitly delegates iteration.

- Keep variants within the deployment's quota and generate them sequentially.
- Name variants separately. Change one intentional variable between variants.
- Open or render every result. An API success or saved file is not acceptance.
- Never silently switch models, remove references, shorten the prompt, alter dimensions, or retry with materially different inputs.

## Choose a Workflow

### Simple image or edit

Use a direct prompt when the composition is simple and exact topology is not part of the claim. State the subject, action, setting, composition, style, constraints, and reference roles.

### Diagram, infographic, or educational figure

Read [references/diagram-prompting.md](references/diagram-prompting.md) and use [references/diagram-brief-template.md](references/diagram-brief-template.md).

1. Build a source-backed factual inventory before visual prompting. Separate first-class facts, client-specific facts, optional supporting files, and external lifecycle/runtime concerns.
2. State one learning objective and define the overall silhouette, canvas and safe areas, region map, reading order, hierarchy, connector topology, shape/icon semantics, exact text, color semantics, exclusions, and measurable acceptance criteria.
3. Treat containment as a factual claim: draw an element inside a boundary only when it actually belongs there.
4. Give unfamiliar icons persistent visible labels. Icons reinforce text; they do not replace it.
5. For complex or layout-sensitive figures, create a deterministic labeled wireframe/content master first. It must lock regions, labels, wrapping, connectors, attachment points, and boundaries.
6. Edit from that master and name every reference's role, such as layout/copy master, style reference, identity reference, or accepted prior result.
7. Reject generic dashboard or equal-card-grid compositions unless the content is genuinely a dashboard or a set of peers.
8. Inspect every candidate for required counts, exact spelling, topology, boundary truth, connector crossings, safe-area compliance, and cropping.
9. Correct a failed candidate with a surgical, one-variable reference-guided edit and a preserve list. Do not broadly regenerate an otherwise accepted figure.

## Model Selection

| `model` | API and strengths | References | Dimensions and model-only controls |
|---------|-------------------|------------|------------------------------------|
| `gpt-image-2` (default) | OpenAI images generation/edit APIs; supports `quality` and edit `input_fidelity` | 0-16 PNG/JPEG | `auto` or arbitrary sizes with 16-pixel edges, <=3,840 long edge, <=3:1 ratio, and 655,360-8,294,400 pixels |
| `FLUX.2-flex` | Black Forest Labs provider API; text/layout work with explicit `guidance` and `steps` | 0-10 PNG/JPEG, sent in order | `WIDTHxHEIGHT` or `auto`; each edge >=64, <=4 MP; `guidance` 1.5-10, `steps` 1-50 |
| `MAI-Image-2.5-Pro` | MAI generation/edit APIs; generation returns PNG and edits use multipart image upload | 0-1 PNG/JPEG | Generation only: each edge >=768 and <=1,048,576 total pixels. Edit dimensions are provider-determined. |

There is no universal winner. Same-prompt comparisons can expose useful differences, but report the model, dimensions, references, and provider-only controls with each result. A comparison is not controlled when unsupported parameters are silently normalized.

## Configuration

Authenticate Azure CLI with `az login` and grant the appropriate inference role on the target resource. Configure generic account endpoints and deployment names; the plugin contains no resource-specific defaults.

| Environment variable | Used by | Default |
|----------------------|---------|---------|
| `FOUNDRY_IMAGE_ENDPOINT` | GPT OpenAI-compatible account endpoint | Required for GPT |
| `FOUNDRY_IMAGE_SERVICES_ENDPOINT` | FLUX BFL provider and MAI API base endpoint | Required for FLUX/MAI |
| `FOUNDRY_IMAGE_DEPLOYMENT` | GPT deployment name | `gpt-image-2` |
| `FOUNDRY_IMAGE_FLUX_DEPLOYMENT` | FLUX deployment name | `FLUX.2-flex` |
| `FOUNDRY_IMAGE_MAI_DEPLOYMENT` | MAI deployment name | `MAI-Image-2.5-Pro` |
| `FOUNDRY_IMAGE_API_VERSION` | GPT images API version | `preview` |
| `FOUNDRY_IMAGE_FLUX_API_VERSION` | BFL provider API version | `preview` |
| `FOUNDRY_IMAGE_SUBSCRIPTION` | Optional subscription GUID used to acquire the Entra token | Empty |

`FOUNDRY_IMAGE_ENDPOINT` remains the GPT endpoint setting for backward compatibility. The selected model determines the provider; missing configuration and unsupported parameter combinations fail before any provider request.

## Tool Parameters

`prompt` is required. Optional parameters are `model`, `size`, `quality`, `reference_images`, `input_fidelity`, `guidance`, `steps`, and `filename`. References must be local PNG/JPEG files under 50 MB. Relative paths must remain inside the session workspace.

Images are saved as PNG to the session `files/` directory, or to `$TEMP/foundry-images` without a session workspace. Provider error bodies are returned unchanged.

## Recovery and QA

- Missing or misplaced content: strengthen the locked inventory or edit only the failed region.
- Bad text: use exact quoted copy and a labeled layout/copy master.
- Over-copied references: for GPT edits, lower `input_fidelity`; otherwise restate each reference's role and preserve list.
- Moderation block: simplify neutral wording; never bypass safety controls.
- Rate limit: wait for the quota window and continue sequentially without changing the request.

Run the offline checks:

```shell
node --test plugins/foundry-image-gen/.github/extensions/foundry-image-gen/tests/providers.test.mjs
node plugins/foundry-image-gen/.github/extensions/foundry-image-gen/extension.mjs --self-test
```
