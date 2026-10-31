// URL handling of the facade, kept free of imports so tests can run it as is.

export function resolveTemplate(template: string, base: URL): string {
  // URL() percent-encodes the placeholders' braces.
  return new URL(template, base).href.replace(/%7B([zxy])%7D/g, "{$1}");
}

/** Same-origin http(s) only, so markup cannot start data:, blob: or foreign workers (AGENTS.md §8.3). */
export function workerScriptUrl(url: string | URL, base: URL, origin: string): string {
  const u = new URL(url, base);
  if (!/^https?:$/.test(u.protocol) || u.origin !== origin) {
    throw new Error(`mbmap: the worker must be a same-origin http(s) URL: ${u.href}`);
  }
  return u.href;
}

export function wasmUrl(url: string | URL, base: URL): string {
  const u = new URL(url, base);
  if (!/^https?:$/.test(u.protocol)) throw new Error(`mbmap: the wasm must be an http(s) URL: ${u.href}`);
  return u.href;
}
