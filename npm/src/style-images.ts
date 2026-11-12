// The style's images: the sprite's (sprite.js, loaded with the first sprite) and those `addImage` adds.
import * as engine from "mbmap-engine";
import { MAX_DOCUMENT_BYTES, readCapped } from "../../worker/js/body.mjs";
import { decodeImage } from "../../worker/js/imagesize.mjs";
import { type ImageInput, type StyleImageOptions, canvasPixels, imageOptions, imagePixels } from "./images";
import type { ResourceType } from "./types";
import { httpUrl } from "./urls";

/**
 * What the images need of the map: `withEngine` runs on the engine once it exists, `fail` fires
 * `error`, `fetch` goes through the `transformRequest`, `waitFor` holds `idle` back until a promise settles.
 */
export interface ImageHost {
  withEngine(f: (map: engine.EngineMap) => void): void;
  fail(err: unknown): void;
  fetch(url: string, type: ResourceType): Promise<Response>;
  waitFor(p: Promise<unknown>): Promise<unknown>;
}

export class StyleImages {
  #host: ImageHost;
  #names = new Set<string>();
  #sprite: string[] = [];
  #spriteKey = "null";
  #closed = false;

  constructor(host: ImageHost) {
    this.#host = host;
  }

  /** Loads the images of `sprite` when it changes, replacing the previous sprite's. */
  loadSprite(sprite: unknown, base: URL): void {
    const key = JSON.stringify(sprite ?? null);
    if (key === this.#spriteKey) return;
    this.#spriteKey = key;
    for (const name of this.#sprite.splice(0)) this.remove(name);
    const host = this.#host;
    // Tiles with icons wait for the sprite, as MapLibre's do.
    host.withEngine((m) => engine.map_hold_images(m, sprite != null));
    if (sprite == null) return;
    const loading = import("./sprite.js")
      .then((m) => m.loadSprites(sprite, globalThis.devicePixelRatio ?? 1, base, host.fetch, (res, what) =>
        readCapped(res, MAX_DOCUMENT_BYTES, () => new Error(`${what}: larger than ${MAX_DOCUMENT_BYTES} bytes`))))
      .then((images) => {
        if (key !== this.#spriteKey || this.#closed) return;
        for (const { name, pixels, pixelRatio, sdf } of images) {
          if (this.#names.has(name)) continue;
          this.#names.add(name);
          this.#sprite.push(name);
          host.withEngine((m) => engine.map_add_image(m, name, pixels.width, pixels.height, pixels.data, pixelRatio, sdf));
        }
      })
      .catch(host.fail)
      .finally(() => key === this.#spriteKey && host.withEngine((m) => engine.map_hold_images(m, false)));
    host.waitFor(loading);
  }

  /** Adds image `id`, or with `replace` replaces its pixels; fires `error` if it exists already, or does not. */
  set(id: string, image: ImageInput, options: StyleImageOptions, replace: boolean): void {
    if (this.#names.has(id) !== replace) {
      this.#host.fail(new Error(replace ? `mbmap: no image named "${id}"` : `mbmap: an image named "${id}" already exists`));
      return;
    }
    let pixels, opts;
    try {
      pixels = imagePixels(image, canvasPixels);
      opts = imageOptions(options);
    } catch (err) {
      this.#host.fail(err);
      return;
    }
    this.#names.add(id);
    this.#host.withEngine((m) => engine.map_add_image(m, id, pixels.width, pixels.height, pixels.data, opts.pixelRatio, opts.sdf));
  }

  has(id: string): boolean {
    return this.#names.has(id);
  }

  remove(id: string): void {
    if (this.#names.delete(id)) this.#host.withEngine((m) => engine.map_remove_image(m, id));
  }

  list(): string[] {
    return [...this.#names];
  }

  /** Fetches an image (http(s), relative to `base`) for `addImage` (MapLibre's `loadImage`), its pixels as stored. */
  async load(url: string, base: URL): Promise<{ data: ImageBitmap }> {
    const res = await this.#host.fetch(httpUrl(url, base, "an image"), "Image");
    if (!res.ok) throw new Error(`mbmap: image ${url}: HTTP ${res.status}`);
    return { data: await decodeImage(await res.blob()) };
  }

  /** Stops a sprite still loading from adding its images. */
  close(): void {
    this.#closed = true;
  }
}
