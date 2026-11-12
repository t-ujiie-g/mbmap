// Response bodies read up to a size: a tile server is untrusted (AGENTS.md
// §8.2), so a body is refused once it says, or turns out, to be larger.
// Import-free.

/** Largest tile body read: the wasm input limit (worker/packed.mbt `MAX_PACKED_BYTES`). */
export const MAX_BODY_BYTES = 64 * 1024 * 1024;

/** Largest JSON document (a style, TileJSON, sprite index, tileset, service document) read. */
export const MAX_DOCUMENT_BYTES = 64 * 1024 * 1024;

/** Largest data file (GeoJSON, CSV, …) read: wasmio's `MAX_INPUT_BYTES`. */
export const MAX_DATA_BYTES = 256 * 1024 * 1024;

/** `res`'s body as bytes, or `tooLarge()` thrown once it says, or turns out, to pass `max` bytes. */
export async function readCapped(res, max = MAX_BODY_BYTES, tooLarge = () => new Error(`response larger than ${max} bytes`)) {
  if (Number(res.headers.get("content-length")) > max) {
    res.body?.cancel().catch(() => {});
    throw tooLarge();
  }
  if (!res.body) return new Uint8Array(await res.arrayBuffer());
  const reader = res.body.getReader();
  const parts = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.length;
    if (total > max) {
      reader.cancel().catch(() => {});
      throw tooLarge();
    }
    parts.push(value);
  }
  const out = new Uint8Array(total);
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out;
}

/** `res`'s body parsed as JSON, capped as `readCapped`. */
export const readJsonCapped = async (res, max = MAX_DOCUMENT_BYTES, tooLarge) => JSON.parse(new TextDecoder().decode(await readCapped(res, max, tooLarge)));

/** How long a fetch of data (files up to 256 MB, not map tiles) may take, its body included. */
export const DATA_TIMEOUT_MS = 5 * 60 * 1000;

// What a `transformRequest` may set on a fetch: string headers and a
// credentials mode (none sent otherwise); anything else is left out.
export function fetchInit(init, signal) {
  const out = { signal, credentials: "omit" };
  if (init && typeof init === "object") {
    if (["omit", "same-origin", "include"].includes(init.credentials)) out.credentials = init.credentials;
    if (init.headers && typeof init.headers === "object") {
      out.headers = Object.fromEntries(Object.entries(init.headers).filter(([, v]) => typeof v === "string"));
    }
  }
  return out;
}

/** `fetchInit` with the data timeout: a stalled server must not hold the data worker's queue for good. */
export const dataFetchInit = (init) => fetchInit(init, AbortSignal.timeout(DATA_TIMEOUT_MS));
