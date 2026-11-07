// Expected values from @turf/nearest-point-on-line and @turf/line-slice 7.4.0
// in Node; rows Turf rejects are NaN or None.

///|
let nan : Double = @double.not_a_number

///|
let inf : Double = @double.infinity

///|
let rows : Array[(@geom.GeomKind, Array[Array[Array[Double]]])] = [
  (LineString, [[[0.0, 0.0], [1.0, 1.0], [2.0, 0.0], [3.0, 1.0]]]),
  (MultiLineString, [[[0.0, 0.0], [1.0, 1.0]], [[2.0, 0.0], [2.0, 2.0]]]),
  (LineString, [[[10.0, 10.0], [10.0, 10.0], [11.0, 11.0]]]),
  (LineString, [[[5.0, 5.0]]]),
  (Point, [[[1.0, 2.0]]]),
  (Polygon, [[[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 0.0]]]),
  (LineString, [[[0.0, 0.0], [nan, 1.0]]]),
  (LineString, [[[179.5, 10.0], [-179.5, 10.5], [-178.0, 11.0]]]),
  (NoGeometry, []),
  (
    LineString,
    [[[139.7, 35.6], [139.71, 35.61], [139.72, 35.6], [139.73, 35.62]]],
  ),
]

///|
let nearest_expected : Array[(Double, Double, Array[Double])] = [
  (
    1.5,
    0.5,
    [
      1.5000285609642563, 0.5000285577017349, 0.004490972147488408, 235.87290079634099,
      1.0, 0.0, 1.9999999999999998, 0.5000190382262164, 55.59542307906143, 212.84925554789828,
      0.0, 1.0, 10.0, 10.0, 1414.0829084644913, 0.0, 1.0, 0.0, inf, inf, inf, -1.0,
      -1.0, -1.0, nan, nan, nan, nan, nan, nan, nan, nan, nan, nan, nan, nan, nan,
      nan, nan, nan, nan, nan, -178.0, 11.0, 18735.177182510015, 295.7745212710235,
      2.0, 0.0, nan, nan, nan, nan, nan, nan, 139.7, 35.6, 14115.627532099496, 0.0,
      0.0, 0.0,
    ],
  ),
  (
    -1.0,
    -1.0,
    [
      0.0, 0.0, 157.2495984740402, 0.0, 0.0, 0.0, 0.0, 0.0, 157.2495984740402, 0.0,
      0.0, 0.0, 10.0, 10.0, 1725.7682098010148, 0.0, 1.0, 0.0, inf, inf, inf, -1.0,
      -1.0, -1.0, nan, nan, nan, nan, nan, nan, nan, nan, nan, nan, nan, nan, nan,
      nan, nan, nan, nan, nan, -178.0, 11.0, 18854.85208592619, 295.7745212710235,
      2.0, 0.0, nan, nan, nan, nan, nan, nan, 139.7, 35.6, 14426.191828618683, 0.0,
      0.0, 0.0,
    ],
  ),
  (
    5.0,
    1.0,
    [
      3.0, 1.0, 222.35628592958034, 471.74879542212057, 3.0, 0.0, 2.0, 1.0013720667474513,
      333.5343875825769, 268.59724577964175, 0.0, 1.0, 10.0, 10.0, 1143.2985781412485,
      0.0, 1.0, 0.0, inf, inf, inf, -1.0, -1.0, -1.0, nan, nan, nan, nan, nan, nan,
      nan, nan, nan, nan, nan, nan, nan, nan, nan, nan, nan, nan, -178.0, 11.0, 18640.164938715297,
      295.7745212710235, 2.0, 0.0, nan, nan, nan, nan, nan, nan, 139.7, 35.6, 13807.354703851932,
      0.0, 0.0, 0.0,
    ],
  ),
  (
    1.0,
    1.0,
    [
      1.0, 1.0, 0.0, 157.2495984740402, 1.0, 0.0, 1.0, 1.0, 0.0, 157.2495984740402,
      1.0, 0.0, 10.0, 10.0, 1411.278132786262, 0.0, 1.0, 0.0, inf, inf, inf, -1.0,
      -1.0, -1.0, nan, nan, nan, nan, nan, nan, nan, nan, nan, nan, nan, nan, nan,
      nan, nan, nan, nan, nan, -178.0, 11.0, 18676.20058850216, 295.7745212710235,
      2.0, 0.0, nan, nan, nan, nan, nan, nan, 139.7, 35.6, 14112.095668003178, 0.0,
      0.0, 0.0,
    ],
  ),
  (
    179.9,
    10.2,
    [
      3.0, 1.0, 18723.34938115845, 471.74879542212057, 3.0, 0.0, 2.0, 2.0, 18638.760946854203,
      379.63975894110604, 1.0, 1.0, 11.0, 11.0, 17357.49608078762, 155.9414301963512,
      2.0, 0.0, inf, inf, inf, -1.0, -1.0, -1.0, nan, nan, nan, nan, nan, nan, nan,
      nan, nan, nan, nan, nan, nan, nan, nan, nan, nan, nan, 179.8997720160259, 10.200441252576724,
      0.05504443120236313, 49.112363909739585, 0.0, 0.0, nan, nan, nan, nan, nan,
      nan, 139.72, 35.6, 4936.873949330002, 2.8662030314092055, 2.0, 0.0,
    ],
  ),
  (
    10.0,
    10.0,
    [
      3.0, 1.0, 1265.1177603708777, 471.74879542212057, 3.0, 0.0, 2.0, 2.0, 1254.0580635561012,
      379.63975894110604, 1.0, 1.0, 10.0, 10.0, 0.0, 0.0, 1.0, 0.0, inf, inf, inf,
      -1.0, -1.0, -1.0, nan, nan, nan, nan, nan, nan, nan, nan, nan, nan, nan, nan,
      nan, nan, nan, nan, nan, nan, -179.5, 10.5, 17505.126049984498, 122.7348190100605,
      1.0, 0.0, nan, nan, nan, nan, nan, nan, 139.7, 35.6, 12701.8619024887, 0.0,
      0.0, 0.0,
    ],
  ),
  (
    139.715,
    35.603,
    [
      3.0, 1.0, 13962.209167820003, 471.74879542212057, 3.0, 0.0, 2.0, 2.0, 13955.989260671005,
      379.63975894110604, 1.0, 1.0, 11.0, 11.0, 12546.891030714685, 155.9414301963512,
      2.0, 0.0, inf, inf, inf, -1.0, -1.0, -1.0, nan, nan, nan, nan, nan, nan, nan,
      nan, nan, nan, nan, nan, nan, nan, nan, nan, nan, nan, 179.5, 10.0, 4919.44558092439,
      0.0, 0.0, 0.0, nan, nan, nan, nan, nan, nan, 139.71620428965184, 35.603796101941214,
      0.1403239095410447, 2.322197027698038, 1.0, 0.0,
    ],
  ),
  (
    2.0,
    0.0,
    [
      2.0, 0.0, 0.0, 314.4991969480804, 2.0, 0.0, 2.0, 0.0, 0.0, 157.2495984740402,
      0.0, 1.0, 10.0, 10.0, 1421.158323418503, 0.0, 1.0, 0.0, inf, inf, inf, -1.0,
      -1.0, -1.0, nan, nan, nan, nan, nan, nan, nan, nan, nan, nan, nan, nan, nan,
      nan, nan, nan, nan, nan, -178.0, 11.0, 18791.968559467063, 295.7745212710235,
      2.0, 0.0, nan, nan, nan, nan, nan, nan, 139.7, 35.6, 14118.422034170007, 0.0,
      0.0, 0.0,
    ],
  ),
]

///|
let slice_expected : Array[
  (Double, Double, Double, Double, Array[Array[Double]?]),
] = [
  (
    1.5,
    0.5,
    -1.0,
    -1.0,
    [
      Some([0.0, 0.0, 1.0, 1.0, 1.5000285609642563, 0.5000285577017349]),
      None,
      Some([10.0, 10.0, 10.0, 10.0]),
      Some([inf, inf, inf, inf]),
      None,
      None,
      None,
      Some([-178.0, 11.0, -178.0, 11.0]),
      None,
      Some([139.7, 35.6, 139.7, 35.6]),
    ],
  ),
  (
    0.5,
    0.6,
    2.5,
    0.4,
    [
      Some([
        0.5499737616942918, 0.5500321941316083, 1.0, 1.0, 2.0, 0.0, 2.449969877984551,
        0.4500245403811222,
      ]),
      None,
      Some([10.0, 10.0, 10.0, 10.0]),
      Some([inf, inf, inf, inf]),
      None,
      None,
      None,
      Some([-178.0, 11.0, -178.0, 11.0]),
      None,
      Some([139.7, 35.6, 139.7, 35.6]),
    ],
  ),
  (
    5.0,
    1.0,
    1.0,
    1.0,
    [
      Some([1.0, 1.0, 2.0, 0.0, 3.0, 1.0]),
      None,
      Some([10.0, 10.0, 10.0, 10.0]),
      Some([inf, inf, inf, inf]),
      None,
      None,
      None,
      Some([-178.0, 11.0, -178.0, 11.0]),
      None,
      Some([139.7, 35.6, 139.7, 35.6]),
    ],
  ),
  (
    1.0,
    1.0,
    1.0,
    1.0,
    [
      Some([1.0, 1.0, 1.0, 1.0]),
      None,
      Some([10.0, 10.0, 10.0, 10.0]),
      Some([inf, inf, inf, inf]),
      None,
      None,
      None,
      Some([-178.0, 11.0, -178.0, 11.0]),
      None,
      Some([139.7, 35.6, 139.7, 35.6]),
    ],
  ),
  (
    179.9,
    10.2,
    -178.5,
    11.0,
    [
      Some([3.0, 1.0, 3.0, 1.0]),
      None,
      Some([11.0, 11.0, 11.0, 11.0]),
      Some([inf, inf, inf, inf]),
      None,
      None,
      None,
      Some([
        179.8997720160259, 10.200441252576724, -179.5, 10.5, -178.44877979864026,
        10.851337301337987,
      ]),
      None,
      Some([139.72, 35.6, 139.72, 35.6]),
    ],
  ),
  (
    139.715,
    35.603,
    139.701,
    35.6,
    [
      Some([3.0, 1.0, 3.0, 1.0]),
      None,
      Some([11.0, 11.0, 11.0, 11.0]),
      Some([inf, inf, inf, inf]),
      None,
      None,
      None,
      Some([179.5, 10.0, 179.5, 10.0]),
      None,
      Some([
        139.70039792597257, 35.60039798952014, 139.71, 35.61, 139.71620428965184,
        35.603796101941214,
      ]),
    ],
  ),
  (
    10.0,
    10.0,
    10.5,
    10.6,
    [
      Some([3.0, 1.0, 3.0, 1.0]),
      None,
      Some([10.0, 10.0, 10.550242653801723, 10.551431871593707]),
      Some([inf, inf, inf, inf]),
      None,
      None,
      None,
      Some([-179.5, 10.5, -179.5, 10.5]),
      None,
      Some([139.7, 35.6, 139.7, 35.6]),
    ],
  ),
]

///|
/// The rows as a table, each with id `i` and property `n` = `i`.
fn table() -> @geom.Table {
  let b = @geom.TableBuilder::new()
  for i, row in rows {
    let (kind, parts) = row
    for part in parts {
      for p in part {
        b.point(p[0], p[1])
      }
      b.end_ring()
      b.end_part()
    }
    b.prop("n", Num(i.to_double()))
    b.end_feature(kind, id=Some(Num(i.to_double())))
  }
  b.finish()
}

///|
/// Whether `a` is `b` within 1e-12 relative, plus `abs`: distances between
/// close points lose relative precision when the points move in their last
/// bits, as they do under native `@math`.
fn close(a : Double, b : Double, abs~ : Double = 0.0) -> Bool {
  if b.is_nan() {
    a.is_nan()
  } else if b.is_inf() {
    a == b
  } else {
    (a - b).abs() <= 1.0e-12 * @cmp.maximum(1.0, b.abs()) + abs
  }
}

///|
test "nearest_point_on_line matches Turf on every row" {
  let t = table()
  for q in nearest_expected {
    let (x, y, want) = q
    let got = @lineops.nearest_point_on_line(t, x, y)
    assert_eq(got.length(), want.length())
    for i, w in want {
      let word = i % @lineops.NEAREST_WORDS
      let abs = if word is (2 | 3) { 1.0e-9 } else { 0.0 }
      if !close(got[i], w, abs~) {
        fail("query (\{x}, \{y}) word \{i}: got \{got[i]}, want \{w}")
      }
    }
  }
}

///|
test "nearest_point_on_line takes the trig it is given" {
  let t = table()
  let trig = @lineops.Trig::moonbit()
  let a = @lineops.nearest_point_on_line(t, 1.5, 0.5, trig~)
  let b = @lineops.nearest_point_on_line(t, 1.5, 0.5)
  for i in 0..<a.length() {
    assert_true(close(a[i], b[i]))
  }
  let flat = { ..trig, sin: _ => 0.0, }
  let c = @lineops.nearest_point_on_line(t, 1.5, 0.5, trig=flat)
  assert_eq(c[2], 0.0)
}

///|
test "nearest_point_on_line rejects a NaN query" {
  let got = @lineops.nearest_point_on_line(table(), nan, 0.5)
  assert_eq(got.length(), rows.length() * @lineops.NEAREST_WORDS)
  assert_true(got.iter().all(v => v.is_nan()))
  assert_true(
    @lineops.nearest_point_on_line(table(), 0.5, nan)
    .iter()
    .all(v => v.is_nan()),
  )
  assert_eq(
    @lineops.nearest_point_on_line(@geom.Table::new(), 0.0, 0.0).length(),
    0,
  )
}

///|
test "line_slice matches Turf on every row" {
  let t = table()
  for s in slice_expected {
    let (ax, ay, bx, by, want) = s
    let got = @lineops.line_slice(t, ax, ay, bx, by)
    assert_eq(got.length(), want.length())
    for f, w in want {
      assert_eq(got.ids[f], Some(Num(f.to_double())))
      match got.column("n") {
        Some(c) => assert_eq(c.values[f], Some(Num(f.to_double())))
        None => fail("no column n")
      }
      let (p0, p1) = got.parts(f)
      match w {
        None => {
          assert_eq(got.kinds[f], NoGeometry)
          assert_eq(p1, p0)
        }
        Some(coords) => {
          assert_eq(got.kinds[f], LineString)
          assert_eq(p1 - p0, 1)
          let (r0, r1) = got.rings(p0)
          assert_eq(r1 - r0, 1)
          let (i0, i1) = got.points(r0)
          assert_eq((i1 - i0) * 2, coords.length())
          for k, c in coords {
            let v = got.coords[i0 * 2 + k]
            if !close(v, c) {
              fail("slice row \{f} word \{k}: got \{v}, want \{c}")
            }
          }
        }
      }
    }
  }
}

///|
test "line_slice rejects NaN ends" {
  let t = table()
  for
    ends in [
      (nan, 0.0, 1.0, 1.0),
      (0.0, nan, 1.0, 1.0),
      (0.0, 0.0, nan, 1.0),
      (0.0, 0.0, 1.0, nan),
    ] {
    let got = @lineops.line_slice(t, ends.0, ends.1, ends.2, ends.3)
    assert_eq(got.length(), t.length())
    assert_true(got.kinds.iter().all(k => k is NoGeometry))
    assert_eq(got.coords.length(), 0)
    assert_eq(got.ids[3], Some(Num(3.0)))
  }
  assert_eq(@lineops.line_slice(@geom.Table::new(), 0, 0, 1, 1).length(), 0)
}

///|
test "an infinite query finds no segment, as in Turf" {
  let b = @geom.TableBuilder::new()
  b.point(0.0, 0.0)
  b.point(1.0, 1.0)
  b.point(2.0, 2.0)
  b.end_ring()
  b.end_part()
  b.end_feature(LineString)
  let t = b.finish()
  let got = @lineops.nearest_point_on_line(t, inf, 0.0)
  assert_eq(got, [inf, inf, inf, -1.0, -1.0, -1.0])
  let s = @lineops.line_slice(t, inf, 0.0, 0.5, 0.5)
  let want = [inf, inf, 0.0, 0.0, 0.49997143903574376, 0.5000285577017347]
  assert_eq(s.coords.length(), want.length())
  for i, w in want {
    assert_true(close(s.coords[i], w))
  }
}
