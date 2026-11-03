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
  // `text-justify` center, no variable anchors; on points, kept upright, 250
  // px apart, 45° at most along lines.
  assert_eq((r.u8(), r.u8()), (2, 0))
  assert_eq((r.u8(), r.u8(), r.f64(), r.f64()), (0, 1, 250.0, 45.0))
  // No icon.
  assert_eq(r.u8(), 0)
  assert_eq(r.u32(), 1)
  assert_eq(
    (r.u32(), r.i16(), r.i16(), r.f64(), r.f64(), r.u32()),
    (0, 2048, 2048, 10.0, 0.0, 2),
  )
  assert_eq((r.u8(), r.utf8()), (@core.PROP_STRING, "k="))
  assert_eq((r.u8(), r.f64()), (@core.PROP_NUMBER, 1.0))
  // The other point lacks k: its text is "k=" and a null part.
  let r2 = @core.ByteReader::new(b[entry(1, 2):entry(1, 2) + entry(1, 3)])
  for _ in 0..<65 {
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
  assert_eq(u32_at(b, at + 65), 1)
}

///|
test "labels along lines carry their features' lines" {
  let style =
    #|{"sources": {"g": {"type": "geojson", "data": "x"}},
    #| "layers": [{"id": "t", "type": "symbol", "source": "g",
    #|   "layout": {"text-field": "a", "symbol-placement": "line-center", "symbol-spacing": 100,
    #|              "text-max-angle": 30, "text-keep-upright": false}}]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  assert_true(p.process("g", geojson_tile()[:], 0))
  let b = p.out.to_bytes()[:]
  let r = @core.ByteReader::new(b[u32_at(b, 4 + 2 * 4):])
  for _ in 0..<46 {
    r.u8() |> ignore
  }
  assert_eq((r.u8(), r.u8(), r.f64(), r.f64()), (2, 0, 100.0, 30.0))
  assert_eq(r.u8(), 0)
  // The square of the tile is its one line feature, a ring of 5 points.
  assert_eq(r.u32(), 1)
  assert_eq((r.u32(), r.i16(), r.i16(), r.f64(), r.f64()), (2, 0, 0, 16.0, 0.0))
  assert_eq((r.u32(), r.u8(), r.utf8()), (1, @core.PROP_STRING, "a"))
  assert_eq((r.u32(), r.u32()), (1, 5))
}

///|
test "variable anchors follow the layout, each with its offset in ems" {
  let style =
    #|{"sources": {"g": {"type": "geojson", "data": "x"}},
    #| "layers": [{"id": "t", "type": "symbol", "source": "g", "filter": ["has", "k"],
    #|   "layout": {"text-field": "{k}", "text-justify": "auto",
    #|              "text-variable-anchor": ["left", "top"], "text-radial-offset": 2}}]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  assert_true(p.process("g", geojson_tile()[:], 0))
  let b = p.out.to_bytes()[:]
  let r = @core.ByteReader::new(b[u32_at(b, 4 + 2 * 4):])
  assert_eq((r.u8(), r.u8(), r.u8(), r.u8()), (0, 0, 0, 0))
  for _ in 0..<5 {
    r.f64() |> ignore
  }
  assert_eq((r.u8(), r.u8()), (0, 2))
  assert_eq((r.u8(), r.f64(), r.f64()), (1, 2.0, 0.0))
  assert_eq((r.u8(), r.f64(), r.f64()), (3, 0.0, 2.0 - 7.0 / 24.0))
  assert_eq((r.u8(), r.u8(), r.f64(), r.f64()), (0, 1, 250.0, 45.0))
  // No icon.
  assert_eq(r.u8(), 0)
  assert_eq(r.u32(), 1)
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
  assert_eq((r.u8(), r.u8()), (2, 0))
  assert_eq((r.u8(), r.u8(), r.f64(), r.f64()), (0, 1, 250.0, 45.0))
  // No icon.
  assert_eq(r.u8(), 0)
  assert_eq(r.u32(), 1)
  assert_eq(
    (r.u32(), r.i16(), r.i16(), r.f64(), r.f64()),
    (0, 2048, 2048, 16.0, 1.0),
  )
}

///|
test "icons pack their layout, then each label's image parts, size one zoom deeper and rotation" {
  let style =
    #|{"sources": {"g": {"type": "geojson", "data": "x"}},
    #| "layers": [{"id": "i", "type": "symbol", "source": "g", "filter": ["has", "k"],
    #|   "layout": {"icon-image": "shop-{k}", "icon-size": ["interpolate", ["linear"], ["zoom"], 0, 1, 2, 3],
    #|              "icon-rotate": 30, "icon-anchor": "bottom", "icon-offset": [1, 2], "icon-optional": true,
    #|              "icon-text-fit": "width", "icon-padding": [1, 2, 3, 4]}}]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  assert_true(p.process("g", geojson_tile()[:], 0))
  let b = p.out.to_bytes()[:]
  let r = @core.ByteReader::new(b[u32_at(b, 4 + 2 * 4):])
  for _ in 0..<64 {
    r.u8() |> ignore
  }
  // Anchor bottom; allow overlap, ignore placement, optional, text optional,
  // rotate and pitch with the map, keep upright; fit width.
  assert_eq(r.u8(), 1)
  assert_eq(r.u8(), 4)
  assert_eq(Array::makei(7, _ => r.u8()), [0, 0, 1, 0, 0, 0, 0])
  assert_eq(r.u8(), 1)
  assert_eq(Array::makei(10, _ => r.f64()), [
    1.0, 2.0, 1.0, 2.0, 3.0, 4.0, 0.0, 0.0, 0.0, 0.0,
  ])
  assert_eq(r.u32(), 1)
  // No text, then the image's parts, its size at zoom 1 and its rotation.
  assert_eq(
    (r.u32(), r.i16(), r.i16(), r.f64(), r.f64()),
    (0, 2048, 2048, 16.0, 0.0),
  )
  assert_eq(r.u32(), 0)
  assert_eq((r.u32(), r.u8(), r.utf8()), (2, @core.PROP_STRING, "shop-"))
  assert_eq((r.u8(), r.f64()), (@core.PROP_NUMBER, 1.0))
  assert_eq((r.f64(), r.f64()), (2.0, 30.0))
}
