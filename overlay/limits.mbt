///|
/// Largest coordinate the operations take: Clipper's integers (`@clipper.MAX_COORD`)
/// hold it in 1e-7 degrees or millimeters with room to spare.
pub const MAX_COORDINATE : Double = 1.0e9

///|
/// Most points a geodesic buffer may split its input's edges into.
pub const MAX_BUFFER_POINTS : Int32 = 10_000_000

///|
/// Why `t` cannot go through the operations, or None: a coordinate not finite
/// or past `MAX_COORDINATE`; with `geodesic`, one that is no longitude and
/// latitude, or edges that split into more than `MAX_BUFFER_POINTS`.
pub fn refusal(t : @geom.Table, geodesic~ : Bool = false) -> String? {
  let n = t.coords.length() / 2
  for i in 0..<n {
    let x = t.coords[i * 2]
    let y = t.coords[i * 2 + 1]
    if !(x.abs() <= MAX_COORDINATE && y.abs() <= MAX_COORDINATE) {
      return Some("coordinates must be finite and within 1e9")
    }
    if geodesic && !(x.abs() <= 540.0 && y.abs() <= 90.0) {
      return Some("coordinates must be longitudes and latitudes")
    }
  }
  if geodesic {
    let mut points = 0.0
    for r in 0..<t.point_ends.length() {
      let (i0, i1) = t.points(r)
      for i in (i0 + 1)..<i1 {
        let dx = t.coords[i * 2] - t.coords[i * 2 - 2]
        let dy = t.coords[i * 2 + 1] - t.coords[i * 2 - 1]
        points += ((dx * dx + dy * dy).sqrt() / BUFFER_DENSIFY).ceil()
      }
    }
    if points > MAX_BUFFER_POINTS.to_double() {
      return Some("edges split into more than 10,000,000 points")
    }
  }
  None
}

///|
/// Why a buffer of `meters` with `arc_tolerance` cannot be made, or None: a
/// geodesic one wider than the Earth, a planar one past `MAX_COORDINATE`, or a
/// tolerance that would put more than about 2,200 points on a circle.
pub fn buffer_refusal(
  meters : Double,
  mode~ : BufferMode,
  arc_tolerance~ : Double,
) -> String? {
  let widest = if mode is Geodesic { 2.0e7 } else { MAX_COORDINATE }
  if !(meters.abs() <= widest) {
    return Some("invalid distance")
  }
  if !(arc_tolerance == 0.0 || arc_tolerance >= meters.abs() * 1.0e-6) {
    return Some("arc tolerance too small for the distance")
  }
  None
}
