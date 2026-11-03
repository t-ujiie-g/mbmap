// Image, video and canvas sources (MapLibre's ImageSource, VideoSource and CanvasSource):
// the facade loads this file only for styles with one. It fetches and plays the pictures;
// the engine draws them. It imports only plain JS, so that `npm test` can load it.
import { checkBlobImageSize } from "../../worker/js/imagesize.mjs";

/** Largest side of an image source's picture, checked before it is decoded. */
const MAX_MEDIA_SIZE = 8192;

/** The engine's side: show a picture (null for none) placed by a `quadOf`, move it, keep drawing it. */
export interface MediaEngine {
  show(id: string, picture: TexImageSource | null, quad: number[]): void;
  move(id: string, quad: number[]): void;
  playing(id: string, on: boolean): void;
}

/** A source of the style: its id, its specification and, for a canvas source given as an element, the element. */
export interface MediaSource {
  id: string;
  spec: Record<string, unknown>;
  canvas?: unknown;
}

/** MapLibre's `updateImage` options: a new `url` or an already decoded `image`, and maybe new corners. */
export interface UpdateImageOptions {
  url?: string;
  image?: TexImageSource;
  coordinates?: number[][];
}

interface Entry {
  type: string;
  key: string;
  quad: number[];
  request: number;
  video?: HTMLVideoElement;
  canvas?: HTMLCanvasElement;
  stop?: () => void;
}

/** MapLibre's `EXTENT`, which corners are rounded in, and the engine's tile units (`@core.TILE_EXTENT`). */
const EXTENT = 8192;
const TILE_EXTENT = 4096;

/**
 * Where an image goes, as MapLibre's `ImageSource.setCoordinates` and `calculateImageWarp` (its `auto`
 * warp; after Heckbert, "Fundamentals of Texture Mapping and Image Warping", 1989) compute it, in the
 * numbers `Map::set_media_quad` takes; [] for coordinates other than four finite corners.
 */
export function quadOf(coordinates: unknown): number[] {
  if (!Array.isArray(coordinates) || coordinates.length !== 4) return [];
  const flat = coordinates.flatMap((c) => (Array.isArray(c) && c.length === 2 ? c : [NaN]));
  if (flat.length !== 8 || !flat.every(Number.isFinite)) return [];
  const xs = [0, 1, 2, 3].map((i) => (180 + flat[2 * i]) / 360);
  const ys = [0, 1, 2, 3].map((i) => (180 - (180 / Math.PI) * Math.log(Math.tan(Math.PI / 4 + (flat[2 * i + 1] * Math.PI) / 360))) / 360);
  const [x0, x1, y0, y1] = [Math.min(...xs), Math.max(...xs), Math.min(...ys), Math.max(...ys)];
  const z = Math.max(0, Math.floor(-Math.log(Math.max(x1 - x0, y1 - y0)) / Math.LN2));
  const n = 2 ** z;
  const [tx, ty] = [Math.floor(((x0 + x1) / 2) * n), Math.floor(((y0 + y1) / 2) * n)];
  if (!(z <= 28 && tx >= 0 && tx < n && ty >= 0 && ty < n)) return [];
  const p = xs.flatMap((x, i) => [Math.round((x * n - tx) * EXTENT), Math.round((ys[i] * n - ty) * EXTENT)]);
  let warp = [0, 0, 1];
  const parallelogram = p[0] + p[4] === p[2] + p[6] && p[1] + p[5] === p[3] + p[7];
  if (!parallelogram) {
    const [sumX, sumY] = [p[0] - p[2] + p[4] - p[6], p[1] - p[3] + p[5] - p[7]];
    const [rightX, rightY, downX, downY] = [p[2] - p[4], p[3] - p[5], p[6] - p[4], p[7] - p[5]];
    const det = rightX * downY - downX * rightY;
    const px = (sumX * downY - downX * sumY) / det;
    const py = (rightX * sumY - sumX * rightY) / det;
    const d = [1, 1 + px, 1 + px + py, 1 + py];
    const foreshortening = Math.max(...d) / Math.min(...d);
    const blend = Math.max(0, (1 - 4 / foreshortening) / (1 - 4 / 512));
    if (foreshortening >= 1 && foreshortening <= 512 && blend < 1) warp = [px, py, blend];
  }
  const subdivided = warp[2] > 0 && !parallelogram ? 1 : 0;
  return [z, tx, ty, ...p.map((v) => (v * TILE_EXTENT) / EXTENT), ...warp, subdivided, x0, y0, x1, y1];
}

/** `url` against `base`, http(s) only (AGENTS.md §8.3). */
export function mediaUrl(url: unknown, base: URL): string {
  const u = new URL(String(url), base);
  if (!/^https?:$/.test(u.protocol)) throw new Error(`mbmap: media must be http(s): ${u.href}`);
  return u.href;
}

/** What makes a source load again: its type and where its picture comes from. */
function keyOf(s: MediaSource): string {
  const { type, url, urls, canvas } = s.spec;
  return JSON.stringify([type, url, urls, typeof canvas === "string" ? canvas : s.canvas ? "element" : null]);
}

export class Media {
  #entries = new Map<string, Entry>();
  #engine: MediaEngine;
  #fetch: (url: string) => Promise<Response>;
  #fail: (e: Error) => void;
  #base = new URL("about:blank");

  constructor(engine: MediaEngine, fetchImage: (url: string) => Promise<Response>, fail: (e: Error) => void) {
    this.#engine = engine;
    this.#fetch = fetchImage;
    this.#fail = fail;
  }

  /** Follows the style's media sources: loads new ones, moves moved ones, stops removed ones. */
  set(sources: MediaSource[], base: URL): void {
    this.#base = base;
    const ids = new Set(sources.map((s) => s.id));
    for (const [id, e] of this.#entries) if (!ids.has(id)) this.#drop(id, e);
    for (const s of sources) {
      const e = this.#entries.get(s.id);
      if (e && e.key === keyOf(s)) {
        if (String(e.quad) !== String(quadOf(s.spec.coordinates))) this.setCoordinates(s.id, s.spec.coordinates);
        continue;
      }
      if (e) this.#drop(s.id, e);
      this.#load(s);
    }
  }

  #drop(id: string, e: Entry): void {
    e.request++;
    e.stop?.();
    this.#entries.delete(id);
  }

  #load(s: MediaSource): void {
    const type = String(s.spec.type);
    const e: Entry = { type, key: keyOf(s), quad: this.#quad(s.id, s.spec.coordinates), request: 0 };
    this.#entries.set(s.id, e);
    const failed = (err: unknown) => {
      this.#fail(err instanceof Error ? err : new Error(String(err)));
      this.#engine.show(s.id, null, e.quad);
    };
    try {
      if (type === "image") {
        if (s.spec.url === undefined) this.#engine.show(s.id, null, e.quad);
        else this.#image(s.id, e, mediaUrl(s.spec.url, this.#base), failed);
      } else if (type === "video") {
        this.#video(s.id, e, s.spec.urls, failed);
      } else {
        this.#canvas(s.id, e, s.canvas ?? s.spec.canvas, s.spec.animate !== false);
      }
    } catch (err) {
      failed(err);
    }
  }

  #image(id: string, e: Entry, url: string, failed: (err: unknown) => void): void {
    const request = ++e.request;
    this.#fetch(url)
      .then((res) => {
        if (!res.ok) throw new Error(`mbmap: image ${url}: HTTP ${res.status}`);
        return res.blob();
      })
      .then(async (blob) => {
        await checkBlobImageSize(blob, MAX_MEDIA_SIZE, `mbmap: image ${url}`);
        return createImageBitmap(blob);
      })
      .then((bitmap) => {
        if (request === e.request) this.#engine.show(id, bitmap, e.quad);
      })
      .catch((err: unknown) => {
        if (request === e.request) failed(err);
      });
  }

  #video(id: string, e: Entry, urls: unknown, failed: (err: unknown) => void): void {
    if (!Array.isArray(urls) || urls.length === 0) throw new Error(`mbmap: video source "${id}" needs urls`);
    const video = document.createElement("video");
    // Credentials are never sent to other origins; muted so that browsers let it play.
    video.crossOrigin = "anonymous";
    video.muted = true;
    video.loop = true;
    video.playsInline = true;
    for (const u of urls) {
      const source = document.createElement("source");
      source.src = mediaUrl(u, this.#base);
      video.append(source);
    }
    const signal = new AbortController();
    const state = () => this.#engine.playing(id, !video.paused);
    for (const type of ["playing", "pause", "loadeddata", "seeked"]) video.addEventListener(type, state, signal);
    video.lastElementChild!.addEventListener("error", () => failed(new Error(`mbmap: video source "${id}" did not load`)), signal);
    e.video = video;
    e.stop = () => {
      signal.abort();
      video.pause();
    };
    this.#engine.show(id, video, e.quad);
    video.play().catch(() => {});
  }

  #canvas(id: string, e: Entry, canvas: unknown, animate: boolean): void {
    // An id is looked up as such, never as a selector built from the style.
    const el = typeof canvas === "string" ? document.getElementById(canvas) : canvas;
    if (!(el instanceof HTMLCanvasElement)) throw new Error(`mbmap: canvas source "${id}": no canvas ${String(canvas)}`);
    if (!(el.width > 0 && el.height > 0)) throw new Error(`mbmap: canvas source "${id}": the canvas has no pixels`);
    e.canvas = el;
    this.#engine.show(id, el, e.quad);
    if (animate) this.#engine.playing(id, true);
  }

  /** The quad of source `id`'s `coordinates`; malformed ones fire an error and place it nowhere. */
  #quad(id: string, coordinates: unknown): number[] {
    const quad = quadOf(coordinates);
    if (quad.length === 0) this.#fail(new Error(`mbmap: source "${id}": coordinates must be four [longitude, latitude] corners in the world`));
    return quad;
  }

  setCoordinates(id: string, coordinates: unknown): void {
    const e = this.#entries.get(id);
    if (!e) return;
    e.quad = this.#quad(id, coordinates);
    this.#engine.move(id, e.quad);
  }

  /** MapLibre's `updateImage`; `url` resolves as the style's do. */
  updateImage(id: string, o: UpdateImageOptions): void {
    const e = this.#entries.get(id);
    if (!e) return;
    if (o.coordinates) e.quad = this.#quad(id, o.coordinates);
    const failed = (err: unknown) => this.#fail(err instanceof Error ? err : new Error(String(err)));
    if (o.image) {
      e.request++;
      this.#engine.show(id, o.image, e.quad);
    } else if (o.url !== undefined) {
      // The style now names this url: a later style edit keeps the image.
      e.key = keyOf({ id, spec: { type: "image", url: o.url } });
      try {
        this.#image(id, e, mediaUrl(o.url, this.#base), failed);
      } catch (err) {
        failed(err);
      }
    } else if (o.coordinates) {
      this.#engine.move(id, e.quad);
    }
  }

  /** Plays a video, or redraws a canvas every frame. */
  play(id: string): void {
    const e = this.#entries.get(id);
    if (e?.video) e.video.play().catch(() => {});
    else if (e?.canvas) this.#engine.playing(id, true);
  }

  /** Pauses a video, or keeps a canvas's current picture. */
  pause(id: string): void {
    const e = this.#entries.get(id);
    if (e?.video) e.video.pause();
    else if (e?.canvas) this.#engine.playing(id, false);
  }

  video(id: string): HTMLVideoElement | undefined {
    return this.#entries.get(id)?.video;
  }

  canvas(id: string): HTMLCanvasElement | undefined {
    return this.#entries.get(id)?.canvas;
  }

  destroy(): void {
    for (const [id, e] of this.#entries) this.#drop(id, e);
  }
}
