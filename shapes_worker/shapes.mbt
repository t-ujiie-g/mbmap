///|
let trig : @lineops.Trig = @wasmio.host_trig()

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
/// The input's table.
fn input() -> @geom.Table? {
  let bytes = @wasmio.input_bytes()
  @wasmio.clear_input()
  @geom.Table::from_bytes(bytes[:])
}

///|
/// Writes `f` of the input table as table bytes at `output_addr` and returns their
/// length, or minus an error's.
fn run(f : (@geom.Table) -> @geom.Table?) -> Int32 {
  guard input() is Some(t) else { return @wasmio.fail_with("malformed table") }
  match f(t) {
    Some(out) => @wasmio.write_bytes(out.to_bytes()[:])
    None => @wasmio.fail_with("too many points")
  }
}

///|
/// `@simplify.simplify` of the input table (`high_quality` 0 or 1).
#export_name("simplify")
pub fn simplify(tolerance : Double, high_quality : Int32) -> Int32 {
  run(t => Some(@simplify.simplify(t, tolerance, high_quality != 0)))
}

///|
/// Whether the input's vertices fit `@hull.MAX_HULL_POINTS`.
fn hull_fits(t : @geom.Table) -> Bool {
  t.coords.length() / 2 <= @hull.MAX_HULL_POINTS
}

///|
/// `@hull.convex` of the input table.
#export_name("convex")
pub fn convex() -> Int32 {
  run(t => if hull_fits(t) { Some(@hull.convex(t, trig~)) } else { None })
}

///|
/// `@hull.concave` of the input table.
#export_name("concave")
pub fn concave(concavity : Double, length_threshold : Double) -> Int32 {
  run(t => {
    if hull_fits(t) {
      Some(@hull.concave(t, concavity, length_threshold, trig~))
    } else {
      None
    }
  })
}

///|
/// `@delaunay.triangles` of the input table's points.
#export_name("delaunay")
pub fn delaunay() -> Int32 {
  run(t => @delaunay.triangles_checked(t, trig~))
}

///|
/// `@delaunay.voronoi` of the input table's points within the box.
#export_name("voronoi")
pub fn voronoi(x0 : Double, y0 : Double, x1 : Double, y1 : Double) -> Int32 {
  run(t => @delaunay.voronoi_checked(t, x0, y0, x1, y1, trig~))
}

///|
/// `@lineops.line_slice` of the input table's lines.
#export_name("line_slice")
pub fn line_slice(sx : Double, sy : Double, ex : Double, ey : Double) -> Int32 {
  run(t => Some(@lineops.line_slice(t, sx, sy, ex, ey, trig~)))
}

///|
/// Writes `@lineops.nearest_point_on_line` of the input table (six f64s a row)
/// and returns the f64 count, or minus an error's length.
#export_name("nearest_on_line")
pub fn nearest_on_line(x : Double, y : Double) -> Int32 {
  guard input() is Some(t) else { return @wasmio.fail_with("malformed table") }
  @wasmio.write_f64s(@lineops.nearest_point_on_line(t, x, y, trig~))
}
