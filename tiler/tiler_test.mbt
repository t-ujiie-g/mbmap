///|
fn table(f : (@geom.TableBuilder) -> Unit) -> @geom.Table {
  let b = @geom.TableBuilder::new()
  f(b)
  b.finish()
}

///|
fn square(b : @geom.TableBuilder, x : Double, y : Double, d : Double) -> Unit {
  for p in [(x, y), (x + d, y), (x + d, y + d), (x, y + d), (x, y)] {
    b.point(p.0, p.1)
  }
  b.end_ring()
}

///|
fn ring(d : @tiler.TileData, r : Int32) -> Array[Int32] {
  let a = if r == 0 { 0 } else { d.point_ends[r - 1] }
  d.xy[a * 2:d.point_ends[r] * 2].to_owned()
}

///|
test "a point lands at its tile position; empty tiles are None" {
  let t = @tiler.Tiler::new(
    table(b => {
      b.point(0.0, 0.0)
      b.end_ring()
      b.end_part()
      b.end_feature(Point)
    }),
  )
  // Longitude 0, latitude 0 is the world's center: tile 1/1/1's corner.
  let d = t.tile(1, 1, 1).unwrap()
  assert_eq((d.types, d.rows, d.xy), ([1], [0], [0, 0]))
  assert_eq(t.tile(0, 0, 0).unwrap().xy, [2048, 2048])
  assert_eq(t.tile(3, 0, 0).map(d => d.types.length()), None)
  assert_eq(t.tile(-1, 0, 0).map(d => d.types.length()), None)
}

///|
test "polygons are clipped to the tile and its buffer and wound for MVT" {
  // A 20° square around the equator, counterclockwise in lng/lat (so
  // clockwise in tile space, y down) with a hole wound the same way.
  let t = @tiler.Tiler::new(
    table(b => {
      square(b, -10.0, -10.0, 20.0)
      square(b, -2.0, -2.0, 4.0)
      b.end_part()
      b.prop("name", Str("a"))
      b.end_feature(Polygon)
    }),
  )
  let d = t.tile(1, 1, 0).unwrap()
  assert_eq((d.types, d.ring_ends), ([3], [2]))
  let outer = ring(d, 0)
  // Cut at the buffer (64 units) past the tile's left and bottom edges.
  assert_true(outer.iter().all(v => v >= -64 && v <= 4096 + 64))
  assert_true(outer.contains(-64))
  // Exterior clockwise in tile space: positive shoelace sum with y down.
  let area = (r : Array[Int32]) => {
    let mut s = 0
    let mut i = 0
    while i + 3 < r.length() {
      s += r[i] * r[i + 3] - r[i + 2] * r[i + 1]
      i += 2
    }
    s
  }
  assert_true(area(outer) > 0)
  assert_true(area(ring(d, 1)) < 0)
}

///|
test "features near the antimeridian are copied across it when wrapping" {
  let line = table(b => {
    b.point(179.0, 0.0)
    b.point(181.0, 1.0)
    b.end_ring()
    b.end_part()
    b.end_feature(LineString)
  })
  let wrapped = @tiler.Tiler::new(line)
  // The western edge tile gets the part past 180°.
  assert_true(wrapped.tile(2, 0, 1) is Some(_))
  let flat = @tiler.Tiler::new(line, options={
    ..@tiler.TilerOptions::default(),
    wrap: false,
  })
  assert_eq(flat.tile(2, 0, 1).map(d => d.types.length()), None)
  assert_eq(flat.tile(2, -1, 1).map(d => d.types.length()), None)
}

///|
test "tiles below the index are cut on demand, up to max_zoom" {
  let t = @tiler.Tiler::new(
    table(b => {
      b.point(139.7671, 35.6812)
      b.end_ring()
      b.end_part()
      b.end_feature(Point)
    }),
    options={ ..@tiler.TilerOptions::default(), index_max_zoom: 2, },
    trig=@tiler.Trig::moonbit(),
  )
  // z14 (max_zoom) is past the index: cut from z2 on request.
  let d = t.tile(14, 14552, 6451).unwrap()
  assert_eq(d.types, [1])
  assert_true(d.xy[0] >= 0 && d.xy[0] < 4096 && d.xy[1] >= 0 && d.xy[1] < 4096)
  // Beyond max_zoom there are no tiles (callers overzoom), as in geojson-vt.
  assert_eq(t.tile(18, 232847, 103226).map(d => d.types), None)
}

///|
test "simplification drops rings too small to see at a zoom" {
  let tiny = table(b => {
    square(b, 10.0, 10.0, 0.00001)
    b.end_part()
    b.end_feature(Polygon)
  })
  let t = @tiler.Tiler::new(tiny)
  assert_eq(t.tile(0, 0, 0).unwrap().types, [])
  assert_eq(t.tile(14, 8647, 7734).map(d => d.types), Some([3]))
}

///|
test "encode_tile writes the columnar layout with only the tile's keys, then ids" {
  let t = table(b => {
    b.point(-90.0, 45.0)
    b.end_ring()
    b.end_part()
    b.prop("k", Num(1.0))
    b.prop("s", Str("x"))
    b.end_feature(Point, id=Some(Str("a")))
    b.point(90.0, -45.0)
    b.end_ring()
    b.end_part()
    b.prop("far", Bool(true))
    b.end_feature(Point)
  })
  let d = @tiler.Tiler::new(t).tile(1, 0, 0).unwrap()
  let bytes = @tiler.encode_tile(d, t)
  let r = @core.ByteReader::new(bytes[:])
  assert_eq((r.u32(), r.u32(), r.u32(), r.u32()), (1, 1, 1, 2))
  assert_eq(r.u8(), 1)
  r.pad4()
  assert_eq((r.u32(), r.u32()), (1, 1))
  assert_eq([r.i16(), r.i16()], d.xy)
  r.pad4()
  assert_eq((r.utf8(), r.utf8()), ("k", "s"))
  assert_eq(@geom.read_prop(r), Some(Num(1.0)))
  assert_eq(@geom.read_prop(r), Some(Str("x")))
  assert_eq(@geom.read_prop(r), Some(Str("a")))
  assert_true(r.done())
}

///|
fn metrics_tiler(t : @geom.Table) -> @tiler.Tiler {
  @tiler.Tiler::new(t, options={
    ..@tiler.TilerOptions::default(),
    line_metrics: true,
  })
}

///|
test "line metrics tell where each tile's slice lies along its line" {
  // A line from longitude -10 to 10 at latitude 10, cut at x 0.5 plus the buffer.
  let t = table(b => {
    b.point(-10.0, 10.0)
    b.point(10.0, 10.0)
    b.end_ring()
    b.end_part()
    b.end_feature(LineString)
  })
  let buffer = 64.0 / 4096.0 / 2.0
  let left = metrics_tiler(t).tile(1, 0, 0).unwrap()
  assert_eq(left.clips.length(), 2)
  assert_eq(left.clips[0], 0.0)
  assert_true((left.clips[1] - (0.5 + buffer * 18.0)).abs() < 1.0e-9)
  let right = metrics_tiler(t).tile(1, 1, 0).unwrap()
  assert_true((right.clips[0] - (0.5 - buffer * 18.0)).abs() < 1.0e-9)
  assert_eq(right.clips[1], 1.0)
  // Without line metrics there are none.
  assert_eq(@tiler.Tiler::new(t).tile(1, 0, 0).unwrap().clips, [])
}

///|
test "line metrics split multi-lines into features and reach encode_tile" {
  let t = table(b => {
    b.point(-100.0, 10.0)
    b.point(-80.0, 10.0)
    b.end_ring()
    b.end_part()
    b.point(-100.0, 20.0)
    b.point(-80.0, 20.0)
    b.end_ring()
    b.end_part()
    b.end_feature(MultiLineString)
    b.point(-100.0, 30.0)
    b.point(-90.0, 30.0)
    b.point(-90.0, 40.0)
    b.point(-100.0, 30.0)
    b.end_ring()
    b.end_part()
    b.end_feature(Polygon)
  })
  let d = metrics_tiler(t).tile(1, 0, 0).unwrap()
  assert_eq(d.types, [2, 2, 3])
  assert_eq(d.rows, [0, 0, 1])
  assert_eq(d.clips[:4].to_owned(), [0.0, 1.0, 0.0, 1.0])
  assert_true(d.clips[4].is_nan() && d.clips[5].is_nan())
  let r = @core.ByteReader::new(@tiler.encode_tile(d, t)[:])
  assert_eq((r.u32(), r.u32(), r.u32(), r.u32()), (3, 3, 8, 2))
  for _ in 0..<3 {
    r.u8() |> ignore
  }
  r.pad4()
  for _ in 0..<(3 + 3 + 8) {
    r.u32() |> ignore
  }
  assert_eq((r.utf8(), r.utf8()), (@tiler.CLIP_START, @tiler.CLIP_END))
  let props = Array::makei(6, _ => @geom.read_prop(r))
  assert_eq(props, [
    Some(Num(0.0)),
    Some(Num(0.0)),
    None,
    Some(Num(1.0)),
    Some(Num(1.0)),
    None,
  ])
}
