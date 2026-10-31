// Host imports shared by the wasm-gc entries that read GeoJSON.

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
