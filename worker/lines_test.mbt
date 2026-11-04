///|
test "dashed lines pack their distances and share buffers only with dashed lines" {
  let style =
    #|{"sources": {"a": {"type": "vector", "tiles": ["t"]}},
    #| "layers": [
    #|  {"id": "road", "type": "line", "source": "a", "source-layer": "line"},
    #|  {"id": "dash", "type": "line", "source": "a", "source-layer": "line",
    #|   "paint": {"line-dasharray": [2, 1]}},
    #|  {"id": "dots", "type": "line", "source": "a", "source-layer": "line",
    #|   "paint": {"line-dasharray": [1, 1]}}]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  assert_true(p.process("a", sample_tile()[:], 14))
  let b = p.out.to_bytes()[:]
  let entry = (k : Int32, w : Int32) => {
    u32_at(b, 4 + (k * @worker.LAYER_ENTRY_WORDS + w) * 4)
  }
  assert_eq(p.out.layer_count(), 3)
  // The solid road has none; the dashed lines share one buffer and its distances.
  assert_eq(entry(0, @worker.ENTRY_DISTANCES_COUNT), 0)
  assert_true(
    entry(1, @worker.ENTRY_VERTEX_OFFSET) !=
    entry(0, @worker.ENTRY_VERTEX_OFFSET),
  )
  assert_eq(
    entry(2, @worker.ENTRY_VERTEX_OFFSET),
    entry(1, @worker.ENTRY_VERTEX_OFFSET),
  )
  assert_eq(
    (
      entry(2, @worker.ENTRY_DISTANCES_OFFSET),
      entry(2, @worker.ENTRY_DISTANCES_COUNT),
    ),
    (
      entry(1, @worker.ENTRY_DISTANCES_OFFSET),
      entry(1, @worker.ENTRY_DISTANCES_COUNT),
    ),
  )
  // Four vertices along a line of 50 units: 0 at the start, 50 at the end.
  assert_eq(entry(1, @worker.ENTRY_DISTANCES_COUNT), 4)
  let d = entry(1, @worker.ENTRY_DISTANCES_OFFSET)
  let u16 = (at : Int32) => b[at].to_int() | (b[at + 1].to_int() << 8)
  assert_eq((u16(d), u16(d + 2), u16(d + 4), u16(d + 6)), (0, 0, 50, 50))
}

///|
test "lines dashed by feature pack their patterns at the tile's zoom and either side" {
  let style =
    #|{"sources": {"a": {"type": "vector", "tiles": ["t"]}},
    #| "layers": [
    #|  {"id": "dash", "type": "line", "source": "a", "source-layer": "line",
    #|   "paint": {"line-dasharray": ["step", ["zoom"], ["literal", [1, 1]], 14, ["case", ["has", "k"], ["literal", [4, 4]], ["literal", [-1]]], 15, ["literal", [3]]]}},
    #|  {"id": "plain", "type": "line", "source": "a", "source-layer": "line",
    #|   "paint": {"line-dasharray": [2, 1]}}]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  assert_true(p.process("a", sample_tile()[:], 14))
  let b = p.out.to_bytes()[:]
  let entry = (k : Int32, w : Int32) => {
    u32_at(b, 4 + (k * @worker.LAYER_ENTRY_WORDS + w) * 4)
  }
  // Each keeps its own buffers; only the first has patterns.
  assert_eq(p.out.layer_count(), 2)
  assert_true(
    entry(0, @worker.ENTRY_VERTEX_OFFSET) !=
    entry(1, @worker.ENTRY_VERTEX_OFFSET),
  )
  assert_eq(entry(1, @worker.ENTRY_DASHES_OFFSET), 0)
  let at = entry(0, @worker.ENTRY_DASHES_OFFSET)
  assert_eq((at % 8, entry(0, @worker.ENTRY_DASHES_COUNT)), (0, 2))
  let f64 = (o : Int32) => {
    let lo = u32_at(b, o).to_uint64()
    let hi = u32_at(b, o + 4).to_uint64()
    (lo | (hi << 32)).reinterpret_as_double()
  }
  // [1, 1] at z13 and [3] at z15; [-1] is no pattern.
  assert_eq([f64(at), f64(at + 8), f64(at + 16)], [2.0, 1.0, 1.0])
  assert_eq([f64(at + 24), f64(at + 32)], [1.0, 3.0])
  let marks = at + 40
  let u16 = (o : Int32) => b[o].to_int() | (b[o + 1].to_int() << 8)
  for v in 0..<4 {
    let o = marks + v * 8
    assert_eq((u16(o), u16(o + 2), u16(o + 4), u16(o + 6)), (0, 0xffff, 1, 0))
  }
}

///|
test "gradient lines pack their progress, rows and line metrics" {
  let b = @geom.TableBuilder::new()
  b.point(-10.0, 10.0)
  b.point(10.0, 10.0)
  b.end_ring()
  b.end_part()
  b.end_feature(LineString)
  let table = b.finish()
  let tiler = @tiler.Tiler::new(table, options={
    ..@tiler.TilerOptions::default(),
    line_metrics: true,
  })
  let tile = @tiler.encode_tile(tiler.tile(1, 1, 0).unwrap(), table)
  let style =
    #|{"sources": {"g": {"type": "geojson", "data": "x", "lineMetrics": true}},
    #| "layers": [
    #|  {"id": "plain", "type": "line", "source": "g"},
    #|  {"id": "ramp", "type": "line", "source": "g",
    #|   "paint": {"line-gradient": ["interpolate", ["linear"], ["line-progress"], 0, "#000", 1, "#fff"]}}]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  assert_true(p.process("g", tile[:], 1))
  let bs = p.out.to_bytes()[:]
  let entry = (k : Int32, w : Int32) => {
    u32_at(bs, 4 + (k * @worker.LAYER_ENTRY_WORDS + w) * 4)
  }
  // Its own buffers, not the plain line's; one row.
  assert_eq(p.out.layer_count(), 2)
  assert_eq(
    (
      entry(0, @worker.ENTRY_PROGRESS_OFFSET),
      entry(0, @worker.ENTRY_PROGRESS_ROWS),
    ),
    (0, 0),
  )
  assert_true(
    entry(1, @worker.ENTRY_VERTEX_OFFSET) !=
    entry(0, @worker.ENTRY_VERTEX_OFFSET),
  )
  assert_eq(entry(1, @worker.ENTRY_PROGRESS_ROWS), 1)
  let n = entry(1, @worker.ENTRY_VERTEX_BYTES) / @worker.LINE_VERTEX_BYTES
  let at = entry(1, @worker.ENTRY_PROGRESS_OFFSET)
  let f32 = (o : Int32) => {
    Float::reinterpret_from_int(u32_at(bs, o)).to_double()
  }
  let f64 = (o : Int32) => {
    let bits = (u32_at(bs, o).to_int64() & 0xffffffffL) |
      (u32_at(bs, o + 4).to_int64() << 32)
    bits.reinterpret_as_double()
  }
  assert_eq((f32(at), f32(at + 4)), (0.0, 0.0))
  assert_eq((f32(at + (n - 1) * 8), f32(at + (n - 1) * 8 + 4)), (1.0, 0.0))
  // The slice right of x 0.5 minus the buffer, to the line's end.
  let start = f64(at + n * 8)
  assert_true(start > 0.3 && start < 0.5)
  assert_eq(f64(at + n * 8 + 8), 1.0)
  assert_true(f64(at + n * 8 + 16) > 0.0)
}

///|
test "offset lines pack their offset normals and share buffers only with offset lines" {
  let style =
    #|{"sources": {"a": {"type": "vector", "tiles": ["t"]}},
    #| "layers": [
    #|  {"id": "road", "type": "line", "source": "a", "source-layer": "line",
    #|   "paint": {"line-gap-width": 3}},
    #|  {"id": "left", "type": "line", "source": "a", "source-layer": "line",
    #|   "paint": {"line-offset": -2}},
    #|  {"id": "right", "type": "line", "source": "a", "source-layer": "line",
    #|   "paint": {"line-offset": ["get", "k"]}}]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  assert_true(p.process("a", sample_tile()[:], 14))
  let b = p.out.to_bytes()[:]
  let entry = (k : Int32, w : Int32) => {
    u32_at(b, 4 + (k * @worker.LAYER_ENTRY_WORDS + w) * 4)
  }
  assert_eq(p.out.layer_count(), 3)
  assert_eq(entry(0, @worker.ENTRY_OFFSETS_COUNT), 0)
  assert_true(
    entry(1, @worker.ENTRY_VERTEX_OFFSET) !=
    entry(0, @worker.ENTRY_VERTEX_OFFSET),
  )
  assert_eq(
    entry(2, @worker.ENTRY_VERTEX_OFFSET),
    entry(1, @worker.ENTRY_VERTEX_OFFSET),
  )
  assert_eq(
    (
      entry(2, @worker.ENTRY_OFFSETS_OFFSET),
      entry(2, @worker.ENTRY_OFFSETS_COUNT),
    ),
    (
      entry(1, @worker.ENTRY_OFFSETS_OFFSET),
      entry(1, @worker.ENTRY_OFFSETS_COUNT),
    ),
  )
  // Four vertices of a straight line along +x: every normal is (0, 63).
  assert_eq(entry(1, @worker.ENTRY_OFFSETS_COUNT), 4)
  let o = entry(1, @worker.ENTRY_OFFSETS_OFFSET)
  for i in 0..<4 {
    assert_eq((b[o + i * 2].to_int(), b[o + i * 2 + 1].to_int()), (0, 63))
  }
  // The data-driven offset goes per vertex, with the width and gap as constants.
  assert_true(entry(2, @worker.ENTRY_PAINT_BYTES) > 0)
}
