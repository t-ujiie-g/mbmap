// Host imports shared by the wasm-gc entries that read GeoJSON.

/** Largest input the entries take (wasmio/memory.mbt `MAX_INPUT_BYTES`): URL data is read up to it. */
export const MAX_INPUT_BYTES = 256 * 1024 * 1024;

// `read_geojson`'s slow_number: the JSON number (ASCII) at `addr` of the
// instance's memory, by `Number()`. One reader per instance; its view is
// renewed only when memory grew (a detached view has length 0).
export function hostNumber(memory) {
  let bytes = new Uint8Array(0);
  return (addr, len) => {
    if (addr + len > bytes.length) bytes = new Uint8Array(memory().buffer);
    return Number(String.fromCharCode.apply(null, bytes.subarray(addr, addr + len)));
  };
}

// The display worker's `Number(string)` and `String(number)`: `text_char` appends a
// UTF-16 code unit, `text_number` returns `Number()` of the text and empties it;
// `number_text` keeps `String(x)` and returns its length, `text_code` its code units.
export function hostText() {
  let text = "";
  let out = "";
  return {
    number_text(x) {
      out = String(x);
      return out.length;
    },
    text_code(i) {
      return out.charCodeAt(i);
    },
    text_char(c) {
      text += String.fromCharCode(c);
    },
    text_number() {
      const n = Number(text);
      text = "";
      return n;
    },
  };
}
