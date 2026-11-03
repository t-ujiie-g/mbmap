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
  #|    "paint": {"line-color": ["collator", {}], "line-width": 3}},
  #|   {"id": "odd", "type": "fill", "source": "v", "source-layer": "a",
  #|    "filter": ["within", {}]},
  #|   {"id": "local", "type": "fill", "source": "f", "source-layer": "a"},
  #|   {"id": "relief", "type": "model", "source": "v"},
  #|   {"id": "water", "type": "fill", "source": "v", "source-layer": "water",
  #|    "paint": {"fill-translate": [1, 2]}}]}

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
  assert_eq(paths(style).last(), Some("layers[4].paint.fill-translate"))
  let path = try {
    @style.Style::from_json(json, strict=false).report_ignored(json)
    ""
  } catch {
    Unsupported(path~, _) => path
    e => e.message()
  }
  assert_eq(path, "layers[4].paint.fill-translate")
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
