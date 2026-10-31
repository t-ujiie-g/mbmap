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
