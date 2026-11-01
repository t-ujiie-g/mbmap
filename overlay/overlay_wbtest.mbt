///|
fn table(
  features : Array[(@geom.GeomKind, Array[Array[(Double, Double)]], String)],
) -> @geom.Table {
  let b = @geom.TableBuilder::new()
  for f in features {
    let (kind, rings, name) = f
    for ring in rings {
      for p in ring {
        b.point(p.0, p.1)
      }
      b.end_ring()
      if kind is (LineString | MultiLineString) {
        b.end_part()
      }
    }
    b.end_part()
    b.prop("name", Str(name))
    b.end_feature(kind)
  }
  b.finish()
}

///|
fn square(x : Double, y : Double, s : Double) -> Array[(Double, Double)] {
  [(x, y), (x + s, y), (x + s, y + s), (x, y + s), (x, y)]
}

///|
/// Signed area in square degrees of every ring of feature `f`.
fn area_of(t : @geom.Table, f : Int32) -> Double {
  let mut a = 0.0
  let (p0, p1) = t.parts(f)
  for p in p0..<p1 {
    let (r0, r1) = t.rings(p)
    for r in r0..<r1 {
      let (i0, i1) = t.points(r)
      for i in i0..<(i1 - 1) {
        a += t.coords[i * 2] * t.coords[i * 2 + 3] -
          t.coords[i * 2 + 2] * t.coords[i * 2 + 1]
      }
    }
  }
  a / 2.0
}

///|
test "a geodesic buffer puts a point's circle at the distance in its local plane" {
  // On the ground it is within millimeters (bench/clipper/buffer-check.mjs).
  let t = table([(Point, [[(139.7, 35.7)]], "a")])
  let out = buffer(t, 1000.0)
  assert_eq((out.length(), out.kinds[0]), (1, Polygon))
  let plane = LocalPlane::new(139.7, 35.7)
  let (i0, i1) = out.points(0)
  // About 50 points: π / acos(1 - 1/500) steps a turn.
  assert_true(i1 - i0 > 40)
  for i in i0..<i1 {
    let (x, y) = plane.forward(out.coords[i * 2], out.coords[i * 2 + 1])
    let d = (x * x + y * y).sqrt()
    // Vertices sit on the circle up to the 1e-7° output grid (about 1 cm).
    assert_true((d - 1000.0).abs() < 0.02)
  }
  let (lon, lat) = plane.inverse(
    plane.forward(139.71, 35.69).0,
    plane.forward(139.71, 35.69).1,
  )
  assert_true((lon - 139.71).abs() < 1.0e-12 && (lat - 35.69).abs() < 1.0e-12)
  assert_eq(out.column("name").unwrap().values[0], Some(Str("a")))
  assert_true(area_of(out, 0) > 0.0)
}

///|
test "a planar buffer is round in Web Mercator meters" {
  let t = table([(Point, [[(139.7, 35.7)]], "a")])
  let out = buffer(t, 1000.0, mode=Planar)
  let (cx, cy) = mercator(139.7, 35.7)
  let (i0, i1) = out.points(0)
  for i in i0..<i1 {
    let (x, y) = mercator(out.coords[i * 2], out.coords[i * 2 + 1])
    let d = ((x - cx) * (x - cx) + (y - cy) * (y - cy)).sqrt()
    assert_true(d < 1000.01 && d > 1000.0 - 2.1)
  }
}

///|
test "buffers grow and shrink polygons, cap lines and drop what vanishes" {
  let t = table([
    (Polygon, [square(139.0, 35.0, 0.01)], "p"),
    (LineString, [[(139.0, 35.0), (139.01, 35.0)]], "l"),
  ])
  let grown = buffer(t, 100.0, join=Miter)
  let shrunk = buffer(t, -100.0, join=Miter)
  assert_true(area_of(grown, 0) > area_of(t, 0))
  assert_true(area_of(shrunk, 0) < area_of(t, 0) && area_of(shrunk, 0) > 0.0)
  assert_true(area_of(grown, 1) > 0.0)
  // Shrinking by more than half its width empties the square.
  let gone = buffer(t, -1000.0)
  assert_eq(gone.kinds[0], NoGeometry)
  // Butt caps make a shorter shape than round ones.
  assert_true(area_of(buffer(t, 100.0, cap=Butt), 1) < area_of(grown, 1))
}

///|
test "dissolve merges overlapping polygons into one feature" {
  let t = table([
    (Polygon, [square(0.0, 0.0, 2.0)], "a"),
    (Polygon, [square(1.0, 1.0, 2.0)], "b"),
    (Polygon, [square(10.0, 10.0, 1.0)], "c"),
  ])
  let out = dissolve(t)
  assert_eq((out.length(), out.kinds[0]), (1, MultiPolygon))
  assert_eq(area_of(out, 0), 8.0)
  assert_eq(out.columns.length(), 0)
}

///|
test "clip and erase cut polygons, lines and points by another layer" {
  let a = table([
    (Polygon, [square(0.0, 0.0, 2.0)], "poly"),
    (LineString, [[(-1.0, 0.5), (3.0, 0.5)]], "line"),
    (MultiPoint, [[(0.5, 0.5), (5.0, 5.0)]], "pts"),
    (Polygon, [square(20.0, 20.0, 1.0)], "far"),
  ])
  let b = table([(Polygon, [square(1.0, -1.0, 4.0)], "cutter")])
  let c = clip(a, b)
  assert_eq(c.length(), 2)
  assert_eq(area_of(c, 0), 2.0)
  assert_eq(c.kinds[1], LineString)
  assert_eq(c.coords[c.coords.length() - 2], 3.0)
  let names = c.column("name").unwrap().values
  assert_eq((names[0], names[1]), (Some(Str("poly")), Some(Str("line"))))
  let e = erase(a, b)
  assert_eq(e.length(), 4)
  assert_eq(area_of(e, 0), 2.0)
  // Neither point lies in the cutter, so both stay.
  assert_eq(e.kinds[2], MultiPoint)
}

///|
test "intersect keeps both layers' properties, renaming shared keys" {
  let a = table([(Polygon, [square(0.0, 0.0, 2.0)], "a")])
  let b = table([
    (Polygon, [square(1.0, 1.0, 2.0)], "b1"),
    (Polygon, [square(-1.0, -1.0, 1.5)], "b2"),
    (Polygon, [square(5.0, 5.0, 1.0)], "b3"),
  ])
  let out = intersect(a, b)
  assert_eq(out.length(), 2)
  assert_eq((area_of(out, 0), area_of(out, 1)), (1.0, 0.25))
  assert_eq(out.column("name").unwrap().values[0], Some(Str("a")))
  assert_eq(out.column("name_2").unwrap().values, [
    Some(Str("b1")),
    Some(Str("b2")),
  ])
}
