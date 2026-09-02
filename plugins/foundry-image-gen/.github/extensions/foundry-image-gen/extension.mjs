// Extension: foundry-image-gen
// Provides a multi-model image generation and editing tool for Microsoft Foundry.

import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { basename, join } from "node:path";

import {
    MODEL_IDS,
    buildProviderRequest,
    executeProviderRequest,
    extractImage,
    formatEffectiveSettings,
    getConfig,
} from "./lib/providers.mjs";
import { validateImageInputs } from "./lib/input-validation.mjs";

function getEntraToken(subscription) {
    if (subscription && !/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(subscription)) {
        throw new Error(`Invalid FOUNDRY_IMAGE_SUBSCRIPTION (expected a GUID): ${subscription}`);
    }
    const args = ["account", "get-access-token"];
    if (subscription) args.push("--subscription", subscription);
    args.push("--resource", "https://cognitiveservices.azure.com", "--query", "accessToken", "-o", "tsv");
    return execFileSync("az", args, { encoding: "utf-8", timeout: 30_000 }).trim();
}

async function runSelfTest() {
    const { runSelfTest: test } = await import("./tests/self-test.mjs");
    await test();
}

if (process.argv.includes("--self-test")) {
    await runSelfTest();
    process.exit(0);
}

const { joinSession } = await import("@github/copilot-sdk/extension");
const session = await joinSession({
    tools: [
        {
            name: "generate_image",
            description:
                "Generate or edit an image with GPT-Image-2, FLUX.2-flex, or MAI-Image-2.5-Pro in Microsoft Foundry. " +
                "Returns the saved PNG path.",
            parameters: {
                type: "object",
                properties: {
                    prompt: { type: "string", description: "Detailed description of the image to generate" },
                    model: {
                        type: "string",
                        description: "Model adapter (defaults to gpt-image-2)",
                        enum: [MODEL_IDS.GPT, MODEL_IDS.FLUX, MODEL_IDS.MAI],
                    },
                    size: {
                        type: "string",
                        description:
                            'Output size as WIDTHxHEIGHT or "auto"; validated against the selected provider.',
                    },
                    quality: {
                        type: "string",
                        description: "GPT-Image-2 quality",
                        enum: ["low", "medium", "high"],
                    },
                    reference_images: {
                        type: "array",
                        description: "Local PNG or JPEG paths used in order as edit references",
                        items: { type: "string" },
                        minItems: 1,
                        maxItems: 16,
                    },
                    input_fidelity: {
                        type: "string",
                        description: "GPT-Image-2 reference fidelity",
                        enum: ["low", "high"],
                    },
                    guidance: {
                        type: "number",
                        description: "FLUX.2-flex prompt guidance from 1.5 to 10",
                        minimum: 1.5,
                        maximum: 10,
                    },
                    steps: {
                        type: "integer",
                        description: "FLUX.2-flex inference steps from 1 to 50",
                        minimum: 1,
                        maximum: 50,
                    },
                    filename: { type: "string", description: "Output filename without extension" },
                },
                required: ["prompt"],
            },
            handler: async (args) => {
                const config = getConfig();
                const filename = args.filename || "generated-image";
                let references;
                let model;

                try {
                    ({ model, references } = validateImageInputs(
                        args,
                        session.workspacePath || process.cwd(),
                        config
                    ));
                } catch (error) {
                    return { textResultForLlm: error.message, resultType: "failure" };
                }

                await session.log(`${references.length ? "Editing" : "Generating"} with ${model}...`, {
                    ephemeral: true,
                });

                let token;
                try {
                    token = getEntraToken(config.subscription);
                } catch (error) {
                    return {
                        textResultForLlm: `Auth failed - ensure Azure CLI is installed and run 'az login'. ${error.message}`,
                        resultType: "failure",
                    };
                }

                let result;
                let request;
                try {
                    request = buildProviderRequest(args, references, token, config);
                    result = await executeProviderRequest(request);
                } catch (error) {
                    return { textResultForLlm: error.message, resultType: "failure" };
                }

                const image = extractImage(result);
                if (!image) {
                    return { textResultForLlm: "Provider returned no image data.", resultType: "failure" };
                }

                const outDir = session.workspacePath
                    ? join(session.workspacePath, "files")
                    : join(process.env.TEMP || "/tmp", "foundry-images");
                if (!existsSync(outDir)) mkdirSync(outDir, { recursive: true });
                const safeName = basename(filename).replace(/[^a-zA-Z0-9_-]/g, "_") || "generated-image";
                const outPath = join(outDir, `${safeName}.png`);

                try {
                    if (image.b64) {
                        writeFileSync(outPath, Buffer.from(image.b64, "base64"));
                    } else {
                        const response = await fetch(image.url);
                        if (!response.ok) throw new Error(`Image download failed: ${response.status}`);
                        writeFileSync(outPath, Buffer.from(await response.arrayBuffer()));
                    }
                } catch (error) {
                    return { textResultForLlm: error.message, resultType: "failure" };
                }

                await session.log(`Image saved: ${outPath}`);
                return [
                    `Image saved to: ${outPath}`,
                    `Model: ${request.model}`,
                    `Prompt: ${args.prompt}`,
                    `Settings: ${formatEffectiveSettings(request.effectiveSettings)}`,
                ].join("\n");
            },
        },
    ],
});
