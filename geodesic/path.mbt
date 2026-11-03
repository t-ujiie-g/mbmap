///|
/// Measures the path through `coords` (longitude, latitude pairs in degrees):
/// its length in meters, then the area in square meters of the ring it closes
/// (counter-clockwise positive; 0 below three vertices, NaN unless `closed`),
/// then the distance along it to each vertex. A closed path's length includes
/// the edge back to the first vertex.
pub fn Geodesic::measure_path(
  self : Geodesic,
  coords : ArrayView[Double],
  closed : Bool,
) -> FixedArray[Double] {
  let n = coords.length() / 2
  let out = FixedArray::make(2 + n, 0.0)
  let path = self.polygon(polyline=!closed)
  for i in 0..<n {
    path.add_point(coords[i * 2 + 1], coords[i * 2])
    out[2 + i] = path.perimetersum.sum(0.0)
  }
  let (length, area) = path.compute(reverse=false, sign=true)
  out[0] = length
  out[1] = if closed && n < 3 { 0.0 } else { area }
  out
}

///|
/// The path through `coords` (longitude, latitude pairs) with points added
/// along each geodesic edge at most `step` meters apart, as longitude,
/// latitude pairs whose longitudes run on continuously across ±180; None if
/// that would take more than `max_points` points or `step` is not positive.
pub fn Geodesic::densify(
  self : Geodesic,
  coords : ArrayView[Double],
  step : Double,
  max_points : Int32,
) -> Array[Double]? {
  let n = coords.length() / 2
  guard step > 0.0 && n <= max_points else { return None }
  let out = []
  if n == 0 {
    return Some(out)
  }
  let mut lon = coords[0]
  out.push(lon)
  out.push(coords[1])
  for i in 1..<n {
    let line = self.inverse_line(
      coords[i * 2 - 1],
      lon,
      coords[i * 2 + 1],
      coords[i * 2],
    )
    let parts = (line.s13 / step).ceil()
    guard !parts.is_nan() &&
      (out.length() / 2).to_double() + parts <= max_points.to_double() else {
      return None
    }
    let parts = if parts < 1.0 { 1 } else { parts.to_int() }
    let da = line.a13 / parts.to_double()
    for k in 1..<=parts {
      let p = line.position(true, da * k.to_double(), unroll=true)
      out.push(p.lon2)
      out.push(p.lat2)
    }
    lon = out[out.length() - 2]
  }
  Some(out)
}
