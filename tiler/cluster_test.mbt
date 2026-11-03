///|
fn points(coords : Array[(Double, Double)]) -> @geom.Table {
  let b = @geom.TableBuilder::new()
  for i, c in coords {
    b.point(c.0, c.1)
    b.end_ring()
    b.end_part()
    b.prop("i", Num(i.to_double()))
    b.end_feature(Point, id=Some(Str("p\{i}")))
  }
  b.finish()
}

///|
fn summary(fs : Array[@tiler.ClusterFeature]) -> Array[(Int32, Int32, Int32)] {
  fs.map(f => (f.row, f.cluster_id, f.count))
}

///|
/// Three points 0.001° apart around (0, 0): about 2982 tree units, so
/// they first cluster at zoom 14 (radius 5120 units).
let three : Array[(Double, Double)] = [(0.0, 0.0), (0.001, 0.0), (0.0, 0.001)]

///|
test "nearby points cluster below the zoom their distance allows" {
  let c = @tiler.ClusterIndex::new(points(three))
  // Cluster id: (index 0 << 5) + (zoom 14 + 1) + 3 points.
  assert_eq(summary(c.tile(0, 0, 0).unwrap()), [(-1, 18, 3)])
  assert_eq(summary(c.tile(14, 8192, 8191).unwrap()), [(-1, 18, 3)])
  let f = c.tile(0, 0, 0).unwrap()[0]
  assert_eq((f.x, f.y), (256.0, 256.0))
  let near = c.tile(15, 16384, 16383).unwrap()
  assert_true(near.iter().all(f => f.row >= 0 && f.count == 1))
  assert_true(near.length() >= 2)
}

///|
test "expansion zoom, children and leaves of a cluster" {
  let c = @tiler.ClusterIndex::new(points(three))
  assert_eq(c.expansion_zoom(18), 15)
  let children = c.children(18).unwrap()
  let rows = children.map(f => f.row)
  rows.sort()
  assert_eq(rows, [0, 1, 2])
  let p0 = children.filter(f => f.row == 0)[0]
  assert_true(p0.x.abs() < 1.0e-9 && p0.y.abs() < 1.0e-9)
  assert_eq(c.leaves(18, limit=2).unwrap().length(), 2)
  assert_eq(c.leaves(18, limit=0).unwrap().length(), 3)
  assert_eq(c.leaves(18, limit=10, offset=2).unwrap().length(), 1)
  assert_eq(c.leaves(18, limit=-1, offset=5).unwrap().length(), 0)
}

///|
test "unknown cluster ids have no children or leaves" {
  let c = @tiler.ClusterIndex::new(points(three))
  assert_eq(c.children(0).map(a => a.length()), None)
  assert_eq(c.children(19).map(a => a.length()), None)
  assert_eq(c.children(18 + (5 << 5)).map(a => a.length()), None)
  assert_eq(c.leaves(-7).map(a => a.length()), None)
  assert_eq(c.expansion_zoom(-7), -10)
}

///|
test "min_points and max_zoom limit clustering" {
  let opts = { ..@tiler.ClusterOptions::default(), min_points: 4, }
  let c = @tiler.ClusterIndex::new(points(three), options=opts)
  assert_eq(c.tile(0, 0, 0).unwrap().length(), 3)
  let opts = { ..@tiler.ClusterOptions::default(), max_zoom: -1, }
  let c = @tiler.ClusterIndex::new(points(three), options=opts)
  assert_eq(summary(c.tile(0, 0, 0).unwrap()), [
    (0, -1, 1),
    (1, -1, 1),
    (2, -1, 1),
  ])
}

///|
test "multipoints cluster position by position; lines are left out" {
  let b = @geom.TableBuilder::new()
  b.point(10.0, 10.0)
  b.point(10.001, 10.0)
  b.end_ring()
  b.end_part()
  b.end_feature(MultiPoint)
  b.point(0.0, 0.0)
  b.point(1.0, 1.0)
  b.end_ring()
  b.end_part()
  b.end_feature(LineString)
  let c = @tiler.ClusterIndex::new(b.finish())
  assert_eq(summary(c.tile(0, 0, 0).unwrap()), [(-1, 2 + 15 + 0, 2)])
  assert_eq(c.leaves(17).unwrap().map(f => f.row), [0, 0])
}

///|
test "no points, no tiles; zooms past 24 have none" {
  let c = @tiler.ClusterIndex::new(@geom.TableBuilder::new().finish())
  assert_eq(c.tile(0, 0, 0).map(a => a.length()), None)
  let c = @tiler.ClusterIndex::new(points(three))
  assert_eq(c.tile(25, 0, 0).map(a => a.length()), None)
  assert_eq(c.tile(-1, 0, 0).map(a => a.length()), None)
}

///|
test "points near the antimeridian are copied across it when wrapping" {
  let t = points([(179.0, 0.0)])
  let c = @tiler.ClusterIndex::new(t, wrap_buffer=0.25)
  // The westmost tile shows the copy at x - 1 and, past its west edge, the
  // point itself, as geojson-vt does.
  let west = c.tile(1, 0, 1).unwrap()
  assert_eq(summary(west), [(0, -1, 1), (0, -1, 1)])
  assert_eq(west.map(f => f.x), [-3.0, -3.0])
  let no_wrap = { ..@tiler.ClusterOptions::default(), wrap: false, }
  let c = @tiler.ClusterIndex::new(
    points([(200.0, 0.0), (0.0, 0.0)]),
    options=no_wrap,
  )
  assert_eq(summary(c.tile(0, 0, 0).unwrap()), [(1, -1, 1)])
  assert_eq(c.tile(0, 1, 0).map(a => a.length()), None)
}

///|
test "thousands of points: every one is in exactly one cluster or alone" {
  let coords = []
  let mut s = 42U
  let rand = () => {
    s = s * 1103515245U + 12345U
    s.to_double() / 4294967296.0
  }
  for _ in 0..<3000 {
    coords.push((rand() * 20.0, rand() * 20.0))
  }
  let c = @tiler.ClusterIndex::new(points(coords))
  assert_true(c.tile(3, 4, 3).unwrap().length() > 1)
  let all = c.tile(0, 0, 0).unwrap()
  assert_eq(all.fold(init=0, (n, f) => n + f.count), 3000)
  for f in all {
    if f.row < 0 {
      assert_eq(c.leaves(f.cluster_id, limit=-1).unwrap().length(), f.count)
    }
  }
}

///|
test "abbreviated counts follow geojson-vt" {
  assert_eq(@tiler.abbreviated_count(999), Num(999.0))
  assert_eq(@tiler.abbreviated_count(1000), Str("1k"))
  assert_eq(@tiler.abbreviated_count(1050), Str("1.1k"))
  assert_eq(@tiler.abbreviated_count(9999), Str("10k"))
  assert_eq(@tiler.abbreviated_count(12500), Str("13k"))
}

///|
test "cluster tiles encode as columnar tiles" {
  let t = points(three)
  let c = @tiler.ClusterIndex::new(t)
  let r = @core.ByteReader::new(
    @tiler.encode_cluster_tile(c.tile(0, 0, 0).unwrap(), t)[:],
  )
  assert_eq([r.u32(), r.u32(), r.u32(), r.u32()], [1, 1, 1, 4])
  assert_eq(r.u8(), 1)
  r.pad4()
  assert_eq([r.u32(), r.u32(), r.i16(), r.i16()], [1, 1, 256, 256])
  let keys = Array::makei(4, _ => r.utf8())
  assert_eq(keys, [
    "cluster", "cluster_id", "point_count", "point_count_abbreviated",
  ])
  let values = Array::makei(5, _ => @geom.read_prop(r))
  assert_eq(values, [
    Some(Bool(true)),
    Some(Num(18.0)),
    Some(Num(3.0)),
    Some(Num(3.0)),
    Some(Num(18.0)),
  ])
  let near = c.tile(16, 32768, 32767).unwrap()
  let r = @core.ByteReader::new(@tiler.encode_cluster_tile(near, t)[:])
  let n = near.length()
  assert_eq([r.u32(), r.u32(), r.u32(), r.u32()], [n, n, n, 1])
}

///|
test "cluster features encode with their properties and ids" {
  let t = points(three)
  let c = @tiler.ClusterIndex::new(t)
  let fs = c.leaves(18, limit=1).unwrap()
  let r = @core.ByteReader::new(@tiler.encode_cluster_features(fs, t)[:])
  assert_eq(r.u32(), 1)
  r.f64() |> ignore
  r.f64() |> ignore
  let id = @geom.read_prop(r)
  assert_eq(r.u32(), 1)
  assert_eq(r.utf8(), "i")
  let i = @geom.read_prop(r)
  assert_true(
    (id, i) is (Some(Str("p0")), Some(Num(0.0))) ||
    (id, i) is (Some(Str("p1")), Some(Num(1.0))) ||
    (id, i) is (Some(Str("p2")), Some(Num(2.0))),
  )
  let r = @core.ByteReader::new(
    @tiler.encode_cluster_features(c.tile(0, 0, 0).unwrap(), t)[:],
  )
  assert_eq(r.u32(), 1)
  r.f64() |> ignore
  r.f64() |> ignore
  assert_eq(@geom.read_prop(r), Some(Num(18.0)))
  assert_eq(r.u32(), 4)
}
