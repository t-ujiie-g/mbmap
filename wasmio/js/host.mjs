// Host imports and input copying shared by the wasm-gc entries.

/** Largest input the entries take (wasmio/memory.mbt `MAX_INPUT_BYTES`): URL data is read up to it. */
export const MAX_INPUT_BYTES = 256 * 1024 * 1024;

/** Copies `parts` one after another into the input area of `exports`; `what` names them when too large. */
export function writeInput(exports, parts, what = "input") {
  const len = parts.reduce((sum, part) => sum + part.length, 0);
  let at = exports.prepare_input(len);
  if (at < 0) throw new Error(`${what} too large (${len} bytes)`);
  for (const part of parts) {
    new Uint8Array(exports.memory.buffer, at, part.length).set(part);
    at += part.length;
  }
}

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
    // MapLibre's number-format (op 0), Collator compare (1) and resolvedLocale (2) on
    // the text's strings: `la` and `lb` code units, then the rest (worker/linear_memory.mbt).
    intl(op, f, x, y, z, la, lb) {
      const [a, b, c] = [text.slice(0, la), text.slice(la, la + lb), text.slice(la + lb)];
      text = "";
      try {
        if (op === 1) {
          const sensitivity = f & 1 ? (f & 2 ? "variant" : "case") : f & 2 ? "accent" : "base";
          return new Intl.Collator(f & 4 ? c : [], { sensitivity, usage: "search" }).compare(a, b);
        }
        out = op === 0
          ? new Intl.NumberFormat(f & 1 ? a : [], {
            style: f & 2 ? "currency" : f & 4 ? "unit" : "decimal",
            currency: f & 2 ? b : undefined,
            unit: f & 4 ? c : undefined,
            minimumFractionDigits: f & 8 ? y : undefined,
            maximumFractionDigits: f & 16 ? z : undefined,
          }).format(x)
          : new Intl.Collator(f & 1 ? a : []).resolvedOptions().locale;
        return out.length;
      } catch {
        return op === 1 ? NaN : -1;
      }
    },
  };
}
