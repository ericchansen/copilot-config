const MODEL_IDS = Object.freeze({
    GPT: "gpt-image-2",
    FLUX: "FLUX.2-flex",
    MAI: "MAI-Image-2.5-Pro",
});

const REFERENCE_LIMITS = Object.freeze({
    [MODEL_IDS.GPT]: 16,
    [MODEL_IDS.FLUX]: 10,
    [MODEL_IDS.MAI]: 1,
});

const envValue = (env, name, fallback = "") => env[name]?.trim() || fallback;
const trimEndpoint = (value) => value.replace(/\/+$/, "");

export function getConfig(env = process.env) {
    return {
        openaiEndpoint: envValue(env, "FOUNDRY_IMAGE_ENDPOINT"),
        servicesEndpoint: envValue(env, "FOUNDRY_IMAGE_SERVICES_ENDPOINT"),
        gptDeployment: envValue(env, "FOUNDRY_IMAGE_DEPLOYMENT", MODEL_IDS.GPT),
        fluxDeployment: envValue(env, "FOUNDRY_IMAGE_FLUX_DEPLOYMENT", MODEL_IDS.FLUX),
        maiDeployment: envValue(env, "FOUNDRY_IMAGE_MAI_DEPLOYMENT", MODEL_IDS.MAI),
        openaiApiVersion: envValue(env, "FOUNDRY_IMAGE_API_VERSION", "preview"),
        fluxApiVersion: envValue(env, "FOUNDRY_IMAGE_FLUX_API_VERSION", "preview"),
        subscription: envValue(env, "FOUNDRY_IMAGE_SUBSCRIPTION"),
    };
}

export function normalizeModel(model) {
    const selected = model || MODEL_IDS.GPT;
    if (!Object.values(MODEL_IDS).includes(selected)) {
        throw new Error(`Unsupported model: ${selected}`);
    }
    return selected;
}

function requireEndpoint(value, name) {
    if (!value) throw new Error(`${name} is required for the selected model`);
    let parsed;
    try {
        parsed = new URL(value);
    } catch {
        throw new Error(`${name} must be an absolute HTTP(S) URL`);
    }
    if (!["http:", "https:"].includes(parsed.protocol)) {
        throw new Error(`${name} must be an absolute HTTP(S) URL`);
    }
    return trimEndpoint(value);
}

function parseDimensions(size, model) {
    if (size === "auto") return null;
    const match = /^(\d+)x(\d+)$/.exec(size);
    if (!match) throw new Error(`Invalid size for ${model}: ${size}`);
    return { width: Number(match[1]), height: Number(match[2]) };
}

function validateNumber(value, name, { integer = false, min, max }) {
    if (value === undefined) return;
    if (typeof value !== "number" || !Number.isFinite(value) || (integer && !Number.isInteger(value))) {
        throw new Error(`${name} must be ${integer ? "an integer" : "a number"}`);
    }
    if (value < min || value > max) throw new Error(`${name} must be between ${min} and ${max}`);
}

export function validateReferenceCount(model, references) {
    const limit = REFERENCE_LIMITS[model];
    if (references.length > limit) {
        throw new Error(`${model} supports at most ${limit} reference image${limit === 1 ? "" : "s"}`);
    }
}

function validateGpt(args, references) {
    const size = args.size || "1024x1024";
    const dimensions = parseDimensions(size, MODEL_IDS.GPT);
    if (dimensions) {
        const { width, height } = dimensions;
        if (width % 16 !== 0 || height % 16 !== 0) {
            throw new Error(`${MODEL_IDS.GPT} width and height must be multiples of 16`);
        }
        if (Math.max(width, height) > 3840) {
            throw new Error(`${MODEL_IDS.GPT} longest edge must not exceed 3,840 pixels`);
        }
        if (Math.max(width, height) / Math.min(width, height) > 3) {
            throw new Error(`${MODEL_IDS.GPT} aspect ratio must not exceed 3:1`);
        }
        const pixels = width * height;
        if (pixels < 655_360 || pixels > 8_294_400) {
            throw new Error(`${MODEL_IDS.GPT} output must contain between 655,360 and 8,294,400 pixels`);
        }
    }
    if (args.guidance !== undefined || args.steps !== undefined) {
        throw new Error(`${MODEL_IDS.GPT} does not support guidance or steps`);
    }
    if (args.input_fidelity !== undefined && !references.length) {
        throw new Error("input_fidelity requires at least one reference image");
    }
}

function validateFlux(args) {
    if (args.quality !== undefined || args.input_fidelity !== undefined) {
        throw new Error(`${MODEL_IDS.FLUX} does not support quality or input_fidelity`);
    }
    validateNumber(args.guidance, "guidance", { min: 1.5, max: 10 });
    validateNumber(args.steps, "steps", { integer: true, min: 1, max: 50 });

    const dimensions = parseDimensions(args.size || "1024x1024", MODEL_IDS.FLUX);
    if (!dimensions) return;
    if (dimensions.width < 64 || dimensions.height < 64) {
        throw new Error(`${MODEL_IDS.FLUX} width and height must each be at least 64`);
    }
    if (dimensions.width * dimensions.height > 4_194_304) {
        throw new Error(`${MODEL_IDS.FLUX} output must not exceed 4 megapixels`);
    }
}

function validateMai(args, references) {
    if (args.quality !== undefined || args.input_fidelity !== undefined || args.guidance !== undefined || args.steps !== undefined) {
        throw new Error(`${MODEL_IDS.MAI} does not support quality, input_fidelity, guidance, or steps`);
    }
    if (references.length) {
        if (args.size !== undefined) throw new Error(`${MODEL_IDS.MAI} edits do not support output dimensions`);
        return;
    }

    if (args.size === "auto") throw new Error(`${MODEL_IDS.MAI} does not support size "auto"`);
    const dimensions = parseDimensions(args.size || "1024x1024", MODEL_IDS.MAI);
    if (dimensions.width < 768 || dimensions.height < 768) {
        throw new Error(`${MODEL_IDS.MAI} width and height must each be at least 768`);
    }
    if (dimensions.width * dimensions.height > 1_048_576) {
        throw new Error(`${MODEL_IDS.MAI} output must not exceed 1,048,576 pixels`);
    }
}

export function validateImageRequest(args, references, config = getConfig()) {
    if (typeof args.prompt !== "string" || !args.prompt.trim()) {
        throw new Error("prompt must be a non-empty string");
    }
    const model = normalizeModel(args.model);
    validateReferenceCount(model, references);

    if (model === MODEL_IDS.GPT) {
        requireEndpoint(config.openaiEndpoint, "FOUNDRY_IMAGE_ENDPOINT");
        validateGpt(args, references);
    } else {
        requireEndpoint(config.servicesEndpoint, "FOUNDRY_IMAGE_SERVICES_ENDPOINT");
        if (model === MODEL_IDS.FLUX) validateFlux(args);
        if (model === MODEL_IDS.MAI) validateMai(args, references);
    }
    return model;
}

function makeGptBody(args, references, deployment) {
    const size = args.size || "1024x1024";
    const quality = args.quality || "high";
    if (!references.length) {
        return JSON.stringify({
            model: deployment,
            prompt: args.prompt,
            n: 1,
            size,
            quality,
            output_format: "png",
        });
    }

    const body = new FormData();
    body.append("model", deployment);
    body.append("prompt", args.prompt);
    body.append("n", "1");
    body.append("size", size);
    body.append("quality", quality);
    body.append("output_format", "png");
    body.append("input_fidelity", args.input_fidelity || "high");
    for (const image of references) {
        body.append("image[]", new Blob([image.data], { type: image.type }), image.name);
    }
    return body;
}

function makeFluxBody(args, references, deployment) {
    const body = {
        model: deployment,
        prompt: args.prompt,
        output_format: "png",
    };
    const dimensions = parseDimensions(args.size || "1024x1024", MODEL_IDS.FLUX);
    if (dimensions) Object.assign(body, dimensions);
    if (args.guidance !== undefined) body.guidance = args.guidance;
    if (args.steps !== undefined) body.steps = args.steps;
    references.forEach((image, index) => {
        const field = index === 0 ? "input_image" : `input_image_${index + 1}`;
        body[field] = image.data.toString("base64");
    });
    return JSON.stringify(body);
}

function makeMaiBody(args, references, deployment) {
    if (!references.length) {
        const dimensions = parseDimensions(args.size || "1024x1024", MODEL_IDS.MAI);
        return JSON.stringify({
            model: deployment,
            prompt: args.prompt,
            ...dimensions,
        });
    }

    const body = new FormData();
    body.append("model", deployment);
    body.append("prompt", args.prompt);
    const image = references[0];
    body.append("image", new Blob([image.data], { type: image.type }), image.name);
    return body;
}

export function getEffectiveSettings(args, references, model = normalizeModel(args.model)) {
    const editing = references.length > 0;
    const settings = {
        operation: editing ? "edit" : "generate",
        size: model === MODEL_IDS.MAI && editing ? "provider-determined" : args.size || "1024x1024",
        outputFormat: "png",
        referenceCount: references.length,
    };

    if (model === MODEL_IDS.GPT) {
        settings.quality = args.quality || "high";
        if (editing) settings.inputFidelity = args.input_fidelity || "high";
    } else if (model === MODEL_IDS.FLUX) {
        settings.guidance = args.guidance ?? 4.5;
        settings.steps = args.steps ?? 50;
    }

    return settings;
}

export function formatEffectiveSettings(settings) {
    return Object.entries(settings)
        .map(([name, value]) => `${name}: ${value}`)
        .join(", ");
}

export function buildProviderRequest(args, references, token, config = getConfig()) {
    const model = validateImageRequest(args, references, config);
    const effectiveSettings = getEffectiveSettings(args, references, model);
    const headers = { Authorization: `Bearer ${token}` };
    let url;
    let body;

    if (model === MODEL_IDS.GPT) {
        const operation = references.length ? "edits" : "generations";
        url = `${trimEndpoint(config.openaiEndpoint)}/openai/v1/images/${operation}?api-version=${encodeURIComponent(config.openaiApiVersion)}`;
        body = makeGptBody(args, references, config.gptDeployment);
    } else if (model === MODEL_IDS.FLUX) {
        url = `${trimEndpoint(config.servicesEndpoint)}/providers/blackforestlabs/v1/flux-2-flex?api-version=${encodeURIComponent(config.fluxApiVersion)}`;
        body = makeFluxBody(args, references, config.fluxDeployment);
    } else {
        const operation = references.length ? "edits" : "generations";
        url = `${trimEndpoint(config.servicesEndpoint)}/mai/v1/images/${operation}`;
        body = makeMaiBody(args, references, config.maiDeployment);
    }

    if (typeof body === "string") headers["Content-Type"] = "application/json";
    return { model, effectiveSettings, url, init: { method: "POST", headers, body } };
}

export async function executeProviderRequest(request, fetchImpl = fetch) {
    const response = await fetchImpl(request.url, request.init);
    if (!response.ok) {
        const providerError = await response.text();
        throw new Error(providerError || `HTTP ${response.status}`);
    }
    return response.json();
}

export function extractImage(result) {
    const first = result?.data?.[0];
    if (first?.b64_json) return { b64: first.b64_json };
    if (first?.url) return { url: first.url };
    if (typeof result?.result?.sample === "string") return { url: result.result.sample };
    if (typeof result?.sample === "string") return { url: result.sample };
    return null;
}

export { MODEL_IDS, REFERENCE_LIMITS };
