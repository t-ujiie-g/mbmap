///|
test "symbol layers read text layout and halo, with MapLibre's defaults" {
  let s = @style.Style::parse(
    (
      #|{"layers": [
      #|  {"id": "a", "type": "symbol", "source": "s", "source-layer": "label",
      #|   "layout": {"text-field": "{knj} ({n})", "text-size": 12, "text-anchor": "top-left",
      #|              "text-offset": [0, 1], "text-max-width": 8, "text-allow-overlap": true},
      #|   "paint": {"text-color": "#ff0000", "text-halo-color": "#ffffff", "text-halo-width": 1.5}},
      #|  {"id": "b", "type": "symbol",
      #|   "layout": {"text-field": ["concat", ["get", "a"], "-", ["to-string", ["get", "b"]]]}}
      #|]}
    ),
  )
  let a = s.layers[0]
  assert_eq(a.kind, Symbol)
  let t = a.text.unwrap()
  assert_eq(t.field, [Get("knj"), Lit(Str(" (")), Get("n"), Lit(Str(")"))])
  assert_eq(constant(t.size), Num(12.0))
  assert_eq((t.anchor, t.offset, t.max_width), (TopLeft, (0.0, 1.0), 8.0))
  assert_eq((t.allow_overlap, t.ignore_placement), (true, false))
  assert_eq(constant(a.color), Color({ r: 1.0, g: 0.0, b: 0.0, a: 1.0, }))
  assert_eq(constant(a.halo_width), Num(1.5))
  let b = s.layers[1].text.unwrap()
  assert_eq(b.field, [Get("a"), Lit(Str("-")), Get("b")])
  assert_eq(constant(b.size), Num(16.0))
  assert_eq(
    (b.anchor, b.offset, b.max_width, b.line_height, b.padding),
    (Center, (0.0, 0.0), 10.0, 1.2, 2.0),
  )
  assert_eq(
    constant(s.layers[1].halo_color),
    Color({ r: 0.0, g: 0.0, b: 0.0, a: 0.0, }),
  )
  assert_eq((b.vertical, b.sort_key), (false, None))
}

///|
test "text-writing-mode takes its first mode; symbol-sort-key compiles" {
  let s = @style.Style::parse(
    (
      #|{"layers": [
      #|  {"id": "v", "type": "symbol", "layout": {"text-writing-mode": ["vertical", "horizontal"],
      #|   "symbol-sort-key": ["get", "rank"]}},
      #|  {"id": "h", "type": "symbol", "layout": {"text-writing-mode": ["horizontal", "vertical"]}}
      #|]}
    ),
  )
  let v = s.layers[0].text.unwrap()
  assert_eq(
    (v.vertical, v.sort_key),
    (true, Some(Assert(NumberType, [Get("rank")]))),
  )
  assert_false(s.layers[1].text.unwrap().vertical)
  try
    @style.Style::parse(
      "{\"layers\": [{\"id\": \"a\", \"type\": \"symbol\", \"layout\": {\"text-writing-mode\": \"vertical\"}}]}",
    )
  catch {
    Invalid(path~, _) => assert_eq(path, "layers[0].layout.text-writing-mode")
    e => fail("unexpected \{Repr(e)}")
  } noraise {
    _ => fail("expected a bare string to be invalid")
  }
}

///|
test "variable anchors take MapLibre's offsets in ems, shaped centered" {
  let b = 7.0 / 24.0
  let h = 1.0 / 2.0.sqrt()
  let s = @style.Style::parse(
    (
      #|{"layers": [
      #|  {"id": "r", "type": "symbol", "layout": {"text-variable-anchor": ["top", "bottom-left", "right", "center"],
      #|   "text-radial-offset": 1, "text-offset": [5, 5], "text-anchor": "left", "text-justify": "auto"}},
      #|  {"id": "o", "type": "symbol", "layout": {"text-variable-anchor": ["top-right", "left", "bottom"],
      #|   "text-offset": [-0.5, -2]}},
      #|  {"id": "a", "type": "symbol", "layout": {"text-variable-anchor-offset": ["top", [0, 1], "left", [2, 0]],
      #|   "text-variable-anchor": ["bottom"]}},
      #|  {"id": "f", "type": "symbol", "layout": {"text-anchor": "bottom-right", "text-radial-offset": 2, "text-justify": "right"}}
      #|]}
    ),
  )
  let r = s.layers[0].text.unwrap()
  assert_eq(r.variable, [
    (Top, 0.0, 1.0 - b),
    (BottomLeft, h, -h + b),
    (Right, -1.0, 0.0),
    (Center, 0.0, 0.0),
  ])
  assert_eq((r.anchor, r.offset, r.justify), (Center, (0.0, 0.0), Auto))
  let o = s.layers[1].text.unwrap()
  assert_eq(o.variable, [
    (TopRight, -0.5, 2.0 - b),
    (Left, 0.5, 0.0),
    (Bottom, 0.0, -2.0 + b),
  ])
  assert_eq(o.justify, Center)
  let a = s.layers[2].text.unwrap()
  assert_eq(a.variable, [(Top, 0.0, 1.0 - b), (Left, 2.0, 0.0)])
  let f = s.layers[3].text.unwrap()
  assert_eq(f.variable, [])
  assert_eq(
    (f.anchor, f.offset, f.justify),
    (BottomRight, (-2.0 * h, -2.0 * h + b), Right),
  )
}

///|
test "variable anchors as expressions are unsupported, unknown ones invalid" {
  let cases = [
    (
      "{\"text-variable-anchor-offset\": [\"step\", [\"zoom\"], [\"literal\", []]]}",
      "layers[0].layout.text-variable-anchor-offset", true,
    ),
    (
      "{\"text-variable-anchor-offset\": [\"top\", [0, 1], \"left\"]}", "layers[0].layout.text-variable-anchor-offset",
      false,
    ),
    (
      "{\"text-variable-anchor\": [\"top\", \"middle\"]}", "layers[0].layout.text-variable-anchor",
      false,
    ),
    (
      "{\"text-variable-anchor\": \"top\"}", "layers[0].layout.text-variable-anchor",
      false,
    ),
    (
      "{\"text-anchor\": [\"get\", \"a\"]}", "layers[0].layout.text-anchor", true,
    ),
    ("{\"text-justify\": \"middle\"}", "layers[0].layout.text-justify", false),
    (
      "{\"text-radial-offset\": [\"get\", \"r\"]}", "layers[0].layout.text-radial-offset",
      true,
    ),
  ]
  for c in cases {
    let text = "{\"layers\": [{\"id\": \"a\", \"type\": \"symbol\", \"layout\": \{c.0}}]}"
    try @style.Style::parse(text) catch {
      Unsupported(path~, _) if c.2 => assert_eq(path, c.1)
      Invalid(path~, _) if !c.2 => assert_eq(path, c.1)
      e => fail("unexpected \{Repr(e)} for \{c.0}")
    } noraise {
      _ => fail("expected \{c.0} to fail")
    }
  }
}

///|
test "labels along lines read spacing, angle and uprightness, with MapLibre's defaults" {
  let s = @style.Style::parse(
    (
      #|{"layers": [
      #|  {"id": "l", "type": "symbol", "layout": {"symbol-placement": "line", "text-rotation-alignment": "map"}},
      #|  {"id": "c", "type": "symbol", "layout": {"symbol-placement": "line-center", "symbol-spacing": 0,
      #|   "text-max-angle": 20, "text-keep-upright": false}},
      #|  {"id": "p", "type": "symbol"}
      #|]}
    ),
  )
  let l = s.layers[0].text.unwrap()
  assert_eq(
    (l.placement, l.spacing, l.max_angle, l.keep_upright),
    (Line, 250.0, 45.0, true),
  )
  let c = s.layers[1].text.unwrap()
  assert_eq(
    (c.placement, c.spacing, c.max_angle, c.keep_upright),
    (LineCenter, 1.0, 20.0, false),
  )
  assert_eq(s.layers[2].text.unwrap().placement, Point)
  try
    @style.Style::parse(
      "{\"layers\": [{\"id\": \"a\", \"type\": \"symbol\", \"layout\": {\"symbol-placement\": \"middle\"}}]}",
    )
  catch {
    Invalid(path~, _) => assert_eq(path, "layers[0].layout.symbol-placement")
    e => fail("unexpected \{Repr(e)}")
  } noraise {
    _ => fail("expected an unknown placement to be invalid")
  }
}

///|
test "text along lines turned to the viewport or offset, icons offset or fitted along lines and format are unsupported" {
  let cases = [
    (
      "{\"symbol-placement\": \"line\", \"text-rotation-alignment\": \"viewport\"}",
      "layers[0].layout.text-rotation-alignment",
    ),
    (
      "{\"symbol-placement\": \"line-center\", \"text-pitch-alignment\": \"viewport\"}",
      "layers[0].layout.text-pitch-alignment",
    ),
    (
      "{\"symbol-placement\": \"line\", \"text-offset\": [0, 1]}", "layers[0].layout.text-offset",
    ),
    (
      "{\"symbol-placement\": \"line\", \"icon-image\": \"x\", \"icon-offset\": [0, 1]}",
      "layers[0].layout.icon-offset",
    ),
    (
      "{\"symbol-placement\": \"line\", \"icon-image\": \"x\", \"icon-text-fit\": \"both\"}",
      "layers[0].layout.icon-text-fit",
    ),
    (
      "{\"symbol-placement\": \"line-center\", \"icon-image\": \"x\", \"icon-pitch-alignment\": \"viewport\"}",
      "layers[0].layout.icon-pitch-alignment",
    ),
    (
      "{\"icon-image\": \"x\", \"icon-offset\": [\"literal\", [0, 1]]}", "layers[0].layout.icon-offset",
    ),
    ("{\"text-field\": [\"format\", \"a\", {}]}", "layers[0].layout.text-field"),
  ]
  for c in cases {
    let text = "{\"layers\": [{\"id\": \"a\", \"type\": \"symbol\", \"layout\": \{c.0}}]}"
    try @style.Style::parse(text) catch {
      Unsupported(path~, _) => assert_eq(path, c.1)
      e => fail("unexpected \{Repr(e)}")
    } noraise {
      _ => fail("expected \{c.0} to be unsupported")
    }
  }
  try
    @style.Style::parse(
      "{\"layers\": [{\"id\": \"a\", \"type\": \"symbol\", \"layout\": {\"text-anchor\": \"middle\"}}]}",
    )
  catch {
    Invalid(path~, _) => assert_eq(path, "layers[0].layout.text-anchor")
    e => fail("unexpected \{Repr(e)}")
  } noraise {
    _ => fail("expected an unknown anchor to be invalid")
  }
}
