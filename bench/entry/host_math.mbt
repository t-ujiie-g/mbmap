///|
/// The host's `Math.sin` and `Math.log` (wasm builds only): the projection
/// then matches geojson-vt bit for bit. The host passes `{ Math }` as imports.
fn host_sin(x : Double) -> Double = "Math" "sin"

///|
fn host_log(x : Double) -> Double = "Math" "log"

///|
fn host_trig() -> @tiler.Trig {
  { sin: host_sin, ln: host_log, }
}

///|
/// The host's `Number()` on the JSON number at `[addr, addr + len)`.
fn host_number(addr : Int32, len : Int32) -> Double = "host" "number"

///|
/// `host_number` for offsets into input copied from `addr`.
fn host_slow_number(addr : Int32) -> (Int32, Int32) -> Double {
  (s, e) => host_number(addr + s, e - s)
}
