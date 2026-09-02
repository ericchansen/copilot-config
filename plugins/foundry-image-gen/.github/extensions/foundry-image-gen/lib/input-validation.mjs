import {
    getConfig,
    normalizeModel,
    validateImageRequest,
    validateReferenceCount,
} from "./providers.mjs";
import { validateReferenceImages } from "./references.mjs";

export function validateImageInputs(
    args,
    baseDir = process.cwd(),
    config = getConfig(),
    referenceValidator = validateReferenceImages
) {
    const model = normalizeModel(args.model);
    const referencePaths = args.reference_images;

    validateReferenceCount(model, Array.isArray(referencePaths) ? referencePaths : []);
    const references = referenceValidator(referencePaths, baseDir);
    validateImageRequest(args, references, config);

    return { model, references };
}
