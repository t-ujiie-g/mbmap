///|
test "symbol layers read icon layout and paint, with MapLibre's defaults" {
  let s = @style.Style::parse(
    (
      #|{"layers": [
      #|  {"id": "a", "type": "symbol",
      #|   "layout": {"icon-image": "shop-{kind}", "icon-size": ["get", "s"], "icon-anchor": "bottom",
      #|              "icon-offset": [1, -2], "icon-rotate": 30, "icon-padding": [1, 2],
      #|              "icon-allow-overlap": true, "icon-optional": true, "text-optional": true,
      #|              "icon-rotation-alignment": "map", "icon-text-fit": "both",
      #|              "icon-text-fit-padding": [1, 2, 3, 4]},
      #|   "paint": {"icon-color": "#ff0000", "icon-halo-width": 2, "icon-opacity": 0.5}},
      #|  {"id": "b", "type": "symbol", "layout": {"icon-image": ["image", ["get", "n"]], "icon-padding": 3}},
      #|  {"id": "c", "type": "symbol", "layout": {"text-field": "x"}}
      #|]}
    ),
  )
  let a = s.layers[0].icon.unwrap()
  assert_eq(a.image, [Lit(Str("shop-")), Get("kind")])
  assert_eq(a.size.feature_inputs(), (["s"], false))
  assert_eq(a.anchor, Bottom)
  assert_eq(a.offset, (1.0, -2.0))
  assert_eq(a.padding, (1.0, 2.0, 1.0, 2.0))
  assert_true(a.allow_overlap && a.optional && a.text_optional)
  assert_false(a.ignore_placement)
  // `icon-pitch-alignment: auto` follows the rotation alignment.
  assert_true(a.rotate_with_map && a.pitch_with_map)
  assert_eq(a.text_fit, Both)
  assert_eq(a.text_fit_padding, (1.0, 2.0, 3.0, 4.0))
  let p = s.layers[0].icon_paint.unwrap()
  assert_eq(p.exprs().length(), 5)
  assert_true(p.opacity is Lit(Num(0.5)))
  let b = s.layers[1].icon.unwrap()
  assert_eq(b.image, [Get("n")])
  assert_eq(b.padding, (3.0, 3.0, 3.0, 3.0))
  assert_eq((b.anchor, b.offset, b.text_fit), (Center, (0.0, 0.0), NoFit))
  assert_false(b.rotate_with_map || b.pitch_with_map || b.keep_upright)
  assert_true(s.layers[1].icon_paint.unwrap().halo_width is Lit(Num(0.0)))
  assert_true(s.layers[2].icon is None)
}

///|
test "icon layout that cannot be drawn is refused with its path" {
  let cases = [
    (
      "{\"icon-image\": \"x\", \"icon-padding\": [1, 2, 3, 4, 5]}", "icon-padding",
    ),
    ("{\"icon-image\": \"x\", \"icon-padding\": \"1\"}", "icon-padding"),
    ("{\"icon-image\": \"x\", \"icon-text-fit\": \"all\"}", "icon-text-fit"),
    (
      "{\"icon-image\": \"x\", \"icon-pitch-alignment\": \"up\"}", "icon-pitch-alignment",
    ),
    ("{\"icon-image\": \"x\", \"icon-offset\": 1}", "icon-offset"),
  ]
  for c in cases {
    let text = "{\"layers\": [{\"id\": \"a\", \"type\": \"symbol\", \"layout\": \{c.0}}]}"
    try @style.Style::parse(text) catch {
      Invalid(path~, _) => assert_eq(path, "layers[0].layout.\{c.1}")
      e => fail("unexpected \{e.message()}")
    } noraise {
      _ => fail("expected \{c.0} to be invalid")
    }
  }
  let state = "{\"layers\": [{\"id\": \"a\", \"type\": \"symbol\", \"layout\": {\"icon-image\": \"x\", \"icon-size\": [\"feature-state\", \"s\"]}}]}"
  try @style.Style::parse(state) catch {
    Invalid(path~, _) => assert_eq(path, "layers[0].layout")
    e => fail("unexpected \{e.message()}")
  } noraise {
    _ => fail("feature-state in icon-size")
  }
  let expr = "{\"layers\": [{\"id\": \"a\", \"type\": \"symbol\", \"layout\": {\"icon-image\": \"x\", \"icon-padding\": [\"get\", \"p\"]}}]}"
  try @style.Style::parse(expr) catch {
    Unsupported(path~, _) => assert_eq(path, "layers[0].layout.icon-padding")
    e => fail("unexpected \{e.message()}")
  } noraise {
    _ => fail("expressions in icon-padding")
  }
}

///|
test "icon layout is part of a layer's tiles, icon paint only by its inputs" {
  let parse = (layout : String, paint : String) => {
    let text = "{\"layers\": [{\"id\": \"a\", \"type\": \"symbol\", \"layout\": {\"icon-image\": \"x\", \{layout}}, \"paint\": {\{paint}}}]}"
    @style.Style::parse(text).layers[0]
  }
  let base = parse("\"icon-size\": 1", "\"icon-opacity\": 1")
  assert_true(
    base.same_tiles(parse("\"icon-size\": 1", "\"icon-opacity\": 0.5")),
  )
  assert_false(
    base.same_tiles(parse("\"icon-size\": 2", "\"icon-opacity\": 1")),
  )
  assert_false(
    base.same_tiles(
      parse("\"icon-size\": 1", "\"icon-opacity\": [\"get\", \"o\"]"),
    ),
  )
}
