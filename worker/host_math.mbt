///|
fn host_sin(x : Double) -> Double = "Math" "sin"

///|
fn host_cos(x : Double) -> Double = "Math" "cos"

///|
fn host_tan(x : Double) -> Double = "Math" "tan"

///|
fn host_asin(x : Double) -> Double = "Math" "asin"

///|
fn host_acos(x : Double) -> Double = "Math" "acos"

///|
fn host_atan(x : Double) -> Double = "Math" "atan"

///|
fn host_atan2(y : Double, x : Double) -> Double = "Math" "atan2"

///|
fn host_exp(x : Double) -> Double = "Math" "exp"

///|
fn host_log(x : Double) -> Double = "Math" "log"

///|
fn host_pow(x : Double, y : Double) -> Double = "Math" "pow"

///|
/// The host's `Math` (worker/js/worker.mjs passes it), as MapLibre computes
/// with; keeps `@math` out of the module. `@wasmio.host_trig` is the same for
/// the wasm-gc-only entries, which this all-targets package cannot import.
fn host_trig() -> @core.Trig {
  {
    sin: host_sin,
    cos: host_cos,
    tan: host_tan,
    asin: host_asin,
    acos: host_acos,
    atan: host_atan,
    atan2: host_atan2,
    exp: host_exp,
    ln: host_log,
    pow: host_pow,
  }
}
