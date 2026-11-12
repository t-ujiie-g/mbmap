// Capped fetches for mbmap/3d's main-thread loaders: services are untrusted (AGENTS.md §8.2).
import { MAX_DOCUMENT_BYTES, readCapped } from "../../../worker/js/body.mjs";

export { MAX_DOCUMENT_BYTES };

/** `url`'s body (http, https, blob or data URLs, no credentials), refused past `max` bytes. */
export async function fetchCapped(url: string | URL, max = MAX_DOCUMENT_BYTES): Promise<Uint8Array> {
  const u = new URL(url);
  if (!/^(https?|blob|data):$/.test(u.protocol)) throw new Error(`cannot load ${u.protocol} URLs`);
  const res = await fetch(u, { credentials: "omit" });
  if (!res.ok) throw new Error(`${u.href}: HTTP ${res.status}`);
  return readCapped(res, max, () => new Error(`${u.href}: larger than ${max} bytes`));
}

/** `url`'s body read as JSON, capped as `fetchCapped`. */
export const fetchJsonCapped = async (url: string | URL): Promise<any> => JSON.parse(new TextDecoder().decode(await fetchCapped(url)));
