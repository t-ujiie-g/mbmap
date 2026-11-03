///|
fn near(a : Double, b : Double) -> Bool {
  (a - b).abs() <= 1.0e-12 * b.abs()
}

///|
/// A polygon with a hole: the unit square around a square of side 0.5.
fn holed() -> @geom.Table {
  let b = @geom.TableBuilder::new()
  for p in [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0), (0.0, 0.0)] {
    b.point(p.0, p.1)
  }
  b.end_ring()
  for
    p in [(0.25, 0.25), (0.25, 0.75), (0.75, 0.75), (0.75, 0.25), (0.25, 0.25)] {
    b.point(p.0, p.1)
  }
  b.end_ring()
  b.end_part()
  b.end_feature(Polygon)
  b.finish()
}

///|
fn points(
  xys : Array[(Double, Double)],
  k~ : Array[Double] = [],
) -> @geom.Table {
  let b = @geom.TableBuilder::new()
  for i, p in xys {
    b.point(p.0, p.1)
    b.end_ring()
    b.end_part()
    if k.get(i) is Some(v) {
      b.prop("k", Num(v))
    }
    b.end_feature(Point)
  }
  b.finish()
}

///|
test "measures match Turf" {
  let trig = @analysis.Trig::moonbit()
  let sq = holed()
  assert_true(near(@analysis.area(sq, trig, 0), 9272759185.183495))
  assert_true(near(@analysis.length(sq, trig, 0), 667148.2529638374))
  assert_eq(@analysis.centroid(sq, 0), (0.5, 0.5))
  assert_eq(@analysis.bbox(sq, 0), (0.0, 0.0, 1.0, 1.0))
  let b = @geom.TableBuilder::new()
  for p in [(139.7, 35.6), (139.8, 35.7), (-170.0, -10.0)] {
    b.point(p.0, p.1)
  }
  b.end_ring()
  b.end_part()
  b.end_feature(LineString)
  let line = b.finish()
  assert_true(near(@analysis.length(line, trig, 0), 7326273.911712621))
  assert_eq(@analysis.area(line, trig, 0), 0.0)
  assert_true(
    near(
      @analysis.distance(trig, 139.7671, 35.6812, -0.1276, 51.5072),
      9562322.834986933,
    ),
  )
  // Degrees are taken modulo 360 with the sign of the dividend, as in JS.
  assert_true(
    near(
      @analysis.distance(trig, -370.0, 10.0, 20.0, -400.0),
      6360297.254353219,
    ),
  )
  let pt = points([(3.0, 4.0)])
  assert_eq(@analysis.length(pt, trig, 0), 0.0)
  assert_eq(@analysis.bbox(pt, 0), (3.0, 4.0, 3.0, 4.0))
}

///|
test "features without geometry have no measures" {
  let b = @geom.TableBuilder::new()
  b.end_feature(NoGeometry)
  let t = b.finish()
  let trig = @analysis.Trig::moonbit()
  assert_eq(
    (@analysis.area(t, trig, 0), @analysis.length(t, trig, 0)),
    (0.0, 0.0),
  )
  assert_true(@analysis.centroid(t, 0).0.is_nan())
  let (x0, _, x1, _) = @analysis.bbox(t, 0)
  assert_true(x0 > x1)
}

///|
test "contains_point counts the boundary as inside, holes as outside" {
  let sq = holed()
  let cases = [
    ((0.5, 0.5), false),
    ((0.1, 0.1), true),
    ((0.0, 0.5), true),
    ((1.0, 1.0), true),
    ((2.0, 2.0), false),
    ((0.25, 0.5), true),
  ]
  for c in cases {
    assert_eq(@analysis.contains_point(sq, 0, c.0.0, c.0.1), c.1)
  }
  assert_false(@analysis.contains_point(points([(0.0, 0.0)]), 0, 0.0, 0.0))
  // Nearly collinear: the exact orientation decides.
  let b = @geom.TableBuilder::new()
  for p in [(0.0, 0.0), (1.0e-20, 1.0), (-1.0, 1.0), (0.0, 0.0)] {
    b.point(p.0, p.1)
  }
  b.end_ring()
  b.end_part()
  b.end_feature(Polygon)
  let thin = b.finish()
  assert_true(@analysis.contains_point(thin, 0, 0.0, 0.5))
  assert_false(@analysis.contains_point(thin, 0, 1.0e-19, 0.5))
}

///|
/// Deterministic pseudo-random doubles in [0, 1).
fn lcg(seed : Int32) -> () -> Double {
  let s = Ref(seed.to_uint64())
  () => {
    s.val = s.val * 6364136223846793005UL + 1442695040888963407UL
    (s.val >> 11).to_double() / 9007199254740992.0
  }
}

///|
test "search and neighbors agree with brute force" {
  let r = lcg(7)
  let n = 1000
  let boxes = Array::makei(n, _ => {
    let x = r() * 100.0
    let y = r() * 100.0
    (x, y, x + r() * 3.0, y + r() * 3.0)
  })
  let index = @analysis.Index::new(n, node_size=8)
  for i, b in boxes {
    assert_eq(index.add(b.0, b.1, b.2, b.3), i)
  }
  assert_eq(index.add(0.0, 0.0, 1.0, 1.0), -1)
  assert_true(index.finish())
  for
    q in [
      (10.0, 10.0, 30.0, 25.0),
      (0.0, 0.0, 200.0, 200.0),
      (50.0, 50.0, 50.0, 50.0),
    ] {
    let got = []
    index.search(q.0, q.1, q.2, q.3, got)
    got.sort()
    let want = []
    for i, b in boxes {
      if !(q.2 < b.0 || q.3 < b.1 || q.0 > b.2 || q.1 > b.3) {
        want.push(i)
      }
    }
    assert_eq(got, want)
  }
  let dist = (b : (Double, Double, Double, Double)) => {
    let dx = @cmp.maximum(@cmp.maximum(b.0 - 40.0, 40.0 - b.2), 0.0)
    let dy = @cmp.maximum(@cmp.maximum(b.1 - 60.0, 60.0 - b.3), 0.0)
    dx * dx + dy * dy
  }
  let near5 = []
  index.neighbors(40.0, 60.0, near5, max_results=5)
  let order = Array::makei(n, i => i)
  order.sort_by((a, b) => dist(boxes[a]).compare(dist(boxes[b])))
  assert_eq(near5.length(), 5)
  for i, k in near5 {
    assert_eq(dist(boxes[k]), dist(boxes[order[i]]))
  }
  let one = []
  index.neighbors(40.0, 60.0, one, max_results=1)
  assert_eq(dist(boxes[one[0]]), dist(boxes[order[0]]))
  let within = []
  index.neighbors(40.0, 60.0, within, max_distance=2.0)
  assert_eq(within.length(), boxes.filter(b => dist(b) <= 4.0).length())
}

///|
test "indexes of no items, too few items and a single node" {
  let empty = @analysis.Index::new(0)
  assert_true(empty.finish())
  let out = []
  empty.search(0.0, 0.0, 1.0, 1.0, out)
  empty.neighbors(0.0, 0.0, out)
  assert_eq(out, [])
  let short = @analysis.Index::new(3)
  short.add(0.0, 0.0, 1.0, 1.0) |> ignore
  assert_false(short.finish())
  short.search(0.0, 0.0, 1.0, 1.0, out)
  assert_eq(out, [])
  let small = @analysis.Index::new(2)
  small.add(0.0, 0.0, 1.0, 1.0) |> ignore
  small.add(5.0, 5.0, 6.0, 6.0) |> ignore
  assert_true(small.finish())
  small.search(4.0, 4.0, 10.0, 10.0, out)
  assert_eq(out, [1])
  out.clear()
  small.neighbors(0.0, 0.0, out, max_results=0)
  assert_eq(out, [])
}

///|
test "points_within, collect and grid_count" {
  let polys = holed()
  let pts = points(
    [(0.1, 0.1), (0.5, 0.5), (1.0, 0.5), (3.0, 3.0), (0.9, 0.9)],
    k=[1.0, 2.0, 4.0, 8.0],
  )
  let pindex = @analysis.Index::of_table(polys)
  let hits = []
  pindex.search(0.5, 0.5, 0.5, 0.5, hits)
  assert_eq(hits, [0])
  hits.clear()
  pindex.search(1.5, 1.5, 2.0, 2.0, hits)
  assert_eq(hits, [])
  assert_eq(@analysis.points_within(pts, polys, pindex), [0, 2, 4])
  let sums = @analysis.collect(polys, pts, @analysis.Index::of_table(pts), "k")
  assert_eq(sums, [3.0, 2.0, 5.0])
  let none = @analysis.collect(polys, pts, @analysis.Index::of_table(pts), "x")
  assert_eq(none, [3.0, 0.0, 0.0])
  let grid = @analysis.grid_count(pts, 0.0, 0.0, 1.0, 1.0, 2, 2).unwrap()
  assert_eq(grid, [1, 0, 0, 3])
  assert_true(@analysis.grid_count(pts, 0.0, 0.0, 0.0, 1.0, 2, 2) is None)
  assert_true(@analysis.grid_count(pts, 0.0, 0.0, 1.0, 1.0, 0, 2) is None)
  assert_true(
    @analysis.grid_count(pts, 0.0, 0.0, 1.0, 1.0, 1 << 13, 1 << 13) is None,
  )
}

///|
test "slope, aspect and hillshade of a plane facing east" {
  // Falling 1 m per 1 m cell eastward: 45 degrees, facing east (90).
  let trig = @analysis.Trig::moonbit()
  let n = 4
  let g = @analysis.Grid::new(
    FixedArray::makei(n * n, i => -(i % n).to_double()),
    n,
    n,
    1.0,
    1.0,
  )
  let near = (a : Double, b : Double) => (a - b).abs() < 1.0e-9
  // Inner cells see the full plane; border cells repeat their neighbors.
  assert_true(near(g.slope(trig)[5], 45.0))
  assert_true(near(g.aspect(trig)[5], 90.0))
  // Light from the east (90) falls straight on it: brightest; from the west, darkest.
  let east = g.hillshade(trig, azimuth=90.0, altitude=45.0)
  let west = g.hillshade(trig, azimuth=270.0, altitude=45.0)
  assert_true(east[5] > b'\xf0')
  assert_eq(west[5], b'\x01')
  // A flat grid has no aspect and the shade of the sun's altitude.
  let flat = @analysis.Grid::new(FixedArray::make(n * n, 3.0), n, n, 10.0, 10.0)
  assert_true(flat.aspect(trig)[5].is_nan())
  assert_eq(flat.slope(trig)[5], 0.0)
  assert_eq(
    flat.hillshade(trig)[5].to_int(),
    (1.0 + 254.0 * @math.sin(@math.PI / 4.0)).round().to_int(),
  )
}

///|
test "Grid::sample interpolates between cell centers as GDAL's bilinear" {
  let g = @analysis.Grid::new([0, 10, 20, 30, 40, 50, 60, 70, 85], 3, 3, 1, 1)
  assert_eq(g.sample(1, 1), 20)
  assert_eq(g.sample(1.25, 0.75), 15)
  assert_eq(g.sample(1.7, 1.2), 33)
  assert_eq(g.sample(0.3, 0.3), 0)
  assert_eq(g.sample(2.7, 0.5), 20)
  assert_eq(g.sample(3, 3), 85)
  assert_true(g.sample(3.2, 1).is_nan())
  assert_true(g.sample(-0.1, 1).is_nan())
  let holed = @analysis.Grid::new(
    [0, 10, 20, 30, 40, 50, 60, 70, @double.not_a_number],
    3,
    3,
    1,
    1,
  )
  assert_eq(holed.sample(1.25, 0.75), 15)
  assert_true(holed.sample(1.5, 1.5).is_nan())
}

///|
test "mercator_cell places a point in a mosaic of Web Mercator tiles" {
  let trig = @analysis.Trig::moonbit()
  let (x, y) = @analysis.mercator_cell(trig, 0, 0, 1, 0, 0, 256)
  assert_eq(x, 256)
  assert_eq(y, 256)
  let (x, y) = @analysis.mercator_cell(trig, -180, 0, 2, 1, 1, 256)
  assert_eq(x, -256)
  assert_eq(y, 256)
  // Tokyo Station at zoom 14 lies in tile (14552, 6451).
  let (x, y) = @analysis.mercator_cell(
    trig, 139.7671, 35.6812, 14, 14552, 6451, 256,
  )
  assert_true(x >= 0 && x < 256 && y >= 0 && y < 256)
}
