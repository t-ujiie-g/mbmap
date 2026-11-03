// Response bodies read up to a size: a tile server is untrusted (AGENTS.md
// §8.2), so a body is refused once it says, or turns out, to be larger.
// Import-free.

/** Largest tile body read: the wasm input limit (worker/packed.mbt `MAX_PACKED_BYTES`). */
export const MAX_BODY_BYTES = 64 * 1024 * 1024;

/** `res`'s body as bytes, or an error once it passes `max` bytes. */
export async function readCapped(res, max = MAX_BODY_BYTES) {
  if (Number(res.headers.get("content-length")) > max) throw new Error(`response larger than ${max} bytes`);
  if (!res.body) return new Uint8Array(await res.arrayBuffer());
  const reader = res.body.getReader();
  const parts = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.length;
    if (total > max) {
      reader.cancel();
      throw new Error(`response larger than ${max} bytes`);
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
