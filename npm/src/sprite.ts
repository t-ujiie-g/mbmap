// A style's sprite sheets (MapLibre's `loadSprite`), loaded only for styles with a `sprite`.
import { checkBlobImageSize } from "../../worker/js/imagesize.mjs";
import { canvasPixels, spriteImages, spriteList } from "./images";
import { httpUrl } from "./urls";

/** Largest side of a sprite sheet, checked before it is decoded. */
const MAX_SHEET_SIZE = 8192;

/**
 * The images of the sprites `sprite` names, the @2x sheets when `pixelRatio` > 1; `fetch` gets
 * each URL (http(s), relative to `base`) through the page's request transform.
 */
export async function loadSprites(
  sprite: unknown,
  pixelRatio: number,
  base: URL,
  fetch: (url: string, type: "SpriteJSON" | "SpriteImage") => Promise<Response>,
) {
  const suffix = pixelRatio > 1 ? "@2x" : "";
  const sheets = await Promise.all(spriteList(sprite).map(async ({ id, url }) => {
    const at = httpUrl(url, base, "the sprite");
    const [json, png] = await Promise.all([fetch(`${at}${suffix}.json`, "SpriteJSON"), fetch(`${at}${suffix}.png`, "SpriteImage")]);
    if (!json.ok || !png.ok) throw new Error(`mbmap: sprite ${at}: HTTP ${json.ok ? png.status : json.status}`);
    const blob = await png.blob();
    await checkBlobImageSize(blob, MAX_SHEET_SIZE, `mbmap: sprite ${at}`);
    const bitmap = await createImageBitmap(blob, { premultiplyAlpha: "none", colorSpaceConversion: "none" });
    try {
      return spriteImages(await json.json(), canvasPixels(bitmap), id === "default" ? "" : `${id}:`);
    } finally {
      bitmap.close();
    }
  }));
  return sheets.flat();
}
