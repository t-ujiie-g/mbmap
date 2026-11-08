// The browser side of bench/model/golden.mjs: loadModel's output as plain arrays, and WebP from PNG.
import { loadModel } from "/npm/dist/3d.js";

window.__webp = async (png) => {
  const bitmap = await createImageBitmap(new Blob([new Uint8Array(png)], { type: "image/png" }));
  const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
  canvas.getContext("2d").drawImage(bitmap, 0, 0);
  const blob = await canvas.convertToBlob({ type: "image/webp", quality: 1 });
  return [...new Uint8Array(await blob.arrayBuffer())];
};

window.__load = async (url) => {
  try {
    const m = await loadModel(url);
    return {
      primitives: m.primitives.map((p) => ({
        attributes: Object.fromEntries(Object.entries(p.attributes).map(([k, a]) => [k, { values: [...a.data], size: a.size, type: a.type, normalized: a.normalized }])),
        indices: p.indices ? [...p.indices] : null,
        mode: p.mode,
        material: p.material,
        matrix: [...p.matrix],
      })),
      materials: m.materials.map((x) => ({ ...x, texture: x.texture && { ...x.texture, matrix: x.texture.matrix && [...x.texture.matrix] } })),
      images: m.images.map((b) => [b.width, b.height]),
    };
  } catch (err) {
    return { error: String(err.message ?? err) };
  }
};
window.__ready = true;
