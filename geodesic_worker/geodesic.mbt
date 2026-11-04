///|
/// Most points `densify` writes.
const MAX_PATH_POINTS : Int32 = 1_000_000

///|
/// Most points `circle` puts on a ring.
const MAX_CIRCLE_POINTS : Int32 = 4096

///|
/// Widest `circle` radius in meters, about half the Earth's circumference.
const MAX_CIRCLE_RADIUS : Double = 2.0e7

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
/// WGS 84, computing with the host's `Math` as GeographicLib's JavaScript does.
let wgs84 : @geodesic.Geodesic = @geodesic.Geodesic::wgs84(
  trig=@wasmio.host_trig(),
)

///|
/// Writes s12, azi1, azi2, a12 and S12 of the inverse problem; returns 5.
#export_name("inverse")
pub fn inverse(
  lat1 : Double,
  lon1 : Double,
  lat2 : Double,
  lon2 : Double,
) -> Int32 {
  @wasmio.clear_input()
  let r = wgs84.inverse(lat1, lon1, lat2, lon2, area=true)
  @wasmio.write_f64s([r.s12, r.azi1, r.azi2, r.a12, r.area])
}

///|
/// Writes lat2, lon2, azi2 and a12 of the direct problem; returns 4.
#export_name("direct")
pub fn direct(
  lat1 : Double,
  lon1 : Double,
  azi1 : Double,
  s12 : Double,
) -> Int32 {
  @wasmio.clear_input()
  let p = wgs84.direct(lat1, lon1, azi1, s12)
  @wasmio.write_f64s([p.lat2, p.lon2, p.azi2, p.a12])
}

///|
/// Measures the path of the input's longitude, latitude pairs
/// (`@geodesic.Geodesic::measure_path`, a ring if `closed` is 1); returns
/// the count of f64s written.
#export_name("measure_path")
pub fn measure_path(closed : Int32) -> Int32 {
  let coords = @wasmio.input_f64s()
  @wasmio.write_f64s(wgs84.measure_path(coords[:], closed == 1))
}

///|
/// The input's path with points every `step` meters along its geodesics
/// (`@geodesic.Geodesic::densify`); returns the count of f64s written.
#export_name("densify")
pub fn densify(step : Double) -> Int32 {
  let coords = @wasmio.input_f64s()
  match wgs84.densify(coords[:], step, MAX_PATH_POINTS) {
    Some(path) => @wasmio.write_f64s(FixedArray::from_array(path))
    None => @wasmio.fail_with("invalid path or too many points along it")
  }
}

///|
/// Writes `@geodesic.Geodesic::circle` (`n` from 1 to `MAX_CIRCLE_POINTS`
/// points, `radius` up to `MAX_CIRCLE_RADIUS`); returns the count of f64s, or minus an error's length.
#export_name("circle")
pub fn circle(lng : Double, lat : Double, radius : Double, n : Int32) -> Int32 {
  @wasmio.clear_input()
  guard n >= 1 &&
    n <= MAX_CIRCLE_POINTS &&
    radius >= 0.0 &&
    radius <= MAX_CIRCLE_RADIUS else {
    return @wasmio.fail_with("invalid circle")
  }
  @wasmio.write_f64s(wgs84.circle(lng, lat, radius, n))
}
