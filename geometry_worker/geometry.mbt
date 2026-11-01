///|
/// Largest input accepted (AGENTS.md §8.2: limit the size before reading).
pub const MAX_INPUT_BYTES : Int32 = 256 * 1024 * 1024

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
/// Writes `t` as table bytes at `output_addr`; returns their length.
fn finish(t : @geom.Table) -> Int32 {
  @wasmio.clear_input()
  @wasmio.write_bytes(t.to_bytes()[:])
}

///|
/// The input's first table (`len` bytes, or all of it if -1) and the rest.
fn tables(len : Int32) -> (@geom.Table, @geom.Table?)? {
  let input = @wasmio.input_bytes()
  if len < 0 {
    return @geom.Table::from_bytes(input[:]).map(t => (t, None))
  }
  if len > input.length() {
    return None
  }
  guard @geom.Table::from_bytes(input[:len]) is Some(a) &&
    @geom.Table::from_bytes(input[len:]) is Some(b) else {
    return None
  }
  Some((a, Some(b)))
}

///|
/// `@overlay.buffer` of the input table: `mode` 0 geodesic, 1 planar in the
/// projected CRS with EPSG code `crs`; `join` 0 round, 1 miter, 2 square, 3
/// bevel; `cap` 0 round, 1 butt, 2 square. Returns the result's length at
/// `output_addr`, or minus an error's.
#export_name("buffer")
pub fn buffer(
  meters : Double,
  mode : Int32,
  join : Int32,
  cap : Int32,
  arc_tolerance : Double,
  crs : Int32,
) -> Int32 {
  guard tables(-1) is Some((t, _)) else {
    return @wasmio.fail_with("malformed table")
  }
  if meters.is_nan() ||
    meters.is_inf() ||
    arc_tolerance.is_nan() ||
    arc_tolerance < 0.0 {
    return @wasmio.fail_with("invalid distance")
  }
  let join : @clipper.JoinType = match join {
    1 => Miter
    2 => Square
    3 => Bevel
    _ => Round
  }
  let cap : @clipper.EndType = match cap {
    1 => Butt
    2 => Square
    _ => Round
  }
  let mode : @overlay.BufferMode = if mode == 1 { Planar } else { Geodesic }
  guard @proj.Crs::from_epsg(crs) is Some(plane) && !plane.is_geographic() else {
    return @wasmio.fail_with("unsupported or unprojected CRS EPSG:\{crs}")
  }
  finish(
    @overlay.buffer(t, meters, mode~, crs=plane, join~, cap~, arc_tolerance~),
  )
}

///|
/// `@overlay.dissolve` of the input table.
#export_name("dissolve")
pub fn dissolve() -> Int32 {
  guard tables(-1) is Some((t, _)) else {
    return @wasmio.fail_with("malformed table")
  }
  finish(@overlay.dissolve(t))
}

///|
/// An overlay of the input's two tables (the first `len_a` bytes, then the
/// rest): `op` 0 clip, 1 erase, 2 intersect.
#export_name("overlay")
pub fn overlay(len_a : Int32, op : Int32) -> Int32 {
  guard tables(len_a) is Some((a, Some(b))) else {
    return @wasmio.fail_with("malformed tables")
  }
  match op {
    0 => finish(@overlay.clip(a, b))
    1 => finish(@overlay.erase(a, b))
    2 => finish(@overlay.intersect(a, b))
    _ => @wasmio.fail_with("unknown overlay \{op}")
  }
}

///|
fn crs_of(code : Int32) -> @proj.Crs? {
  @proj.Crs::from_epsg(code)
}

///|
/// The input table with its coordinates taken from EPSG `from` to EPSG `to`.
#export_name("transform")
pub fn transform(from : Int32, to : Int32) -> Int32 {
  guard tables(-1) is Some((t, _)) else {
    return @wasmio.fail_with("malformed table")
  }
  guard crs_of(from) is Some(f) else {
    return @wasmio.fail_with("unsupported CRS EPSG:\{from}")
  }
  guard crs_of(to) is Some(t2) else {
    return @wasmio.fail_with("unsupported CRS EPSG:\{to}")
  }
  match @overlay.transform(t, f, t2) {
    Some(out) => finish(out)
    None => @wasmio.fail_with("a point lies beyond the projection's reach")
  }
}

///|
/// The input's f64 x, y pairs taken from EPSG `from` to EPSG `to`, as f64s at
/// `output_addr` (NaN where a projection cannot reach); returns their count.
#export_name("transform_coords")
pub fn transform_coords(from : Int32, to : Int32) -> Int32 {
  guard crs_of(from) is Some(f) else {
    return @wasmio.fail_with("unsupported CRS EPSG:\{from}")
  }
  guard crs_of(to) is Some(t) else {
    return @wasmio.fail_with("unsupported CRS EPSG:\{to}")
  }
  let input = @wasmio.input_bytes()
  let n = input.length() / 16
  let out = FixedArray::make(n * 2, @double.not_a_number)
  let f64 = (at : Int32) => {
    let mut bits = 0UL
    for k in 0..<8 {
      bits = bits | (input[at + k].to_uint64() << (k * 8))
    }
    bits.reinterpret_as_double()
  }
  for i in 0..<n {
    if @proj.transform(f, t, f64(i * 16), f64(i * 16 + 8)) is Some((x, y)) {
      out[i * 2] = x
      out[i * 2 + 1] = y
    }
  }
  @wasmio.clear_input()
  @wasmio.write_f64s(out)
}
