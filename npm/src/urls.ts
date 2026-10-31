// URL handling of the facade, kept free of imports so tests can run it as is.

/** A tile URL template resolved against `base`, keeping its `{z}/{x}/{y}`. */
export function resolveTemplate(template: string, base: URL): string {
  // URL() percent-encodes the braces of the placeholders; put them back.
  return new URL(template, base).href.replace(/%7B([zxy])%7D/g, "{$1}");
}

/**
 * The worker script URL, resolved against `base`: http(s) on the page's own
 * origin only, so markup cannot point workers at data:, blob: or foreign code
 * (AGENTS.md §8.3).
 */
export function workerScriptUrl(url: string | URL, base: URL, origin: string): string {
  const u = new URL(url, base);
  if (!/^https?:$/.test(u.protocol) || u.origin !== origin) {
    throw new Error(`mbmap: the worker must be a same-origin http(s) URL: ${u.href}`);
  }
  return u.href;
}

/** The worker's wasm URL, resolved against `base`: http(s) only. */
export function wasmUrl(url: string | URL, base: URL): string {
  const u = new URL(url, base);
  if (!/^https?:$/.test(u.protocol)) throw new Error(`mbmap: the wasm must be an http(s) URL: ${u.href}`);
  return u.href;
}
