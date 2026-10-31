///|
fn square(x : Double, y : Double, d : Double) -> Array[Double] {
  [x, y, x + d, y, x + d, y + d, x, y + d]
}

///|
test "area, bbox, grid counts and ranking of columnar polygons" {
  // A 1° square at the equator with a 0.5° hole, and a 0.1° square.
  let coords = [
    ..square(0.0, 0.0, 1.0),
    ..square(0.25, 0.25, 0.5),
    ..square(10.0, 0.0, 0.1),
  ]
  let p : @analysis.Polygons = {
    coords: FixedArray::from_array(coords),
    ring_ends: [4, 8, 12],
    poly_ends: [2, 3],
  }
  // Turf.js area of the 1° equatorial square: 12363718145.180046 m².
  let outer = 12363718145.180046
  assert_true((p.area(0) - outer * 0.75).abs() / outer < 1.0e-3)
  assert_eq(p.bbox(1), (10.0, 0.0, 10.1, 0.1))
  let counts = p.grid_counts(5.0)
  assert_eq((counts.get(0), counts.get(2)), (Some(1), Some(1)))
  assert_eq(p.largest(5), [0, 1])
  assert_eq(p.describe(), "2 polygons, 3 rings, 12 points")
}
