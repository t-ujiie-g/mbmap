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
    (
      entry(0, @worker.ENTRY_KIND),
      entry(1, @worker.ENTRY_KIND),
      entry(2, @worker.ENTRY_KIND),
    ),
    (@core.KIND_CIRCLE, @core.KIND_CIRCLE, @core.KIND_CIRCLE),
  )
  assert_eq(entry(2, @worker.ENTRY_INDEX_COUNT), 12)
  // Two points inside the tile: 8 vertices, 12 indices; "halo" reuses them.
  assert_eq(
    (entry(0, @worker.ENTRY_VERTEX_BYTES), entry(0, @worker.ENTRY_INDEX_COUNT)),
    (8 * @worker.LINE_VERTEX_BYTES, 12),
  )
  assert_eq(
    (entry(1, @worker.ENTRY_LAYER), entry(1, @worker.ENTRY_VERTEX_OFFSET)),
    (1, entry(0, @worker.ENTRY_VERTEX_OFFSET)),
  )
  let v = entry(0, @worker.ENTRY_VERTEX_OFFSET)
  assert_eq((i16_at(b, v), i16_at(b, v + 2)), (10, 20))
  assert_eq((b[v + 4].to_int(), b[v + 5].to_int()), (256 - 63, 256 - 63))
  assert_eq((i16_at(b, v + 32), i16_at(b, v + 34)), (20, 30))
}

///|
test "heatmap layers pack circle quads with their weights per vertex" {
  let style =
    #|{"sources": {"a": {"type": "vector", "tiles": ["t"]}},
    #| "layers": [
    #|  {"id": "heat", "type": "heatmap", "source": "a", "source-layer": "pts",
    #|   "paint": {"heatmap-weight": ["coalesce", ["get", "w"], 3]}},
    #|  {"id": "dots", "type": "circle", "source": "a", "source-layer": "pts"}
    #|]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  let tile = tile_of([tile_with("pts", 1, [cmd(1, 2), 10, 20, 5000, 0])])
  assert_true(p.process("a", tile[:], 14))
  let b = p.out.to_bytes()[:]
  let entry = (k : Int32, w : Int32) => {
    u32_at(b, 4 + (k * @worker.LAYER_ENTRY_WORDS + w) * 4)
  }
  assert_eq(p.out.layer_count(), 2)
  // Circles of their own: a heatmap's buffers are not shared with circles.
  assert_eq(
    (entry(0, @worker.ENTRY_KIND), entry(1, @worker.ENTRY_KIND)),
    (@core.KIND_CIRCLE, @core.KIND_CIRCLE),
  )
  assert_true(
    entry(1, @worker.ENTRY_VERTEX_OFFSET) !=
    entry(0, @worker.ENTRY_VERTEX_OFFSET),
  )
  // One point inside the tile, its weight (the default 3) on each of its 4 vertices.
  assert_eq(
    (entry(0, @worker.ENTRY_VERTEX_BYTES), entry(0, @worker.ENTRY_INDEX_COUNT)),
    (4 * @worker.LINE_VERTEX_BYTES, 6),
  )
  assert_eq(entry(0, @worker.ENTRY_PAINT_BYTES), 4 * 4)
  let weight = Float::reinterpret_from_int(
    u32_at(b, entry(0, @worker.ENTRY_PAINT_OFFSET) + 12),
  )
  assert_eq(weight.to_double(), 3.0)
}

///|
test "heatmaps reading feature state go by group, with their features' ranges" {
  let style =
    #|{"sources": {"a": {"type": "vector", "tiles": ["t"]}},
    #| "layers": [
    #|  {"id": "heat", "type": "heatmap", "source": "a", "source-layer": "pts",
    #|   "paint": {"heatmap-weight": ["coalesce", ["feature-state", "w"], ["get", "w"], 3]}}]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  let tile = tile_of([tile_with("pts", 1, [cmd(1, 2), 10, 20, 30, 40])])
  assert_true(p.process("a", tile[:], 14))
  let b = p.out.to_bytes()[:]
  let entry = (k : Int32, w : Int32) => {
    u32_at(b, 4 + (k * @worker.LAYER_ENTRY_WORDS + w) * 4)
  }
  // No paint per vertex: the group's properties (none read here) carry it.
  assert_eq(p.out.layer_count(), 1)
  assert_eq(
    (entry(0, @worker.ENTRY_KIND), entry(0, @worker.ENTRY_PAINT_BYTES)),
    (@core.KIND_CIRCLE, 0),
  )
  assert_eq(u32_at(b, entry(0, @worker.ENTRY_PROPS_OFFSET)), 0)
  // The feature's range in the entry, for its state.
  assert_eq(u32_at(p.feature_ranges()[:], 0), 1)
}
