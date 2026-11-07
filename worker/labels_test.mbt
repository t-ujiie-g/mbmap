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
  assert_eq(
    (entry(0, @worker.ENTRY_KIND), entry(0, @worker.ENTRY_INDEX_COUNT)),
    (@core.KIND_SYMBOL, 0),
  )
  assert_eq(props_of(b, 0), ["k=1"])
  let r = @core.ByteReader::new(
    b[entry(0, @worker.ENTRY_VERTEX_OFFSET):entry(
      0,
      @worker.ENTRY_VERTEX_OFFSET,
    ) +
    entry(0, @worker.ENTRY_VERTEX_BYTES)],
  )
  assert_eq((r.u8(), r.u8(), r.u8(), r.u8()), (3, 0, 0, 0))
  assert_eq([r.f64(), r.f64(), r.f64(), r.f64(), r.f64()], [
    0.0, 1.5, 10.0, 1.2, 2.0,
  ])
  // `text-justify` center, no variable anchors; on points, kept upright, 250
  // px apart, 45° at most along lines.
  assert_eq((r.u8(), r.u8()), (2, 0))
  assert_eq((r.u8(), r.u8(), r.f64(), r.f64()), (0, 1, 250.0, 45.0))
  // No icon, no fonts but the map's.
  assert_eq((r.u8(), r.u8()), (0, 0))
  assert_eq(r.u32(), 1)
  assert_eq(
    (r.u32(), r.i16(), r.i16(), r.f64(), r.f64()),
    (0, 4096, 4096, 10.0, 0.0),
  )
  // The map's font, no transform, letter spacing or rotation.
  assert_eq((r.u8(), r.u8(), r.f64(), r.f64(), r.u32()), (0, 0, 0.0, 0.0, 2))
  assert_eq((r.u8(), r.utf8()), (@core.PROP_STRING, "k="))
  assert_eq((r.u8(), r.f64()), (@core.PROP_NUMBER, 1.0))
  // The other point lacks k: its text is "k=" and a null part.
  let r2 = @core.ByteReader::new(
    b[entry(1, @worker.ENTRY_VERTEX_OFFSET):entry(
      1,
      @worker.ENTRY_VERTEX_OFFSET,
    ) +
    entry(1, @worker.ENTRY_VERTEX_BYTES)],
  )
  for _ in 0..<66 {
    r2.u8() |> ignore
  }
  assert_eq(r2.u32(), 1)
  for _ in 0..<42 {
    r2.u8() |> ignore
  }
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
  assert_eq(u32_at(b, at + 66), 1)
}

///|
test "formatted text-fields pack their sections with scale and vertical align" {
  let style =
    #|{"sources": {"g": {"type": "geojson", "data": "x"}},
    #| "layers": [{"id": "t", "type": "symbol", "source": "g",
    #|   "layout": {"text-field": ["format", ["number-format", ["get", "k"], {}], {"font-scale": 1.5},
    #|                             "!", {"vertical-align": "top", "text-font": ["literal", ["A"]]}]}}]}
  let intl = {
    ..@style.Intl::fallback(),
    number_format: (x, _, _, _, _, _) => Some("n\{x.to_int()}"),
  }
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:], intl~)
  assert_true(p.process("g", geojson_tile()[:], 0))
  let b = p.out.to_bytes()[:]
  let at = u32_at(b, 4 + 2 * 4)
  let r = @core.ByteReader::new(b[at + 65:])
  // The second section's font, as its face's style, weight and family.
  assert_eq((r.u8(), r.utf8()), (1, "normal\n\nA"))
  // The point without k fails its number-format, so has no label.
  assert_eq(r.u32(), 1)
  assert_eq(
    (r.u32(), r.i16(), r.i16(), r.f64(), r.f64()),
    (0, 4096, 4096, 16.0, 0.0),
  )
  r.u8() |> ignore
  r.u8() |> ignore
  r.f64() |> ignore
  r.f64() |> ignore
  assert_eq((r.u32(), r.u8(), r.u32()), (1, 6, 2))
  // Sections: text, scale, vertical align, font (255 the label's) and color.
  assert_eq((r.utf8(), r.f64(), r.u8(), r.u8(), r.u8()), ("n1", 1.5, 0, 255, 0))
  assert_eq(r.utf8(), "!")
  assert_true(r.f64().is_nan())
  assert_eq((r.u8(), r.u8(), r.u8()), (2, 1, 0))
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
  assert_eq((r.u8(), r.u8()), (0, 0))
  // The square of the tile is its one line feature, a ring of 5 points.
  assert_eq(r.u32(), 1)
  assert_eq((r.u32(), r.i16(), r.i16(), r.f64(), r.f64()), (2, 0, 0, 16.0, 0.0))
  for _ in 0..<18 {
    r.u8() |> ignore
  }
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
  // No icon, no fonts.
  assert_eq((r.u8(), r.u8()), (0, 0))
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
  // No icon, no fonts.
  assert_eq((r.u8(), r.u8()), (0, 0))
  assert_eq(r.u32(), 1)
  assert_eq(
    (r.u32(), r.i16(), r.i16(), r.f64(), r.f64()),
    (0, 4096, 4096, 16.0, 1.0),
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
  assert_eq((r.u8(), r.u32()), (0, 1))
  // No text, then the image's parts, its size at zoom 1 and its rotation.
  assert_eq(
    (r.u32(), r.i16(), r.i16(), r.f64(), r.f64()),
    (0, 4096, 4096, 16.0, 0.0),
  )
  for _ in 0..<18 {
    r.u8() |> ignore
  }
  assert_eq(r.u32(), 0)
  assert_eq((r.u32(), r.u8(), r.utf8()), (2, @core.PROP_STRING, "shop-"))
  assert_eq((r.u8(), r.f64()), (@core.PROP_NUMBER, 1.0))
  assert_eq((r.f64(), r.f64()), (2.0, 30.0))
}

///|
test "labels carry their font, case, letter spacing and rotation, and sections their font and color" {
  let style =
    #|{"sources": {"g": {"type": "geojson", "data": "x"}},
    #| "layers": [{"id": "t", "type": "symbol", "source": "g", "filter": ["has", "k"],
    #|   "layout": {"text-field": ["format", "a", {"text-color": "#ff0000", "text-font": ["literal", ["B Italic"]]}],
    #|              "text-font": ["case", ["==", ["get", "k"], 1], ["literal", ["Noto Sans Bold", "X"]], ["literal", ["Y"]]],
    #|              "text-transform": "uppercase", "text-letter-spacing": 0.1, "text-rotate": ["*", ["get", "k"], 30]}}]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  assert_true(p.process("g", geojson_tile()[:], 0))
  let b = p.out.to_bytes()[:]
  let r = @core.ByteReader::new(b[u32_at(b, 4 + 2 * 4) + 64:])
  assert_eq(r.u8(), 0)
  assert_eq(
    (r.u8(), r.utf8(), r.utf8()),
    (2, "normal\n700\nNoto Sans Bold,X", "italic\n\nB Italic"),
  )
  assert_eq(r.u32(), 1)
  for _ in 0..<24 {
    r.u8() |> ignore
  }
  assert_eq((r.u8(), r.u8(), r.f64(), r.f64()), (1, 1, 0.1, 30.0))
  assert_eq((r.u32(), r.u8(), r.u32()), (1, 6, 1))
  assert_eq((r.utf8(), r.f64().is_nan(), r.u8(), r.u8()), ("a", true, 0, 2))
  assert_eq(Array::makei(5, _ => r.u8()), [1, 255, 0, 0, 255])
}
