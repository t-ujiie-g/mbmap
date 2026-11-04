///|
/// JS `Number.EPSILON`, for `deviation`'s roundoff bound.
const DOUBLE_EPSILON : Double = 2.220446049250313e-16

///|
/// Relative difference between the polygon's area and its triangulation's;
/// near 0 means a correct triangulation. Arguments are as for `triangulate`.
fn deviation(
  coords : ArrayView[Int32],
  hole_starts : ArrayView[Int32],
  triangles : ArrayView[Int32],
) -> Double {
  let has_holes = hole_starts.length() > 0
  let outer_len = if has_holes { hole_starts[0] * 2 } else { coords.length() }
  let mut polygon_area = signed_area(coords, 0, outer_len).abs()
  let len = hole_starts.length()
  for i in 0..<len {
    let start = hole_starts[i] * 2
    let end = if i < len - 1 { hole_starts[i + 1] * 2 } else { coords.length() }
    polygon_area -= signed_area(coords, start, end).abs()
  }
  let mut triangles_area = 0.0
  for i = 0; i < triangles.length(); i = i + 3 {
    let a = triangles[i] * 2
    let b = triangles[i + 1] * 2
    let c = triangles[i + 2] * 2
    let ax = coords[a].to_double()
    let ay = coords[a + 1].to_double()
    triangles_area += ((ax - coords[c].to_double()) *
    (coords[b + 1].to_double() - ay) -
    (ax - coords[b].to_double()) * (coords[c + 1].to_double() - ay)).abs()
  }
  if triangles_area == 0.0 {
    // No triangles: fine only if the polygon was degenerate up to roundoff.
    let mut max = 0.0
    for i = 0; i < coords.length(); i = i + 2 {
      max = max3(
        max,
        coords[i].to_double().abs(),
        coords[i + 1].to_double().abs(),
      )
    }
    return if polygon_area.abs() <=
      coords.length().to_double() * max * max * DOUBLE_EPSILON {
      0.0
    } else {
      1.0
    }
  }
  ((triangles_area - polygon_area) / polygon_area).abs()
}

///|
fn tri(coords : Array[Int32], holes~ : Array[Int32] = []) -> Array[Int32] {
  let out = []
  Earcut::new().triangulate(coords[:], holes[:], out)
  out
}

///|
test "earcut matches earcut.js 3.2.4 on its doc example" {
  // The JSDoc in src/earcut.js still shows an older output, [1, 0, 3, 3, 2, 1].
  assert_eq(tri([10, 0, 0, 50, 60, 60, 70, 10]), [1, 0, 3, 1, 3, 2])
}

///|
test "a square with a hole covers exactly the ring between them" {
  let coords = [0, 0, 100, 0, 100, 100, 0, 100, 20, 20, 80, 20, 80, 80, 20, 80]
  let t = tri(coords, holes=[4])
  assert_eq(t.length(), 8 * 3)
  assert_eq(deviation(coords[:], [4][:], t[:]), 0.0)
}

///|
test "degenerate input yields no triangles" {
  assert_eq(tri([]), [])
  assert_eq(tri([1, 1, 2, 2]), [])
  // Collinear points have no area.
  let line = [0, 0, 5, 5, 10, 10]
  assert_eq(tri(line), [])
  assert_eq(deviation(line[:], [][:], [][:]), 0.0)
}

///|
test "large polygons use the z-order hash and stay exact" {
  // A 200-point star exceeds the hashing threshold of 80 points.
  let coords = []
  for i in 0..<200 {
    let a = i.to_double() * 2.0 * @math.PI / 200.0
    let r = if i % 2 == 0 { 1000.0 } else { 400.0 }
    coords.push((r * @math.cos(a)).round().to_int())
    coords.push((r * @math.sin(a)).round().to_int())
  }
  let t = tri(coords)
  assert_eq(t.length(), (200 - 2) * 3)
  assert_true(deviation(coords[:], [][:], t[:]) < 1.0e-12)
}

///|
test "an instance can be reused across polygons" {
  let e = Earcut::new()
  let a = []
  let b = []
  e.triangulate([0, 0, 10, 0, 10, 10, 0, 10][:], [][:], a)
  e.triangulate([10, 0, 0, 50, 60, 60, 70, 10][:], [][:], b)
  assert_eq(a.length(), 6)
  assert_eq(b, [1, 0, 3, 1, 3, 2])
}
