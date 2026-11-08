///|
fn paths(style : @style.Style) -> Array[String] {
  style.warnings.map(w => {
    match w {
      Invalid(path~, _) | Unsupported(path~, _) => path
    }
  })
}

///|
let lenient_style : String =
  #|{"version": 8,
  #| "sources": {
  #|   "v": {"type": "vector", "tiles": ["https://example.com/{z}/{x}/{y}.pbf"]},
  #|   "f": {"type": "vector", "tiles": ["file:///tiles/{z}/{x}/{y}.pbf"]}},
  #| "layers": [
  #|   {"id": "road", "type": "line", "source": "v", "source-layer": "road",
  #|    "paint": {"line-color": ["get", "c", ["literal", {}]], "line-width": 3}},
  #|   {"id": "odd", "type": "fill", "source": "v", "source-layer": "a",
  #|    "filter": ["has", "k", ["literal", {}]]},
  #|   {"id": "local", "type": "fill", "source": "f", "source-layer": "a"},
  #|   {"id": "relief", "type": "model", "source": "v"},
  #|   {"id": "water", "type": "fill", "source": "v", "source-layer": "water",
  #|    "layout": {"fill-sort-key": 2, "symbol-avoid-edges": true}}]}

///|
test "a lenient style leaves out what it cannot draw and lists it" {
  let style = @style.Style::parse(lenient_style, strict=false)
  assert_eq(style.layers.map(l => l.id), ["road", "water"])
  assert_eq(style.sources.map(s => s.id), ["v"])
  // The unsupported line color goes back to its default; the width stays.
  assert_eq(constant(style.layers[0].width), Num(3.0))
  assert_eq(constant(style.layers[0].color), Color({ r: 0, g: 0, b: 0, a: 1, }))
  assert_eq(paths(style), [
    "sources.f.tiles", "sources.f", "layers[0].paint.line-color", "layers[1].filter",
    "layers[2]", "layers[3].type",
  ])
}

///|
test "a strict style raises at the first thing it cannot draw" {
  let path = try {
    @style.Style::parse(lenient_style) |> ignore
    ""
  } catch {
    Unsupported(path~, _) => path
    e => e.message()
  }
  assert_eq(path, "sources.f.tiles")
}

///|
test "properties parsed but not drawn yet are reported only when asked" {
  let json = @json.parse(lenient_style)
  let style = @style.Style::from_json(json, strict=false)
  style.report_ignored(json, strict=false)
  assert_eq(paths(style).last(), Some("layers[4].layout.symbol-avoid-edges"))
  let path = try {
    @style.Style::from_json(json, strict=false).report_ignored(json)
    ""
  } catch {
    Unsupported(path~, _) => path
    e => e.message()
  }
  assert_eq(path, "layers[4].layout.symbol-avoid-edges")
}

///|
test "fonts and colors of format sections are drawn without warnings" {
  let json = @json.parse(
    (
      #|{"version": 8, "sources": {"v": {"type": "vector", "tiles": ["https://x/{z}/{x}/{y}"]}},
      #| "layers": [{"id": "t", "type": "symbol", "source": "v", "source-layer": "l",
      #|   "layout": {"text-field": ["case", true, ["format", "a", {"text-color": "red"}],
      #|                             ["format", "b", {"font-scale": 2, "text-font": ["literal", ["A"]]}]]}}]}
    ),
  )
  let style = @style.Style::from_json(json, strict=false)
  assert_eq(style.layers.length(), 1)
  style.report_ignored(json, strict=false)
  assert_eq(style.warnings.map(e => e.message()), [])
}

///|
test "an unsupported light goes back to the default light" {
  let style = @style.Style::parse(
    (
      #|{"version": 8, "sources": {}, "layers": [],
      #| "light": {"position": ["get", "p"]}}
    ),
    strict=false,
  )
  assert_eq(paths(style), ["light.position"])
}

///|
test "lights give an ambient and a directional light, and unknown lights are reported" {
  let style = @style.Style::parse(
    (
      #|{"version": 8, "sources": {}, "layers": [], "lights": [
      #|  {"id": "a", "type": "ambient", "properties": {"color": "#ff0000", "intensity": 0.3}},
      #|  {"id": "s", "type": "directional", "properties": {"intensity": 0.6, "direction": [90, 45]}}]}
    ),
  )
  let lights = style.lights.unwrap()
  assert_eq(lights.direction, (90.0, 45.0))
  assert_true(lights.ambient_intensity is Lit(Num(0.3)))
  assert_true(lights.sun_intensity is Lit(Num(0.6)))
  assert_true(
    @style.Style::parse("{\"version\": 8, \"sources\": {}, \"layers\": []}").lights
    is None,
  )
  let flash = @style.Style::parse(
    (
      #|{"version": 8, "sources": {}, "layers": [], "lights": [{"id": "f", "type": "flashlight"}]}
    ),
    strict=false,
  )
  assert_true(flash.lights is None)
  assert_eq(paths(flash), ["lights[0].type"])
  let bad = try {
    @style.Style::parse(
      "{\"version\": 8, \"sources\": {}, \"layers\": [], \"lights\": {}}",
    )
    |> ignore
    false
  } catch {
    Invalid(path~, _) => path == "lights"
    _ => false
  }
  assert_true(bad)
}
