///|
fn cmd(id : Int32, count : Int32) -> Int32 {
  (count << 3) | id
}

///|
/// A layer holding one feature of the given type and command stream.
fn tile_with(
  layer_name : String,
  geom_type : Int32,
  geometry : Array[Int32],
) -> @pbf.Writer {
  let g = @pbf.Writer::new()
  let mut i = 0
  while i < geometry.length() {
    let header = geometry[i]
    g.write_varint32(header)
    i += 1
    if (header & 7) != 7 {
      for _ in 0..<((header >> 3) * 2) {
        g.write_svarint32(geometry[i])
        i += 1
      }
    }
  }
  let f = @pbf.Writer::new()
  f.write_tag(3, @pbf.WIRE_VARINT)
  f.write_varint32(geom_type)
  f.write_tag(4, @pbf.WIRE_LEN)
  f.write_bytes(g.to_bytes()[:])
  let l = @pbf.Writer::new()
  l.write_tag(1, @pbf.WIRE_LEN)
  l.write_string(layer_name)
  l.write_tag(2, @pbf.WIRE_LEN)
  l.write_bytes(f.to_bytes()[:])
  l
}

///|
fn tile_of(layers : Array[@pbf.Writer]) -> Bytes {
  let t = @pbf.Writer::new()
  for l in layers {
    t.write_tag(3, @pbf.WIRE_LEN)
    t.write_bytes(l.to_bytes()[:])
  }
  t.to_bytes()
}

///|
let style_json : String =
  #|{"sources": {"a": {"type": "vector", "tiles": ["t"]}, "b": {"type": "vector", "tiles": ["u"]}},
  #| "layers": [
  #|  {"id": "bg", "type": "background"},
  #|  {"id": "area", "type": "fill", "source": "a", "source-layer": "poly"},
  #|  {"id": "other", "type": "line", "source": "b", "source-layer": "line"},
  #|  {"id": "late", "type": "line", "source": "a", "source-layer": "line", "minzoom": 15},
  #|  {"id": "road", "type": "line", "source": "a", "source-layer": "line"},
  #|  {"id": "edge", "type": "line", "source": "a", "source-layer": "poly",
  #|   "filter": ["==", ["geometry-type"], "LineString"]}
  #|]}

///|
fn u32_at(b : BytesView, at : Int32) -> Int32 {
  b[at].to_int() |
  (b[at + 1].to_int() << 8) |
  (b[at + 2].to_int() << 16) |
  (b[at + 3].to_int() << 24)
}

///|
fn i16_at(b : BytesView, at : Int32) -> Int32 {
  let v = b[at].to_int() | (b[at + 1].to_int() << 8)
  if v >= 0x8000 {
    v - 0x10000
  } else {
    v
  }
}

///|
fn sample_tile() -> Bytes {
  tile_of([
    tile_with("poly", 3, [cmd(1, 1), 0, 0, cmd(2, 2), 100, 0, 0, 100, cmd(7, 1)]),
    tile_with("line", 2, [cmd(1, 1), -10, 5, cmd(2, 1), 50, 0]),
  ])
}

///|
test "process packs fill and line layers of the source in style order" {
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style_json)[:])
  assert_true(p.process("a", sample_tile()[:], 14))
  let b = p.out.to_bytes()[:]
  assert_eq(u32_at(b, 0), 2)
  assert_eq(p.out.layer_count(), 2)
  let entry = (k : Int32, w : Int32) => {
    u32_at(b, 4 + (k * @worker.LAYER_ENTRY_WORDS + w) * 4)
  }
  // Layer 1 ("area"): a triangle of 4 points (closing point repeated).
  assert_eq((entry(0, 0), entry(0, 1)), (1, @worker.KIND_FILL))
  assert_eq((entry(0, 3), entry(0, 5)), (4 * @worker.FILL_VERTEX_BYTES, 3))
  let v = entry(0, 2)
  assert_eq((i16_at(b, v + 4), i16_at(b, v + 6)), (100, 0))
  // Layer 4 ("road"); "other" is another source, "late" starts at z15 and
  // "edge" filters out the polygon.
  assert_eq((entry(1, 0), entry(1, 1)), (4, @worker.KIND_LINE))
  let lv = entry(1, 2)
  assert_eq(entry(1, 3), 4 * @worker.LINE_VERTEX_BYTES)
  assert_eq(
    (i16_at(b, lv), i16_at(b, lv + 2), b[lv + 5].to_int(), b[lv + 6].to_int()),
    (-10, 5, 63, 1),
  )
  for k in 0..<2 {
    // Small layers use 16-bit indices.
    assert_eq(entry(k, 6), 2)
    let count = entry(k, 5)
    let vertices = entry(k, 3) /
      (if entry(k, 1) == @worker.KIND_FILL {
        @worker.FILL_VERTEX_BYTES
      } else {
        @worker.LINE_VERTEX_BYTES
      })
    for i in 0..<count {
      let at = entry(k, 4) + i * 2
      assert_true((b[at].to_int() | (b[at + 1].to_int() << 8)) < vertices)
    }
    assert_eq(entry(k, 2) % 4, 0)
  }
  assert_eq(b.length(), entry(1, 4) + (entry(1, 5) * 2 + 3) / 4 * 4)
}

///|
test "zoom ranges are checked against the tile zoom" {
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style_json)[:])
  assert_true(p.process("a", sample_tile()[:], 15))
  assert_eq(p.out.layer_count(), 3)
  assert_true(p.process("b", sample_tile()[:], 15))
  assert_eq(p.out.layer_count(), 1)
}

///|
test "coordinates beyond Int16 are clamped" {
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style_json)[:])
  let far = tile_of([
    tile_with("poly", 3, [
      cmd(1, 1),
      40000,
      0,
      cmd(2, 2),
      10,
      0,
      0,
      10,
      cmd(7, 1),
    ]),
  ])
  assert_true(p.process("a", far[:], 14))
  let b = p.out.to_bytes()[:]
  assert_eq(i16_at(b, u32_at(b, 4 + 2 * 4)), 32767)
}

///|
test "malformed tiles and styles fail with a message" {
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style_json)[:])
  assert_false(p.process("a", b"\x1a\x7f"[:], 14))
  assert_true(p.error().has_prefix("malformed tile"))
  assert_true(p.error_utf8().length() > 0)
  let bad = tile_of([tile_with("line", 2, [cmd(2, 1), 1, 1])])
  assert_false(p.process("a", bad[:], 14))
  assert_true(p.error().has_prefix("malformed geometry in line[0]"))
  try @worker.TileProcessor::from_utf8(b"{\"layers\": 3}"[:]) catch {
    Invalid(path~, _) => assert_eq(path, "layers")
    e => fail("unexpected \{Repr(e)}")
  } noraise {
    _ => fail("expected a style error")
  }
}

///|
test "layers with the same geometry share one buffer" {
  let style =
    #|{"sources": {"a": {"type": "vector", "tiles": ["t"]}},
    #| "layers": [
    #|  {"id": "casing", "type": "line", "source": "a", "source-layer": "line",
    #|   "layout": {"line-cap": "round"}, "paint": {"line-width": 6}},
    #|  {"id": "road", "type": "line", "source": "a", "source-layer": "line",
    #|   "layout": {"line-cap": "round"}, "paint": {"line-width": 3, "line-color": "#fff"}},
    #|  {"id": "butt", "type": "line", "source": "a", "source-layer": "line"}
    #|]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  assert_true(p.process("a", sample_tile()[:], 14))
  let b = p.out.to_bytes()[:]
  let entry = (k : Int32, w : Int32) => {
    u32_at(b, 4 + (k * @worker.LAYER_ENTRY_WORDS + w) * 4)
  }
  assert_eq(p.out.layer_count(), 3)
  assert_eq((entry(0, 0), entry(1, 0), entry(2, 0)), (0, 1, 2))
  // "road" reuses "casing"'s data; "butt" has another cap, so its own.
  for w in 1..<@worker.LAYER_ENTRY_WORDS {
    assert_eq(entry(1, w), entry(0, w))
  }
  assert_true(entry(2, 2) > entry(0, 2))
}

///|
test "layers are rescaled to TILE_EXTENT" {
  let l = tile_with("poly", 3, [
    cmd(1, 1),
    0,
    0,
    cmd(2, 2),
    100,
    0,
    0,
    100,
    cmd(7, 1),
  ])
  l.write_tag(5, @pbf.WIRE_VARINT)
  l.write_varint32(8192)
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style_json)[:])
  assert_true(p.process("a", tile_of([l])[:], 14))
  let b = p.out.to_bytes()[:]
  let v = u32_at(b, 4 + 2 * 4)
  assert_eq((i16_at(b, v + 4), i16_at(b, v + 6)), (50, 0))
}

///|
/// A "road" layer of line features, each with property `k` set to the given
/// value (or no `k` for None).
fn road_layer(ks : Array[Int32?]) -> @pbf.Writer {
  let l = @pbf.Writer::new()
  l.write_tag(1, @pbf.WIRE_LEN)
  l.write_string("road")
  for i, k in ks {
    // MoveTo (i * 20, 0), LineTo (+10, +10).
    let g = @pbf.Writer::new()
    g.write_varint32(cmd(1, 1))
    g.write_svarint32(i * 20)
    g.write_svarint32(0)
    g.write_varint32(cmd(2, 1))
    g.write_svarint32(10)
    g.write_svarint32(10)
    let f = @pbf.Writer::new()
    if k is Some(k) {
      let t = @pbf.Writer::new()
      t.write_varint32(0)
      t.write_varint32(k)
      f.write_tag(2, @pbf.WIRE_LEN)
      f.write_bytes(t.to_bytes()[:])
    }
    f.write_tag(3, @pbf.WIRE_VARINT)
    f.write_varint32(2)
    f.write_tag(4, @pbf.WIRE_LEN)
    f.write_bytes(g.to_bytes()[:])
    l.write_tag(2, @pbf.WIRE_LEN)
    l.write_bytes(f.to_bytes()[:])
  }
  l.write_tag(3, @pbf.WIRE_LEN)
  l.write_string("k")
  for v in 0..<2 {
    let vw = @pbf.Writer::new()
    vw.write_tag(4, @pbf.WIRE_VARINT)
    vw.write_varint32(v)
    l.write_tag(4, @pbf.WIRE_LEN)
    l.write_bytes(vw.to_bytes()[:])
  }
  l
}

///|
/// Entry `k`'s group properties as `key=value` pairs.
fn props_of(b : BytesView, k : Int32) -> Array[String] raise {
  let entry = (w : Int32) => {
    u32_at(b, 4 + (k * @worker.LAYER_ENTRY_WORDS + w) * 4)
  }
  let mut at = entry(7)
  let str = () => {
    let n = u32_at(b, at)
    let s = @utf8.decode_lossy(b[at + 4:at + 4 + n])
    at += 4 + n
    s
  }
  let out = []
  let count = u32_at(b, entry(7))
  at = entry(7) + 4
  for _ in 0..<count {
    let key = str()
    let t = b[at].to_int()
    at += 1
    let value = if t == @core.PROP_NUMBER {
      let mut bits = 0UL
      for i in 0..<8 {
        bits = bits | (b[at + i].to_uint64() << (i * 8))
      }
      at += 8
      bits.reinterpret_as_double().to_string()
    } else if t == @core.PROP_STRING {
      "\"\{str()}\""
    } else {
      ["null", "false", "true"][t]
    }
    out.push("\{key}=\{value}")
  }
  assert_eq(at, entry(7) + entry(8))
  out
}

///|
test "data-driven paint goes per vertex, and a layer sharing its geometry gets its own" {
  let style =
    #|{"sources": {"a": {"type": "vector", "tiles": ["t"]}},
    #| "layers": [
    #|  {"id": "road", "type": "line", "source": "a", "source-layer": "road",
    #|   "paint": {"line-width": ["case", ["has", "k"], ["match", ["get", "k"], 0, 2, 4], 1]}},
    #|  {"id": "plain", "type": "line", "source": "a", "source-layer": "road"},
    #|  {"id": "tinted", "type": "line", "source": "a", "source-layer": "road",
    #|   "paint": {"line-opacity": ["match", ["get", "k"], 1, 0.5, 1]}}
    #|]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  // Four lines of 4 vertices: k = 0, 1, 0 and one without k.
  assert_true(
    p.process(
      "a",
      tile_of([road_layer([Some(0), Some(1), Some(0), None])])[:],
      14,
    ),
  )
  let b = p.out.to_bytes()[:]
  let entry = (k : Int32, w : Int32) => {
    u32_at(b, 4 + (k * @worker.LAYER_ENTRY_WORDS + w) * 4)
  }
  // One entry per layer: the header has room for three.
  assert_eq(p.out.layer_count(), 3)
  assert_eq(entry(0, 2), 4 + 3 * @worker.LAYER_ENTRY_WORDS * 4)
  assert_eq(entry(0, 3), 16 * @worker.LINE_VERTEX_BYTES)
  // The width, one float per vertex (a value without a zoom curve).
  let float_at = (at : Int32) => {
    Float::reinterpret_from_int(u32_at(b, at)).to_double()
  }
  let widths = Array::makei(4, f => float_at(entry(0, 9) + f * 4 * 4))
  assert_eq(entry(0, 10), 16 * 4)
  assert_eq(widths, [2.0, 4.0, 2.0, 1.0])
  assert_eq(float_at(entry(0, 9) + 4), 2.0)
  // "plain" shares the geometry and has no paint of its own; "tinted" shares it with its own.
  assert_eq((entry(1, 2), entry(1, 9), entry(1, 10)), (entry(0, 2), 0, 0))
  assert_eq((entry(2, 2), entry(2, 10)), (entry(0, 2), 16 * 4))
  let opacities = Array::makei(4, f => float_at(entry(2, 9) + f * 4 * 4))
  assert_eq(opacities, [1.0, 0.5, 1.0, 1.0])
}

///|
test "property filters select features" {
  let style =
    #|{"sources": {"a": {"type": "vector", "tiles": ["t"]}},
    #| "layers": [{"id": "one", "type": "line", "source": "a", "source-layer": "road",
    #|   "filter": ["==", ["get", "k"], 1]}]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  assert_true(
    p.process("a", tile_of([road_layer([Some(0), Some(1), None])])[:], 14),
  )
  let b = p.out.to_bytes()[:]
  assert_eq(u32_at(b, 4 + 3 * 4), 4 * @worker.LINE_VERTEX_BYTES)
}

///|
test "circle layers pack one quad per point and share buffers like other kinds" {
  let style =
    #|{"sources": {"a": {"type": "vector", "tiles": ["t"]}},
    #| "layers": [
    #|  {"id": "dots", "type": "circle", "source": "a", "source-layer": "pts"},
    #|  {"id": "halo", "type": "circle", "source": "a", "source-layer": "pts",
    #|   "paint": {"circle-radius": 9}},
    #|  {"id": "vertices", "type": "circle", "source": "a", "source-layer": "line"}
    #|]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  // A MultiPoint with three points, one of them outside the tile; and a line,
  // whose vertices get circles as MapLibre draws them.
  let tile = tile_of([
    tile_with("pts", 1, [cmd(1, 3), 10, 20, 5000, 0, -4990, 10]),
    tile_with("line", 2, [cmd(1, 1), 0, 0, cmd(2, 1), 50, 0]),
  ])
  assert_true(p.process("a", tile[:], 14))
  let b = p.out.to_bytes()[:]
  let entry = (k : Int32, w : Int32) => {
    u32_at(b, 4 + (k * @worker.LAYER_ENTRY_WORDS + w) * 4)
  }
  assert_eq(p.out.layer_count(), 3)
  assert_eq(
    (entry(0, 1), entry(1, 1), entry(2, 1)),
    (@worker.KIND_CIRCLE, @worker.KIND_CIRCLE, @worker.KIND_CIRCLE),
  )
  assert_eq(entry(2, 5), 12)
  // Two points inside the tile: 8 vertices, 12 indices; "halo" reuses them.
  assert_eq((entry(0, 3), entry(0, 5)), (8 * @worker.LINE_VERTEX_BYTES, 12))
  assert_eq((entry(1, 0), entry(1, 2)), (1, entry(0, 2)))
  let v = entry(0, 2)
  assert_eq((i16_at(b, v), i16_at(b, v + 2)), (10, 20))
  assert_eq((b[v + 4].to_int(), b[v + 5].to_int()), (256 - 63, 256 - 63))
  assert_eq((i16_at(b, v + 32), i16_at(b, v + 34)), (20, 30))
}

///|
/// A GeoJSON source's tile as the GeoJSON worker sends it: two points (one
/// with k = 1) and a square, cut at 0/0/0.
fn geojson_tile() -> Bytes {
  let b = @geom.TableBuilder::new()
  b.point(0.0, 0.0)
  b.end_ring()
  b.end_part()
  b.prop("k", Num(1.0))
  b.end_feature(Point)
  b.point(10.0, 10.0)
  b.end_ring()
  b.end_part()
  b.end_feature(Point)
  for
    p in [
      (-20.0, -20.0),
      (20.0, -20.0),
      (20.0, 20.0),
      (-20.0, 20.0),
      (-20.0, -20.0),
    ] {
    b.point(p.0, p.1)
  }
  b.end_ring()
  b.end_part()
  b.prop("name", Str("sq"))
  b.end_feature(Polygon, id=Some(Str("square")))
  let table = b.finish()
  let tiler = @tiler.Tiler::new(table)
  @tiler.encode_tile(tiler.tile(0, 0, 0).unwrap(), table)
}

///|
test "GeoJSON sources draw from columnar tiles, with filters and properties" {
  let style =
    #|{"sources": {"g": {"type": "geojson", "data": "x"}},
    #| "layers": [
    #|  {"id": "area", "type": "fill", "source": "g"},
    #|  {"id": "dots", "type": "circle", "source": "g", "filter": ["has", "k"],
    #|   "paint": {"circle-radius": ["get", "k"]}}
    #|]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  assert_true(p.process("g", geojson_tile()[:], 0))
  let b = p.out.to_bytes()[:]
  let entry = (k : Int32, w : Int32) => {
    u32_at(b, 4 + (k * @worker.LAYER_ENTRY_WORDS + w) * 4)
  }
  assert_eq(p.out.layer_count(), 2)
  // The square: 4 corners (5 with the closing point), 2 triangles, and its
  // outline: 4 edges as index pairs, after the triangles' indices.
  assert_eq((entry(0, 0), entry(0, 1), entry(0, 5)), (0, @worker.KIND_FILL, 6))
  assert_eq(entry(0, 12), 8)
  let outline = Array::makei(8, i => {
    let at = entry(0, 11) + i * 2
    b[at].to_int() | (b[at + 1].to_int() << 8)
  })
  assert_eq(outline, [0, 1, 1, 2, 2, 3, 3, 4])
  // Only the point with k, its radius per vertex.
  assert_eq((entry(1, 0), entry(1, 1)), (1, @worker.KIND_CIRCLE))
  assert_eq(entry(1, 3), 4 * @worker.LINE_VERTEX_BYTES)
  assert_eq((entry(1, 8), entry(1, 10)), (0, 4 * 4))
  assert_eq(
    Float::reinterpret_from_int(u32_at(b, entry(1, 9))).to_double(),
    1.0,
  )
  // The point at 0, 0 lands in the tile's center.
  let v = entry(1, 2)
  assert_eq((i16_at(b, v), i16_at(b, v + 2)), (2048, 2048))
}

///|
test "malformed columnar tiles fail with a message" {
  let style =
    #|{"sources": {"g": {"type": "geojson", "data": "x"}},
    #| "layers": [{"id": "area", "type": "fill", "source": "g"}]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  let good = geojson_tile()
  for n in 0..<good.length() {
    assert_false(p.process("g", good[0:n], 0))
    assert_eq(p.error(), "malformed GeoJSON tile")
  }
  // A ring count larger than the data can hold.
  let bad = good.to_array()
  bad[4] = b'\xff'
  bad[5] = b'\xff'
  assert_false(p.process("g", Bytes::from_array(bad)[:], 0))
}

///|
test "symbol layers pack their points' labels with the layer's layout" {
  let style =
    #|{"sources": {"g": {"type": "geojson", "data": "x"}},
    #| "layers": [
    #|  {"id": "t", "type": "symbol", "source": "g",
    #|   "layout": {"text-field": "k={k}", "text-size": ["interpolate", ["linear"], ["zoom"], 0, 10, 10, 20],
    #|              "text-anchor": "top", "text-offset": [0, 1.5]},
    #|   "paint": {"text-color": ["match", ["get", "k"], 1, "#f00", "#00f"]}}
    #|]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  assert_true(p.process("g", geojson_tile()[:], 0))
  let b = p.out.to_bytes()[:]
  let entry = (k : Int32, w : Int32) => {
    u32_at(b, 4 + (k * @worker.LAYER_ENTRY_WORDS + w) * 4)
  }
  // The two points split into two groups by their color input; the square has
  // no label.
  assert_eq(p.out.layer_count(), 2)
  assert_eq((entry(0, 1), entry(0, 5)), (@worker.KIND_SYMBOL, 0))
  assert_eq(props_of(b, 0), ["k=1"])
  let r = @core.ByteReader::new(b[entry(0, 2):entry(0, 2) + entry(0, 3)])
  assert_eq((r.u8(), r.u8(), r.u8(), r.u8()), (3, 0, 0, 0))
  assert_eq([r.f64(), r.f64(), r.f64(), r.f64(), r.f64()], [
    0.0, 1.5, 10.0, 1.2, 2.0,
  ])
  assert_eq(r.u32(), 1)
  assert_eq(
    (r.u32(), r.i16(), r.i16(), r.f64(), r.f64(), r.u32()),
    (0, 2048, 2048, 10.0, 0.0, 2),
  )
  assert_eq((r.u8(), r.utf8()), (@core.PROP_STRING, "k="))
  assert_eq((r.u8(), r.f64()), (@core.PROP_NUMBER, 1.0))
  // The other point lacks k: its text is "k=" and a null part.
  let r2 = @core.ByteReader::new(b[entry(1, 2):entry(1, 2) + entry(1, 3)])
  for _ in 0..<44 {
    r2.u8() |> ignore
  }
  assert_eq(r2.u32(), 1)
  r2.u32() |> ignore
  r2.i16() |> ignore
  r2.i16() |> ignore
  r2.f64() |> ignore
  r2.f64() |> ignore
  assert_eq(r2.u32(), 2)
  r2.u8() |> ignore
  assert_eq(r2.utf8(), "k=")
  assert_eq(r2.u8(), @core.PROP_NULL)
}

///|
test "labels whose text has no value are left out" {
  let style =
    #|{"sources": {"g": {"type": "geojson", "data": "x"}},
    #| "layers": [{"id": "t", "type": "symbol", "source": "g", "layout": {"text-field": "{k}"}},
    #|            {"id": "u", "type": "symbol", "source": "g"}]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  assert_true(p.process("g", geojson_tile()[:], 0))
  let b = p.out.to_bytes()[:]
  assert_eq(p.out.layer_count(), 1)
  let at = u32_at(b, 4 + 2 * 4)
  assert_eq(u32_at(b, at + 44), 1)
}

///|
test "vertical writing and sort keys reach the labels" {
  let style =
    #|{"sources": {"g": {"type": "geojson", "data": "x"}},
    #| "layers": [{"id": "t", "type": "symbol", "source": "g", "filter": ["has", "k"],
    #|   "layout": {"text-field": "{k}", "text-writing-mode": ["vertical"], "symbol-sort-key": ["get", "k"]}}]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  assert_true(p.process("g", geojson_tile()[:], 0))
  let b = p.out.to_bytes()[:]
  let at = u32_at(b, 4 + 2 * 4)
  let r = @core.ByteReader::new(b[at:])
  assert_eq((r.u8(), r.u8(), r.u8(), r.u8()), (0, 0, 0, 1))
  for _ in 0..<5 {
    r.f64() |> ignore
  }
  assert_eq(r.u32(), 1)
  assert_eq(
    (r.u32(), r.i16(), r.i16(), r.f64(), r.f64()),
    (0, 2048, 2048, 16.0, 1.0),
  )
}

///|
test "dem_tile reads a raster-dem source's tiles and refuses others" {
  let style =
    #|{"sources": {"v": {"type": "vector", "tiles": ["t"]},
    #|             "d": {"type": "raster-dem", "tiles": ["t"], "encoding": "gsi", "tileSize": 256}},
    #| "layers": [{"id": "h", "type": "hillshade", "source": "d"}]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  let d = p.style.sources.search_by(s => s.id == "d").unwrap()
  let v = p.style.sources.search_by(s => s.id == "v").unwrap()
  // A flat 2 x 2 tile, 10 m everywhere in GSI's encoding.
  let rgba = Bytes::makei(16, i => {
    match i % 4 {
      1 => b'\x03'
      2 => b'\xe8'
      3 => b'\xff'
      _ => b'\x00'
    }
  })
  let out = p.dem_tile(d, rgba[:], 2, 14).unwrap()
  // 8 slope bytes, 8 runs of 2 border elevations, then 4 f32 elevations.
  assert_eq(out.length(), 8 + 16 * 8 + 4 * 4)
  assert_eq(
    out[8 + 16 * 8:].to_owned(),
    b"\x00\x00\x20\x41\x00\x00\x20\x41\x00\x00\x20\x41\x00\x00\x20\x41",
  )
  assert_eq(out[:8].to_owned().to_array(), Array::make(8, b'\x80'))
  let r = @core.ByteReader::new(out[8:])
  assert_eq((r.f64(), r.f64()), (10.0, 10.0))
  assert_eq(p.dem_tile(v, rgba[:], 2, 14), None)
  assert_eq(p.error(), "no DEM source \{v}")
  assert_eq(p.dem_tile(d, rgba[:4], 2, 14), None)
  assert_eq(p.error(), "DEM tile is not 2 x 2 RGBA")
}

///|
test "fill-extrusion layers pack walls, roofs and per-feature heights" {
  let style =
    #|{"sources": {"a": {"type": "vector", "tiles": ["t"]}},
    #| "layers": [
    #|  {"id": "flat", "type": "fill", "source": "a", "source-layer": "poly"},
    #|  {"id": "box", "type": "fill-extrusion", "source": "a", "source-layer": "poly",
    #|   "paint": {"fill-extrusion-height": ["interpolate", ["linear"], ["zoom"], 14, 10, 15, 25.25],
    #|    "fill-extrusion-base": -3}}]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  assert_true(p.process("a", sample_tile()[:], 14))
  let b = p.out.to_bytes()[:]
  let entry = (k : Int32, w : Int32) => {
    u32_at(b, 4 + (k * @worker.LAYER_ENTRY_WORDS + w) * 4)
  }
  // Its own entry, not an alias of the fill with the same geometry.
  assert_eq(p.out.layer_count(), 2)
  assert_eq((entry(1, 0), entry(1, 1)), (1, @worker.KIND_EXTRUSION))
  // A triangle: 3 walls and a 1-triangle roof of 3 vertices.
  let n = entry(1, 3) / @worker.EXTRUSION_VERTEX_BYTES
  assert_eq((n, entry(1, 5)), (3 * 4 + 4, 3 * 6 + 3))
  let v = entry(1, 2)
  let u16 = (at : Int32) => b[at].to_int() | (b[at + 1].to_int() << 8)
  // Centroid of (0, 0), (100, 0), (100, 100) (the commands are deltas); base
  // clamped to 0; height 10 m at z14 and 25.3 m (decimeters) at z15.
  assert_eq((i16_at(b, v + 12), i16_at(b, v + 14)), (66, 33))
  assert_eq(
    (u16(v + 16), u16(v + 18), u16(v + 20), u16(v + 22)),
    (0, 0, 100, 253),
  )
}
