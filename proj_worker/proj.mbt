///|
/// Largest input accepted (AGENTS.md §8.2: limit the size before reading).
pub const MAX_INPUT_BYTES : Int32 = 256 * 1024 * 1024

///|
const MAX_DEFINED_CRS : Int32 = 1024

///|
/// Makes room for `len` input bytes and returns where JS should write them,
/// or -1 if `len` is too large.
#export_name("prepare_input")
pub fn prepare_input(len : Int32) -> Int32 {
  @wasmio.prepare_input(len, MAX_INPUT_BYTES)
}

///|
/// Where the last call's output starts.
#export_name("output_addr")
pub fn output_addr() -> Int32 {
  @wasmio.output_addr()
}

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
/// The host's `Math` (js/worker.mjs passes it), as proj4js computes with.
let trig : @proj.Trig = {
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

///|
/// The CRSs `define_crs` made, by handle.
let defined : Array[@proj.Crs] = []

///|
/// The CRS `id` names: an EPSG code, or -1 - a `define_crs` handle.
fn crs_of(id : Int32) -> @proj.Crs? {
  if id >= 0 {
    @proj.Crs::from_epsg(id, trig~)
  } else {
    defined.get(-1 - id)
  }
}

///|
fn crs_name(id : Int32) -> String {
  if id >= 0 {
    "EPSG:\{id}"
  } else {
    "definition \{-1 - id}"
  }
}

///|
fn f64_at(b : Bytes, at : Int32) -> Double {
  let mut bits = 0UL
  for k in 0..<8 {
    bits = bits | (b[at + k].to_uint64() << (k * 8))
  }
  bits.reinterpret_as_double()
}

///|
/// Makes the CRS encoded in the input (docs/FORMATS.md "CRS definition") and
/// returns its handle.
#export_name("define_crs")
pub fn define_crs() -> Int32 {
  let input = @wasmio.input_bytes()
  @wasmio.clear_input()
  guard input.length() == @proj.DEFINITION_SLOTS * 8 else {
    return @wasmio.fail_with("malformed CRS definition")
  }
  guard defined.length() < MAX_DEFINED_CRS else {
    return @wasmio.fail_with("too many CRS definitions")
  }
  let slots = FixedArray::makei(@proj.DEFINITION_SLOTS, i => {
    f64_at(input, i * 8)
  })
  match @proj.Definition::decode(slots[:]).bind(d => @proj.Crs::new(d, trig~)) {
    Some(crs) => {
      defined.push(crs)
      defined.length() - 1
    }
    None => @wasmio.fail_with("invalid CRS definition")
  }
}

///|
/// 1 if CRS `id` is geographic, 0 if projected, or minus an error's length.
#export_name("crs_kind")
pub fn crs_kind(id : Int32) -> Int32 {
  match crs_of(id) {
    Some(c) => if c.is_geographic() { 1 } else { 0 }
    None => @wasmio.fail_with("unsupported CRS \{crs_name(id)}")
  }
}

///|
/// The input's f64 x, y pairs taken from CRS `from` to CRS `to`, as f64s at
/// `output_addr` (NaN where a projection cannot reach); returns their count.
#export_name("transform_coords")
pub fn transform_coords(from : Int32, to : Int32) -> Int32 {
  guard crs_of(from) is Some(f) else {
    return @wasmio.fail_with("unsupported CRS \{crs_name(from)}")
  }
  guard crs_of(to) is Some(t) else {
    return @wasmio.fail_with("unsupported CRS \{crs_name(to)}")
  }
  let input = @wasmio.input_bytes()
  let n = input.length() / 16
  let out = FixedArray::make(n * 2, @double.not_a_number)
  for i in 0..<n {
    if @proj.transform(f, t, f64_at(input, i * 16), f64_at(input, i * 16 + 8))
      is Some((x, y)) {
      out[i * 2] = x
      out[i * 2 + 1] = y
    }
  }
  @wasmio.clear_input()
  @wasmio.write_f64s(out)
}
