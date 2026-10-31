/** The relative files a minified JS file imports or loads by `new URL`. */
export function referencesOf(js) {
  const found = new Set();
  for (const re of [/\bfrom\s*"(\.\/[^"]+)"/g, /\bimport\s*\(?\s*"(\.\/[^"]+)"/g, /new URL\(\s*"(\.\/[^"]+)"/g]) {
    for (const m of js.matchAll(re)) found.add(m[1]);
  }
  return [...found].sort();
}
