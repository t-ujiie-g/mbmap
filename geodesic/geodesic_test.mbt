// Cases from geographiclib-geodesic 2.2.0's test/geodesictest.js (MIT License,
// Copyright (c) Charles Karney). Bit-for-bit agreement with the library is
// checked by `npm run geodesic:golden`.

///|
fn near(a : Double, b : Double, tol : Double) -> Bool {
  (a - b).abs() <= tol
}

///|
test "inverse solves the library's first test case" {
  let g = @geodesic.Geodesic::wgs84()
  let r = g.inverse(35.60777, -139.44815, -11.17491, -69.95921, area=true)
  assert_true(near(r.azi1, 111.098748429560326, 1.0e-13))
  assert_true(near(r.azi2, 129.289270889708762, 1.0e-13))
  assert_true(near(r.s12, 8935244.5604818305, 1.0e-8))
  assert_true(near(r.a12, 80.50729714281974, 1.0e-13))
  assert_true(near(r.area, 12841384694976.432, 0.1))
  assert_true(
    g.inverse(35.60777, -139.44815, -11.17491, -69.95921).area.is_nan(),
  )
}

///|
test "inverse handles nearly antipodal, meridional and equatorial lines" {
  let g = @geodesic.Geodesic::wgs84()
  assert_true(
    near(
      g.inverse(88.202499451857, 0, -88.202499451857, 179.981022032992859592).s12,
      20003898.214,
      0.5e-3,
    ),
  )
  assert_true(
    near(
      g.inverse(56.320923501171, 0, -56.320923501171, 179.664747671772880215).s12,
      19993558.287,
      0.5e-3,
    ),
  )
  let m = g.inverse(10, 20, 50, 20)
  assert_eq(m.azi1, 0)
  assert_eq(m.azi2, 0)
  let e = g.inverse(0, 0, 0, 90)
  assert_eq(e.azi1, 90)
  assert_true(near(e.s12, quarter_equator, 1.0e-6))
  assert_true(
    near(
      g.inverse(36.493349428792, 0, 36.49334942879201, 0.0000008).s12,
      0.072,
      0.5e-3,
    ),
  )
  assert_eq(g.inverse(20.001, 0, 20.001, 0).s12, 0)
}

///|
let quarter_equator : Double = 6378137.0 * 3.141592653589793 / 2.0

///|
test "inverse works on a prolate ellipsoid" {
  let g = @geodesic.Geodesic::new(6.4e6, -1.0 / 150.0).unwrap()
  let r = g.inverse(0.07476, 0, -0.07476, 180)
  assert_true(near(r.azi1, 90.00078, 0.5e-5))
  assert_true(near(r.s12, 20106193, 0.5))
}

///|
test "new rejects semi-axes that are not finite and positive" {
  assert_true(@geodesic.Geodesic::new(0, 0) is None)
  assert_true(@geodesic.Geodesic::new(6.4e6, 1) is None)
  assert_true(@geodesic.Geodesic::new(@double.infinity, 0) is None)
  assert_true(@geodesic.Geodesic::new(6.4e6, 0) is Some(_))
}

///|
test "direct inverts the library's first test case" {
  let g = @geodesic.Geodesic::wgs84()
  let p = g.direct(
    35.60777, -139.44815, 111.098748429560326, 8935244.5604818305,
  )
  assert_true(near(p.lat2, -11.17491, 1.0e-13))
  assert_true(near(p.lon2, -69.95921, 1.0e-13))
  assert_true(near(p.azi2, 129.289270889708762, 1.0e-13))
  assert_true(near(p.a12, 80.50729714281974, 1.0e-13))
  let pole = g.direct(0.01777745589997, 30, 0, 10.0e6)
  assert_true(near(pole.lat2, 90, 0.5e-5))
}

///|
test "lines give points by distance and arc, with longitudes unrolled" {
  let g = @geodesic.Geodesic::wgs84()
  let line = g.inverse_line(40.6, -73.8, 49.01666667, 2.55)
  assert_true(near(line.s13, 5853226, 0.5))
  assert_true(near(line.azi1, 53.47022, 0.5e-5))
  let end = line.position(false, line.s13)
  assert_true(near(end.lat2, 49.01666667, 1.0e-9))
  assert_true(near(end.lon2, 2.55, 1.0e-9))
  let by_arc = line.position(true, line.a13)
  assert_true(near(by_arc.s12, line.s13, 1.0e-6))
  assert_true(near(by_arc.lon2, 2.55, 1.0e-9))
  let east = g.line(0, 170, 90)
  assert_true(near(east.position(false, 2.0e6).lon2, -172.03369, 1.0e-4))
  assert_true(
    near(east.position(false, 2.0e6, unroll=true).lon2, 187.96631, 1.0e-4),
  )
  assert_true(g.line(0, 0, 0).s13.is_nan())
}

///|
fn polygon(
  points : Array[(Double, Double)],
  polyline~ : Bool = false,
) -> (Double, Double) {
  let p = @geodesic.Geodesic::wgs84().polygon(polyline~)
  for pt in points {
    p.add_point(pt.0, pt.1)
  }
  p.compute(reverse=false, sign=true)
}

///|
test "polygons measure perimeter and signed area, around poles too" {
  let (perimeter, area) = polygon([(89, 0), (89, 90), (89, 180), (89, 270)])
  assert_true(near(perimeter, 631819.8745, 1.0e-4))
  assert_true(near(area, 24952305678, 1))
  let (_, south) = polygon([(-89, 0), (-89, 90), (-89, 180), (-89, 270)])
  assert_true(near(south, -24952305678, 1))
  let (perimeter, area) = polygon([(0, -1), (-1, 0), (0, 1), (1, 0)])
  assert_true(near(perimeter, 627598.2731, 1.0e-4))
  assert_true(near(area, 24619419146, 1))
  let (_, twice) = polygon([
    (89, -360),
    (89, -240),
    (89, -120),
    (89, 0),
    (89, 120),
    (89, 240),
  ])
  assert_true(near(twice, 32415230256, 1))
  let (_, crossing) = polygon([(89, 0.1), (89, 90.1), (89, -179.9)])
  assert_true(near(crossing, 12476152838.5, 1))
}

///|
test "polygon areas follow reverse and sign" {
  let p = @geodesic.Geodesic::wgs84().polygon()
  for pt in [(2.0, 1.0), (1, 2), (3, 3)] {
    p.add_point(pt.0, pt.1)
  }
  let r = 18454562325.45119
  let a0 = 510065621724088.5093
  assert_true(near(p.compute(reverse=false, sign=true).1, r, 0.5))
  assert_true(near(p.compute(reverse=false, sign=false).1, r, 0.5))
  assert_true(near(p.compute(reverse=true, sign=true).1, -r, 0.5))
  assert_true(near(p.compute(reverse=true, sign=false).1, a0 - r, 0.5))
  assert_eq(p.count(), 3)
}

///|
test "polylines have a length and no area; short polygons are empty" {
  let (length, area) = polygon([(90, 0), (0, 0), (0, 90)], polyline=true)
  assert_true(near(length, 20020719, 1))
  assert_true(area.is_nan())
  assert_eq(polygon([(1, 1)]), (0, 0))
  let (zero, none) = polygon([], polyline=true)
  assert_eq(zero, 0)
  assert_true(none.is_nan())
}

///|
test "measure_path gives length, area and the distance to each vertex" {
  let g = @geodesic.Geodesic::wgs84()
  let square : FixedArray[Double] = [-1, 0, 0, -1, 1, 0, 0, 1]
  let open = g.measure_path(square[:], false)
  let edge = g.inverse(0, -1, -1, 0).s12
  assert_eq(open.length(), 6)
  assert_true(open[1].is_nan())
  assert_eq(open[2], 0)
  assert_true(near(open[3], edge, 1.0e-6))
  assert_true(near(open[0], 3.0 * edge, 1.0e-6))
  let closed = g.measure_path(square[:], true)
  assert_true(near(closed[0], 627598.2731, 1.0e-4))
  assert_true(near(closed[1], 24619419146, 1))
  assert_eq(g.measure_path(view([0, 0, 1, 1]), true)[1], 0)
}

///|
test "densify splits edges into steps and unrolls longitudes" {
  let g = @geodesic.Geodesic::wgs84()
  let path = g.densify(view([179, 0, -179, 0]), 50000, 1000).unwrap()
  assert_eq(path.length(), 2 * 6)
  assert_eq(path[0], 179)
  assert_true(near(path[path.length() - 2], 181, 1.0e-9))
  assert_true(near(path[path.length() - 1], 0, 1.0e-9))
  for i in 1..<(path.length() / 2) {
    let d = g.inverse(
        path[i * 2 - 1],
        path[i * 2 - 2],
        path[i * 2 + 1],
        path[i * 2],
      ).s12
    assert_true(d <= 50000.0)
  }
  assert_eq(g.densify(view([0, 0, 0, 0]), 10, 10).unwrap().length(), 4)
  assert_eq(g.densify(view([]), 10, 10).unwrap().length(), 0)
  assert_true(g.densify(view([0, 0, 10, 0]), 1, 1000) is None)
  assert_true(g.densify(view([0, 0, 1, 0]), 0, 1000) is None)
  assert_true(g.densify(view([0, 0, 1, 0, 2, 0]), 1.0e6, 2) is None)
}

///|
fn view(a : FixedArray[Double]) -> ArrayView[Double] {
  a[:]
}
