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
