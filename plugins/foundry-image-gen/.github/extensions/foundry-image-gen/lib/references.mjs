import { existsSync, readFileSync, realpathSync, statSync } from "node:fs";
import * as platformPath from "node:path";

export function isPathInside(rootPath, candidatePath, path = platformPath) {
    const candidate = path.relative(rootPath, candidatePath);
    return candidate === "" || (candidate !== ".." && !candidate.startsWith(`..${path.sep}`) && !path.isAbsolute(candidate));
}

export function validateReferenceImages(paths, baseDir = process.cwd()) {
    if (paths === undefined) return [];
    if (!Array.isArray(paths) || paths.length < 1 || paths.length > 16) {
        throw new Error("reference_images must contain 1 to 16 local paths");
    }

    const resolvedBase = platformPath.resolve(baseDir);
    const realBase = realpathSync(resolvedBase);

    return paths.map((path) => {
        if (typeof path !== "string" || !path.trim()) {
            throw new Error("Each reference image path must be a non-empty string");
        }
        const cleanPath = path.trim();
        const fullPath = platformPath.resolve(resolvedBase, cleanPath);
        if (!isPathInside(resolvedBase, fullPath) && !isPathInside(realBase, fullPath)) {
            throw new Error(`Reference image path escapes the workspace: ${cleanPath}`);
        }
        if (!existsSync(fullPath)) throw new Error(`Reference image not found: ${cleanPath}`);
        const realPath = realpathSync(fullPath);
        if (!isPathInside(realBase, realPath)) {
            throw new Error(`Reference image path escapes the workspace: ${cleanPath}`);
        }
        const file = statSync(realPath);
        if (!file.isFile()) throw new Error(`Reference image is not a file: ${cleanPath}`);
        if (file.size >= 50 * 1024 * 1024) {
            throw new Error(`Reference image must be under 50 MB: ${cleanPath}`);
        }

        const data = readFileSync(realPath);
        const png =
            data.length >= 8 &&
            data.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
        const jpeg = data.length >= 3 && data[0] === 0xff && data[1] === 0xd8 && data[2] === 0xff;
        if (!png && !jpeg) throw new Error(`Reference image must be PNG or JPEG: ${cleanPath}`);
        return { data, name: platformPath.basename(fullPath), type: png ? "image/png" : "image/jpeg" };
    });
}
