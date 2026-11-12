// A style's sprite sheets (MapLibre's `loadSprite`), loaded only for styles with a `sprite`.
import { checkBlobImageSize, decodeImage } from "../../worker/js/imagesize.mjs";
import { canvasPixels, spriteImages, spriteList, spriteUrl } from "./images.ts";
import { httpUrl } from "./urls.ts";

/** Largest side of a sprite sheet, checked before it is decoded. */
const MAX_SHEET_SIZE = 8192;

/**
 * The images of the sprites `sprite` names, the @2x sheets when `pixelRatio` > 1; `fetch` gets
 * each URL (http(s), relative to `base`) through the page's request transform, `read` its body (capped).
 */
export async function loadSprites(
  sprite: unknown,
  pixelRatio: number,
  base: URL,
  fetch: (url: string, type: "SpriteJSON" | "SpriteImage") => Promise<Response>,
  read: (res: Response, what: string) => Promise<Uint8Array<ArrayBuffer>>,
) {
  const suffix = pixelRatio > 1 ? "@2x" : "";
  const sheets = await Promise.all(spriteList(sprite).map(async ({ id, url }) => {
    const at = httpUrl(url, base, "the sprite");
    const [json, png] = await Promise.all([fetch(spriteUrl(at, suffix, ".json"), "SpriteJSON"), fetch(spriteUrl(at, suffix, ".png"), "SpriteImage")]);
    if (!json.ok || !png.ok) throw new Error(`mbmap: sprite ${at}: HTTP ${json.ok ? png.status : json.status}`);
    const what = `mbmap: sprite ${at}`;
    const blob = new Blob([await read(png, what)], { type: png.headers.get("content-type") ?? "image/png" });
    await checkBlobImageSize(blob, MAX_SHEET_SIZE, `mbmap: sprite ${at}`);
    const bitmap = await decodeImage(blob);
    try {
      return spriteImages(JSON.parse(new TextDecoder().decode(await read(json, what))), canvasPixels(bitmap), id === "default" ? "" : `${id}:`);
    } finally {
      bitmap.close();
    }
  }));
  return sheets.flat();
}
