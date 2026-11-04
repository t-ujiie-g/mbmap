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
test "a planar buffer is round in the coordinates' own plane" {
  let t = table([(Point, [[(-5995.0, -35367.0)]], "a")])
  let out = buffer(t, 1000.0, mode=Planar)
  let (i0, i1) = out.points(0)
  assert_true(i1 - i0 > 40)
  for i in i0..<i1 {
    let dx = out.coords[i * 2] + 5995.0
    let dy = out.coords[i * 2 + 1] + 35367.0
    let d = (dx * dx + dy * dy).sqrt()
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

///|
/// The coordinates of feature `f`'s ring `r` (within it) as pairs.
fn ring_of(t : @geom.Table, f : Int32, r : Int32) -> Array[(Double, Double)] {
  let (p0, _) = t.parts(f)
  let (r0, _) = t.rings(p0)
  let (i0, i1) = t.points(r0 + r)
  Array::makei(i1 - i0, i => {
    (t.coords[(i0 + i) * 2], t.coords[(i0 + i) * 2 + 1])
  })
}

///|
test "split cuts a square across into two counter-clockwise halves with its properties" {
  let a = table([(Polygon, [square(0, 0, 2)], "a")])
  let b = table([(LineString, [[(1, -1), (1, 3)]], "cut")])
  let out = split(a, b)
  assert_eq(out.length(), 2)
  for f in 0..<2 {
    assert_true((area_of(out, f) - 2.0).abs() < 1.0e-12)
    assert_eq(out.columns[0].values[f], Some(Str("a")))
    let ring = ring_of(out, f, 0)
    assert_eq(ring[0], ring[ring.length() - 1])
    assert_true(ring.contains((1.0, 0.0)) && ring.contains((1.0, 2.0)))
  }
}

///|
test "split follows a bent line and several crossings" {
  // A line in and out twice cuts a square into three.
  let a = table([(Polygon, [square(0, 0, 4)], "a")])
  let b = table([(LineString, [[(1, -1), (1, 5), (3, 5), (3, -1)]], "cut")])
  let out = split(a, b)
  assert_eq(out.length(), 3)
  let areas = Array::makei(3, f => area_of(out, f))
  areas.sort()
  assert_true(
    (areas[0] - 4.0).abs() < 1.0e-12 &&
    (areas[1] - 4.0).abs() < 1.0e-12 &&
    (areas[2] - 8.0).abs() < 1.0e-12,
  )
  // A bent line crossing once divides along its bend.
  let bent = split(a, table([(LineString, [[(-1, 1), (2, 3), (5, 1)]], "cut")]))
  assert_eq(bent.length(), 2)
  assert_true((area_of(bent, 0) + area_of(bent, 1) - 16.0).abs() < 1.0e-12)
}

///|
test "split leaves alone what a line does not cross from edge to edge" {
  let a = table([(Polygon, [square(0, 0, 2)], "a"), (Point, [[(5, 5)]], "p")])
  // Ends inside the square.
  let out = split(a, table([(LineString, [[(1, -1), (1, 1)]], "cut")]))
  assert_eq(out.length(), 2)
  assert_eq(out.kinds[1], Point)
  assert_true((area_of(out, 0) - 4.0).abs() < 1.0e-12)
  // Misses it.
  assert_eq(
    split(a, table([(LineString, [[(3, -1), (3, 3)]], "cut")])).length(),
    2,
  )
}

///|
test "split keeps a hole in the piece around it" {
  let a = table([(Polygon, [square(0, 0, 4), square(2.5, 1, 1).rev()], "a")])
  let out = split(a, table([(LineString, [[(2, -1), (2, 5)]], "cut")]))
  assert_eq(out.length(), 2)
  let holed = if out.rings(out.parts(0).0) is (r0, r1) && r1 - r0 == 2 {
    0
  } else {
    1
  }
  let (r0, r1) = out.rings(out.parts(holed).0)
  assert_eq(r1 - r0, 2)
  assert_true((area_of(out, holed) - 7.0).abs() < 1.0e-12)
  assert_true((area_of(out, 1 - holed) - 8.0).abs() < 1.0e-12)
}

///|
test "split cuts a line where lines cross it" {
  let a = table([(LineString, [[(0, 0), (4, 0)]], "l")])
  let out = split(
    a,
    table([(LineString, [[(1, -1), (1, 1)], [(3, -1), (3, 1)]], "cut")]),
  )
  assert_eq(out.length(), 3)
  assert_eq(ring_of(out, 0, 0), [(0.0, 0.0), (1.0, 0.0)])
  assert_eq(ring_of(out, 1, 0), [(1.0, 0.0), (3.0, 0.0)])
  assert_eq(ring_of(out, 2, 0), [(3.0, 0.0), (4.0, 0.0)])
}

///|
test "merge unites polygons, joins lines end to end and gathers points" {
  let polys = merge(
    table([(Polygon, [square(0, 0, 2)], "a"), (Polygon, [square(1, 0, 2)], "b")]),
  ).unwrap()
  assert_eq((polys.length(), polys.kinds[0]), (1, Polygon))
  assert_true((area_of(polys, 0) - 6.0).abs() < 1.0e-12)
  assert_eq(polys.columns[0].values[0], Some(Str("a")))
  let apart = merge(
    table([(Polygon, [square(0, 0, 1)], "a"), (Polygon, [square(3, 0, 1)], "b")]),
  ).unwrap()
  assert_eq(apart.kinds[0], MultiPolygon)
  let lines = merge(
    table([
      (LineString, [[(1, 0), (2, 0)]], "a"),
      (LineString, [[(3, 1), (2, 0)]], "b"),
      (LineString, [[(0, 0), (1, 0)]], "c"),
    ]),
  ).unwrap()
  assert_eq(lines.kinds[0], LineString)
  assert_eq(ring_of(lines, 0, 0), [
    (0.0, 0.0),
    (1.0, 0.0),
    (2.0, 0.0),
    (3.0, 1.0),
  ])
  let gap = merge(
    table([
      (LineString, [[(0, 0), (1, 0)]], "a"),
      (LineString, [[(5, 0), (6, 0)]], "b"),
    ]),
  ).unwrap()
  assert_eq(gap.kinds[0], MultiLineString)
  let points = merge(
    table([(Point, [[(0, 0)]], "a"), (Point, [[(1, 1)]], "b")]),
  ).unwrap()
  assert_eq((points.kinds[0], points.points(0)), (MultiPoint, (0, 2)))
  assert_true(
    merge(table([(Point, [[(0, 0)]], "a"), (Polygon, [square(0, 0, 1)], "b")]))
    is None,
  )
  assert_true(merge(table([])) is None)
}

///|
test "refusal keeps out coordinates Clipper cannot hold and edges that split too far" {
  let ok = table([(Polygon, [square(0.0, 0.0, 1.0)], "a")])
  assert_eq(refusal(ok), None)
  assert_eq(refusal(ok, geodesic=true), None)
  let far = table([(LineString, [[(0.0, 0.0), (2.0e9, 0.0)]], "a")])
  assert_true(refusal(far) is Some(_))
  let inf = table([(Point, [[(1.0 / 0.0, 0.0)]], "a")])
  assert_true(refusal(inf) is Some(_))
  let planar = table([(Point, [[(5.0e8, 1.0e6)]], "a")])
  assert_eq(refusal(planar), None)
  assert_true(refusal(planar, geodesic=true) is Some(_))
  let long = []
  for i in 0..<400 {
    long.push((if i % 2 == 0 { -179.0 } else { 179.0 }, 0.0))
  }
  assert_true(
    refusal(table([(LineString, [long], "a")]), geodesic=true) is Some(_),
  )
}

///|
test "buffer_refusal bounds the distance and the arc tolerance" {
  assert_eq(buffer_refusal(1000.0, mode=Geodesic, arc_tolerance=0.0), None)
  assert_eq(buffer_refusal(-1000.0, mode=Geodesic, arc_tolerance=0.01), None)
  assert_true(
    buffer_refusal(3.0e7, mode=Geodesic, arc_tolerance=0.0) is Some(_),
  )
  assert_eq(buffer_refusal(3.0e7, mode=Planar, arc_tolerance=0.0), None)
  assert_true(
    buffer_refusal(0.0 / 0.0, mode=Planar, arc_tolerance=0.0) is Some(_),
  )
  assert_true(
    buffer_refusal(1000.0, mode=Geodesic, arc_tolerance=1.0e-9) is Some(_),
  )
}
