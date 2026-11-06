// Property values as the wasm writes them (docs/FORMATS.md, "Property values").

// `@core.PROP_*`.
const PROP_NULL = 0;
const PROP_FALSE = 1;
const PROP_TRUE = 2;
const PROP_NUMBER = 3;
const PROP_STRING = 4;

// ignoreBOM: a string that starts with U+FEFF keeps it.
const decoder = new TextDecoder("utf-8", { ignoreBOM: true });

// A u32-length-prefixed UTF-8 string at `at`, and the offset after it.
export function readString(view, bytes, at) {
  const n = view.getUint32(at, true);
  return [decoder.decode(bytes.subarray(at + 4, at + 4 + n)), at + 4 + n];
}

// The value at `at` (null, a boolean, a number, a string, or undefined when
// absent), and the offset after it.
export function readValue(view, bytes, at) {
  const tag = view.getUint8(at);
  if (tag === PROP_NUMBER) return [view.getFloat64(at + 1, true), at + 9];
  if (tag === PROP_STRING) return readString(view, bytes, at + 1);
  return [tag === PROP_NULL ? null : tag === PROP_FALSE ? false : tag === PROP_TRUE ? true : undefined, at + 1];
}
