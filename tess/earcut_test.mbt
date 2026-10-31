///|
fn tri(coords : Array[Int32], holes~ : Array[Int32] = []) -> Array[Int32] {
  let out = []
  @tess.Earcut::new().triangulate(coords[:], holes[:], out)
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
  assert_eq(@tess.deviation(coords[:], [4][:], t[:]), 0.0)
}

///|
test "degenerate input yields no triangles" {
  assert_eq(tri([]), [])
  assert_eq(tri([1, 1, 2, 2]), [])
  // Collinear points have no area.
  let line = [0, 0, 5, 5, 10, 10]
  assert_eq(tri(line), [])
  assert_eq(@tess.deviation(line[:], [][:], [][:]), 0.0)
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
  assert_true(@tess.deviation(coords[:], [][:], t[:]) < 1.0e-12)
}

///|
test "an instance can be reused across polygons" {
  let e = @tess.Earcut::new()
  let a = []
  let b = []
  e.triangulate([0, 0, 10, 0, 10, 10, 0, 10][:], [][:], a)
  e.triangulate([10, 0, 0, 50, 60, 60, 70, 10][:], [][:], b)
  assert_eq(a.length(), 6)
  assert_eq(b, [1, 0, 3, 1, 3, 2])
}
