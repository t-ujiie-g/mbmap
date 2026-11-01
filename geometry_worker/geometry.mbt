///|
/// Makes room for `len` input bytes and returns where JS should write them,
/// or -1 if `len` is too large.
#export_name("prepare_input")
pub fn prepare_input(len : Int32) -> Int32 {
  @wasmio.prepare_input(len, @wasmio.MAX_INPUT_BYTES)
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
/// `@overlay.buffer` of the input table: `mode` 0 geodesic (degrees), 1
/// planar (in the coordinates' own units); `join` 0 round, 1 miter, 2 square, 3
/// bevel; `cap` 0 round, 1 butt, 2 square. Returns the result's length at
/// `output_addr`, or minus an error's.
#export_name("buffer")
pub fn buffer(
  meters : Double,
  mode : Int32,
  join : Int32,
  cap : Int32,
  arc_tolerance : Double,
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
  finish(@overlay.buffer(t, meters, mode~, join~, cap~, arc_tolerance~))
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
