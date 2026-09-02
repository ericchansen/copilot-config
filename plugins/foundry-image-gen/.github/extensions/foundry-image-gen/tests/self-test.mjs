import assert from "node:assert/strict";

import { MODEL_IDS, buildProviderRequest, extractImage } from "../lib/providers.mjs";

export async function runSelfTest() {
    const config = {
        openaiEndpoint: "https://openai.example.test",
        servicesEndpoint: "https://services.example.test",
        gptDeployment: "gpt",
        fluxDeployment: "flux",
        maiDeployment: "mai",
        openaiApiVersion: "preview",
        fluxApiVersion: "preview",
        subscription: "",
    };
    const image = { data: Buffer.from([0x89, 0x50]), name: "reference.png", type: "image/png" };
    const gpt = buildProviderRequest({ prompt: "test" }, [], "token", config);
    const flux = buildProviderRequest(
        { model: MODEL_IDS.FLUX, prompt: "test", guidance: 4.5, steps: 25 },
        [image],
        "token",
        config
    );
    const mai = buildProviderRequest({ model: MODEL_IDS.MAI, prompt: "test" }, [image], "token", config);

    assert.match(gpt.url, /images\/generations/);
    assert.equal(JSON.parse(flux.init.body).input_image, image.data.toString("base64"));
    assert.equal(mai.init.body.get("image").type, "image/png");
    assert.deepEqual(extractImage({ data: [{ b64_json: "abc" }] }), { b64: "abc" });
    console.log("foundry-image-gen provider self-test passed");
}
