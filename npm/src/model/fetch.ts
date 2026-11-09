// Capped fetches for mbmap/3d's main-thread loaders: services are untrusted (AGENTS.md §8.2). Import-free.

/** Largest JSON document (a tileset, an I3S layer or node page) read. */
export const MAX_DOCUMENT_BYTES = 64 << 20;

/** `url`'s body (http, https, blob or data URLs, no credentials), refused past `max` bytes. */
export async function fetchCapped(url: string | URL, max = MAX_DOCUMENT_BYTES): Promise<Uint8Array> {
  const u = new URL(url);
  if (!/^(https?|blob|data):$/.test(u.protocol)) throw new Error(`cannot load ${u.protocol} URLs`);
  const res = await fetch(u, { credentials: "omit" });
  if (!res.ok) throw new Error(`${u.href}: HTTP ${res.status}`);
  if (Number(res.headers.get("content-length")) > max) throw new Error(`${u.href}: larger than ${max} bytes`);
  if (!res.body) return new Uint8Array(await res.arrayBuffer());
  const reader = res.body.getReader();
  const parts: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.length;
    if (total > max) {
      reader.cancel();
      throw new Error(`${u.href}: larger than ${max} bytes`);
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

/** `url`'s body read as JSON, capped as `fetchCapped`. */
export const fetchJsonCapped = async (url: string | URL): Promise<any> => JSON.parse(new TextDecoder().decode(await fetchCapped(url)));
