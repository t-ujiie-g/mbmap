///|
let compiled_style : String =
  #|{"version": 8,
  #| "sources": {
  #|   "v": {"type": "vector", "tiles": ["https://x/{z}/{x}/{y}"], "minzoom": 2, "maxzoom": 12,
  #|         "promoteId": {"roads": "rid"}, "bounds": [130, 30, 140, 40]},
  #|   "g": {"type": "geojson", "data": {"type": "FeatureCollection", "features": []},
  #|         "buffer": 64, "tolerance": 0.5, "promoteId": "pid", "lineMetrics": true},
  #|   "d": {"type": "raster-dem", "tiles": ["https://d/{z}/{x}/{y}"], "tileSize": 256,
  #|         "encoding": "custom", "redFactor": 2, "greenFactor": 3, "blueFactor": 4, "baseShift": -5}},
  #| "layers": [
  #|   {"id": "bg", "type": "background", "paint": {"background-color": "#123"}},
  #|   {"id": "f", "type": "fill", "source": "v", "source-layer": "water", "minzoom": 3, "maxzoom": 15.5,
  #|    "filter": ["all", ["==", ["get", "k"], "a"], ["!", ["has", "x"]], ["in", ["get", "n"], ["literal", [1, 2]]]],
  #|    "paint": {"fill-color": ["match", ["get", "c"], ["a", "b"], "red", "c", "rgba(0, 0, 255, 0.5)", "white"],
  #|              "fill-opacity": ["interpolate", ["cubic-bezier", 0.1, 0.2, 0.3, 0.4], ["zoom"], 3, 0.2, 9, 1],
  #|              "fill-outline-color": "blue", "fill-antialias": false}},
  #|   {"id": "l", "type": "line", "source": "v", "source-layer": "roads",
  #|    "layout": {"line-join": "round", "line-cap": "square", "line-miter-limit": 3, "line-round-limit": 1.5},
  #|    "paint": {"line-color": ["interpolate-hcl", ["linear"], ["zoom"], 5, "red", 10, "blue"],
  #|              "line-width": ["step", ["zoom"], 1, 8, ["coalesce", ["get", "w"], 2], 12, ["case", ["==", ["feature-state", "hover"], true], 4, 3]],
  #|              "line-dasharray": [2, 1], "line-gap-width": 2, "line-offset": ["get", "o"],
  #|              "line-blur": 0.5, "line-translate": [1, -2], "line-translate-anchor": "viewport"}},
  #|   {"id": "grad", "type": "line", "source": "g",
  #|    "paint": {"line-gradient": ["interpolate-lab", ["linear"], ["line-progress"], 0, "red", 1, "blue"]}},
  #|   {"id": "pat", "type": "fill", "source": "v", "source-layer": "water",
  #|    "paint": {"fill-pattern": ["concat", "p-", ["to-string", ["get", "k"]]]}},
  #|   {"id": "c", "type": "circle", "source": "g",
  #|    "paint": {"circle-radius": ["+", 1, ["*", 2, ["sqrt", ["abs", ["number", ["get", "r"], 4]]]]],
  #|              "circle-color": ["to-color", ["get", "col"], "black"],
  #|              "circle-stroke-width": ["max", 1, ["round", ["/", ["zoom"], 3]]],
  #|              "circle-stroke-color": ["rgba", 10, 20, 30, 0.5], "circle-stroke-opacity": 0.25,
  #|              "circle-blur": 0.3, "circle-pitch-scale": "viewport", "circle-pitch-alignment": "map"}},
  #|   {"id": "h", "type": "heatmap", "source": "g",
  #|    "paint": {"heatmap-weight": ["get", "w"], "heatmap-intensity": 2,
  #|              "heatmap-color": ["interpolate", ["exponential", 2], ["heatmap-density"], 0, "transparent", 1, "red"]}},
  #|   {"id": "x", "type": "fill-extrusion", "source": "v", "source-layer": "buildings",
  #|    "paint": {"fill-extrusion-height": ["get", "height"], "fill-extrusion-base": 2,
  #|              "fill-extrusion-vertical-gradient": false}},
  #|   {"id": "t", "type": "symbol", "source": "v", "source-layer": "roads",
  #|    "layout": {"text-field": ["concat", ["upcase", ["get", "name"]], " ", ["slice", ["get", "ref"], 1]],
  #|               "text-size": ["interpolate", ["linear"], ["zoom"], 0, 10, 10, 20],
  #|               "symbol-placement": "line", "symbol-spacing": 120, "text-max-angle": 30,
  #|               "text-keep-upright": false,
  #|               "text-justify": "right", "text-max-width": 7, "text-line-height": 1.5, "text-padding": 3,
  #|               "text-allow-overlap": true, "text-ignore-placement": true, "symbol-sort-key": ["get", "rank"]},
  #|    "paint": {"text-color": "#333", "text-halo-color": "white", "text-halo-width": 1.5}},
  #|   {"id": "i", "type": "symbol", "source": "g",
  #|    "layout": {"text-field": "{k}", "text-variable-anchor": ["top", "bottom-right"], "text-writing-mode": ["vertical"],
  #|               "icon-image": ["concat", "shop-", ["get", "k"]], "icon-size": 1.5, "icon-rotate": 45,
  #|               "icon-anchor": "bottom", "icon-offset": [2, 3], "icon-padding": [1, 2, 3, 4],
  #|               "icon-allow-overlap": true, "icon-optional": true, "icon-text-fit": "both",
  #|               "icon-text-fit-padding": [4, 3, 2, 1]},
  #|    "paint": {"icon-color": "red", "icon-opacity": 0.5, "icon-halo-width": 2}},
  #|   {"id": "hs", "type": "hillshade", "source": "d"}
  #| ]}

///|
fn round_trip(s : @style.Style) -> @style.Style {
  @style.Style::from_compiled(s.to_compiled()[:]) catch {
    e => abort(e.message())
  }
}

///|
test "a compiled style reads back as the layers and sources workers use" {
  let s = @style.Style::parse(compiled_style) catch { e => abort(e.message()) }
  let r = round_trip(s)
  assert_eq(r.to_compiled(), s.to_compiled())
  assert_eq(r.layers.length(), s.layers.length())
  for i, a in s.layers {
    let b = r.layers[i]
    assert_eq(b.id, a.id)
    assert_eq(b.kind, a.kind)
    assert_eq((b.source, b.source_layer), (a.source, a.source_layer))
    assert_eq((b.min_zoom, b.max_zoom), (a.min_zoom, a.max_zoom))
    assert_eq((b.filter, b.filter_id), (a.filter, a.filter_id))
    assert_eq(
      [
        b.color,
        b.opacity,
        b.width,
        b.radius,
        b.stroke_width,
        b.stroke_color,
        b.stroke_opacity,
        b.halo_color,
        b.halo_width,
      ],
      [
        a.color,
        a.opacity,
        a.width,
        a.radius,
        a.stroke_width,
        a.stroke_color,
        a.stroke_opacity,
        a.halo_color,
        a.halo_width,
      ],
    )
    assert_true(b.text == a.text)
    assert_true(b.extrusion == a.extrusion)
    assert_eq(
      b.icon_paint.map(p => p.exprs()),
      a.icon_paint.map(p => p.exprs()),
    )
    assert_eq(
      b.heatmap.map(h => [h.weight, h.intensity, h.color]),
      a.heatmap.map(h => [h.weight, h.intensity, h.color]),
    )
    assert_eq((b.join, b.cap), (a.join, a.cap))
    assert_eq((b.miter_limit, b.round_limit), (a.miter_limit, a.round_limit))
    assert_eq(b.antialias, a.antialias)
    assert_eq([b.outline_color, b.dasharray, b.gradient, b.pattern], [
      a.outline_color,
      a.dasharray,
      a.gradient,
      a.pattern,
    ])
    assert_eq([b.gap_width, b.offset, b.blur], [a.gap_width, a.offset, a.blur])
    assert_eq(
      (b.translate, b.translate_viewport),
      (a.translate, a.translate_viewport),
    )
    assert_eq(
      (b.scale_with_map, b.pitch_with_map),
      (a.scale_with_map, a.pitch_with_map),
    )
    assert_true(b.same_line_layout(a))
    assert_eq(b.reads_state(), a.reads_state())
    assert_eq(b.paints_by_group(), a.paints_by_group())
    assert_eq(b.vertex_paint().length(), a.vertex_paint().length())
  }
  let icon = r.layers[9].icon.unwrap()
  let want = s.layers[9].icon.unwrap()
  assert_eq(icon.image, want.image)
  assert_eq((icon.size, icon.rotate), (want.size, want.rotate))
  assert_eq(
    (icon.anchor, icon.offset, icon.padding),
    (want.anchor, want.offset, want.padding),
  )
  assert_eq(
    [
      icon.allow_overlap,
      icon.ignore_placement,
      icon.optional,
      icon.text_optional,
      icon.rotate_with_map,
      icon.pitch_with_map,
      icon.keep_upright,
    ],
    [
      want.allow_overlap,
      want.ignore_placement,
      want.optional,
      want.text_optional,
      want.rotate_with_map,
      want.pitch_with_map,
      want.keep_upright,
    ],
  )
  assert_eq(
    (icon.text_fit, icon.text_fit_padding),
    (want.text_fit, want.text_fit_padding),
  )
  assert_true(r.layers[10].hillshade is None)
  assert_eq(r.sources.length(), 3)
  for i, a in s.sources {
    let b = r.sources[i]
    assert_eq(
      (b.id, b.kind, b.encoding, b.promote_id),
      (a.id, a.kind, a.encoding, a.promote_id),
    )
    assert_eq(
      (b.min_zoom, b.max_zoom, b.tile_size),
      (a.min_zoom, a.max_zoom, a.tile_size),
    )
    assert_eq((b.buffer, b.tolerance), (a.buffer, a.tolerance))
    assert_eq((b.tiles, b.bounds), ([], None))
  }
}

///|
test "every expression and value kind survives write_expr and read_expr" {
  let exprs : Array[@style.Expr] = [
    Lit(Null),
    Lit(Bool(true)),
    Lit(Bool(false)),
    Lit(Num(-0.5)),
    Lit(Str("é")),
    Lit(Color({ r: 0.1, g: 0.2, b: 0.3, a: 0.4, })),
    Lit(List([Num(1.0), List([Str("a")])])),
    Lit(Failed),
    Get("k"),
    Has("k"),
    Id,
    GeometryType,
    Zoom,
    LineProgress,
    HeatmapDensity,
    Elevation,
    Not(Id),
    All([Id, Zoom]),
    Any([]),
    Compare(Ge, Zoom, Lit(Num(3.0))),
    In(Get("a"), Lit(List([]))),
    Match(Get("a"), [([Str("x"), Num(2.0)], Zoom)], Lit(Null)),
    Case([(Has("a"), Zoom)], Id),
    Coalesce([Get("a"), Get("b")]),
    Interpolate(CubicBezier(0.1, 0.2, 0.3, 0.4), Lab, Zoom, [
      (1.0, Zoom),
      (2.0, Id),
    ]),
    Interpolate(Exponential(1.5), Hcl, Zoom, []),
    Step(Zoom, Id, [(3.0, Zoom)]),
    FeatureState("hover"),
    Assert(ArrayOf(ArrayOf(NumberType, 2), -1), [Get("a")]),
    Coerce(ColorType, [Get("a"), Lit(Str("red"))]),
    Call(ToRgba, [Get("a")]),
    Call(Add, [Zoom, Zoom]),
    Call(Split, [Get("a"), Lit(Str(","))]),
    Call(Join, [Get("a"), Lit(Str(","))]),
    Call(Format, [Get("a"), Zoom, Lit(Null), Get("c"), Lit(Str("top"))]),
    Call(NumberFormat, [Zoom, Lit(Str("ja")), Lit(Null), Lit(Null), Id, Id]),
    Call(ResolvedLocale, [
      Call(Collator, [Lit(Bool(true)), Lit(Bool(false)), Lit(Null)]),
    ]),
    Collate(
      Lt,
      Get("a"),
      Get("b"),
      Call(Collator, [Lit(Bool(false)), Get("d"), Lit(Str("de"))]),
    ),
  ]
  for e in exprs {
    let w = @core.ByteWriter::new()
    @style.write_expr(w, Some(e))
    let r = @core.ByteReader::new(w.to_bytes()[:])
    assert_eq(@style.read_expr(r), Some(e))
    assert_true(r.done())
  }
  let w = @core.ByteWriter::new()
  @style.write_expr(w, None)
  assert_eq(w.to_bytes(), b"\x00")
  let r = @core.ByteReader::new(b"\x00"[:])
  assert_eq(@style.read_expr(r), None)
  assert_true(r.done())
}

///|
/// The bytes of `e`, for corrupting.
fn expr_bytes(e : @style.Expr) -> Bytes {
  let w = @core.ByteWriter::new()
  @style.write_expr(w, Some(e))
  w.to_bytes()
}

///|
test "read_expr refuses unknown tags, short input and huge counts" {
  for
    bad in [
      b"\x02"[:],
      b"\x01\x63"[:],
      b"\x01\x00\x09"[:],
      b"\x01\x0c\x06\x03\x05"[:],
      b"\x01\x16\x20\x00\x00\x00\x00"[:],
      b"\x01\x0a\xff\xff\xff\x7f"[:],
      expr_bytes(Get("abc"))[:6],
      expr_bytes(Call(NumberFormat, [Zoom]))[:],
      expr_bytes(Call(Format, [Zoom, Zoom]))[:],
      expr_bytes(Call(Split, [Zoom]))[:],
    ] {
    let r = @core.ByteReader::new(bad)
    @style.read_expr(r) |> ignore
    assert_true(!r.ok())
  }
}

///|
test "read_expr refuses more nodes or levels than a compiled expression may have" {
  let wide = @style.Expr::All(
    Array::make(@style.MAX_EXPR_NODES, @style.Expr::Zoom),
  )
  let r = @core.ByteReader::new(expr_bytes(wide)[:])
  @style.read_expr(r) |> ignore
  assert_true(!r.ok())
  let fits = @style.Expr::All(
    Array::make(@style.MAX_EXPR_NODES - 1, @style.Expr::Zoom),
  )
  let r = @core.ByteReader::new(expr_bytes(fits)[:])
  assert_eq(@style.read_expr(r), Some(fits))
  let mut deep : @style.Expr = Zoom
  for _ in 0..<(4 * @style.MAX_EXPR_DEPTH + 1) {
    deep = Not(deep)
  }
  let r = @core.ByteReader::new(expr_bytes(deep)[:])
  @style.read_expr(r) |> ignore
  assert_true(!r.ok())
  let mut ok : @style.Expr = Zoom
  for _ in 0..<(4 * @style.MAX_EXPR_DEPTH) {
    ok = Not(ok)
  }
  let r = @core.ByteReader::new(expr_bytes(ok)[:])
  assert_eq(@style.read_expr(r), Some(ok))
}

///|
test "from_compiled refuses truncated or trailing bytes" {
  let bytes = @style.Style::parse(compiled_style).to_compiled()
  let n = bytes.length()
  let longer = Bytes::makei(n + 1, i => if i < n { bytes[i] } else { b'\x00' })
  for bad in [bytes[:n - 1], b"\x01\x00\x00\x00"[:], longer[:]] {
    let refused = try @style.Style::from_compiled(bad) catch {
      Invalid(_, ..) => true
      _ => false
    } noraise {
      _ => false
    }
    assert_true(refused)
  }
}
