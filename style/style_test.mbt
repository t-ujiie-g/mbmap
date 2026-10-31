///|
test "parse_color reads hex, rgb() and a few names" {
  assert_eq(
    @style.parse_color("#fff"),
    Some({ r: 1.0, g: 1.0, b: 1.0, a: 1.0, }),
  )
  assert_eq(
    @style.parse_color("#FF000080").map(c => (c.r, c.a)),
    Some((1.0, 128.0 / 255.0)),
  )
  assert_eq(
    @style.parse_color(" rgba(0, 51, 255, 0.5) "),
    Some({ r: 0.0, g: 0.2, b: 1.0, a: 0.5, }),
  )
  assert_eq(
    @style.parse_color("rgb(255,255,255)"),
    Some({ r: 1.0, g: 1.0, b: 1.0, a: 1.0, }),
  )
  assert_eq(@style.parse_color("transparent").map(c => c.a), Some(0.0))
  for
    bad in [
      "#12", "#ggg", "rgb(1,2)", "rgba(1,2,3)", "rgb(300,0,0)", "hsl(0,0%,0%)", "red",
    ] {
    assert_eq(@style.parse_color(bad), None)
  }
}

///|
let sample : String =
  #|{
  #|  "version": 8,
  #|  "sources": {
  #|    "gsi": { "type": "vector", "tiles": ["https://x/{z}/{x}/{y}.pbf"], "minzoom": 4, "maxzoom": 16 },
  #|    "dem": { "type": "raster-dem", "url": "x" }
  #|  },
  #|  "layers": [
  #|    { "id": "bg", "type": "background", "paint": { "background-color": "#f5f3ee" } },
  #|    { "id": "water", "type": "fill", "source": "gsi", "source-layer": "waterarea",
  #|      "paint": { "fill-color": "#a8d4f0", "fill-opacity": 0.5 } },
  #|    { "id": "label", "type": "symbol", "source": "gsi", "source-layer": "label" },
  #|    { "id": "hidden", "type": "line", "source": "gsi", "source-layer": "road",
  #|      "layout": { "visibility": "none" } },
  #|    { "id": "road", "type": "line", "source": "gsi", "source-layer": "road", "minzoom": 12,
  #|      "filter": ["==", ["geometry-type"], "LineString"],
  #|      "layout": { "line-join": "round", "line-cap": "square" },
  #|      "paint": { "line-color": "rgb(255, 255, 255)", "line-width": 3 } }
  #|  ]
  #|}

///|
fn constant(e : @style.Expr) -> @style.Value {
  e.eval(0.0, @style.NoFeature::{ })
}

///|
test "a style keeps its vector sources and drawable layers in order" {
  let s = @style.Style::parse(sample)
  assert_eq(s.sources.length(), 1)
  let gsi = s.source("gsi").unwrap()
  assert_eq(
    (gsi.tiles, gsi.min_zoom, gsi.max_zoom),
    (["https://x/{z}/{x}/{y}.pbf"], 4, 16),
  )
  assert_eq(s.layers.map(l => l.id), ["bg", "water", "road"])
  let water = s.layers[1]
  assert_eq(
    (water.kind, water.source_layer, water.filter),
    (Fill, "waterarea", None),
  )
  assert_eq(constant(water.opacity), Num(0.5))
  let road = s.layers[2]
  assert_eq((road.kind, road.min_zoom), (Line, 12.0))
  assert_eq(constant(road.width), Num(3.0))
  assert_eq(
    road.filter,
    Some(Compare(Eq, GeometryType, Lit(Str("LineString")))),
  )
  assert_eq((road.join, road.cap), (Round, Square))
  assert_eq(constant(road.color), Color({ r: 1.0, g: 1.0, b: 1.0, a: 1.0, }))
  assert_eq(
    (s.layers[0].kind, s.layers[0].max_zoom, road.miter_limit),
    (Background, 24.0, 2.0),
  )
  assert_eq(constant(s.layers[0].width), Num(1.0))
}

///|
test "unsupported expressions are reported with their path, not ignored" {
  let cases = [
    (
      (
        #|{"layers": [{"id": "a", "type": "line", "paint": {"line-width": ["sqrt", 2]}}]}
      ),
      "layers[0].paint.line-width",
    ),
    (
      (
        #|{"layers": [{"id": "a", "type": "fill", "filter": ["all", ["get", "k", {}]]}]}
      ),
      "layers[0].filter[1]",
    ),
    (
      (
        #|{"sources": {"s": {"type": "vector", "url": "x"}}, "layers": []}
      ),
      "sources.s",
    ),
  ]
  for c in cases {
    let (text, where_) = c
    try @style.Style::parse(text) catch {
      Unsupported(path~, _) => assert_eq(path, where_)
      e => fail("unexpected \{Repr(e)}")
    } noraise {
      _ => fail("expected Unsupported at \{where_}")
    }
  }
}

///|
test "malformed styles are Invalid with a path" {
  let cases = [
    ("[1]", ""),
    ("{\"layers\": 1}", "layers"),
    ("{\"layers\": [{\"id\": \"a\"}]}", "layers[0].type"),
    (
      "{\"layers\": [{\"type\": \"fill\", \"paint\": {\"fill-color\": \"nope\"}}]}",
      "layers[0].paint.fill-color",
    ),
    (
      "{\"layers\": [{\"type\": \"line\", \"layout\": {\"line-cap\": \"x\"}}]}",
      "layers[0].layout.line-cap",
    ),
    ("not json", ""),
  ]
  for c in cases {
    let (text, where_) = c
    try @style.Style::parse(text) catch {
      Invalid(path~, _) => assert_eq(path, where_)
      e => fail("unexpected \{Repr(e)}")
    } noraise {
      _ => fail("expected Invalid at \{where_}")
    }
  }
}

///|
test "from_json takes a parsed document; errors read as one line" {
  let s = @style.Style::from_json({
    "layers": [{ "id": "bg", "type": "background" }],
  })
  assert_eq(s.layers.map(l => l.kind), [Background])
  assert_eq(
    @style.Invalid(path="layers[0].type", "missing").message(),
    "layers[0].type: missing",
  )
  assert_eq(@style.Invalid(path="", "not an object").message(), "not an object")
  assert_eq(
    @style.Unsupported(path="sources.s", "url").message(),
    "sources.s: unsupported: url",
  )
  assert_eq(@style.Unsupported(path="", "x").message(), "unsupported: x")
}

///|
test "rgb() components are plain decimals" {
  assert_eq(@style.parse_color("rgba(0,0,0,.5)").map(c => c.a), Some(0.5))
  assert_eq(
    @style.parse_color("rgb(12.5,0,0)").map(c => c.r),
    Some(12.5 / 255.0),
  )
  for bad in ["rgb(1.2.3,0,0)", "rgb(,0,0)", "rgb(-1,0,0)", "rgb(1e2,0,0)"] {
    assert_eq(@style.parse_color(bad), None)
  }
}

///|
test "tile URLs are relative or http(s)" {
  let style = (url : String) => {
    "{\"sources\": {\"s\": {\"type\": \"vector\", \"tiles\": [\"\{url}\"]}}, \"layers\": []}"
  }
  for
    ok in [
      "https://x/{z}/{x}/{y}.pbf", "HTTP://x/{z}", "/tiles/{z}/{x}/{y}.pbf", "tiles/{z}.pbf",
      "//cdn.example/{z}", "a/b:c/{z}",
    ] {
    assert_eq(@style.Style::parse(style(ok)).sources[0].tiles, [ok])
  }
  for bad in ["javascript:alert(1)", "data:,x", "file:///etc/{z}", "blob:x"] {
    try @style.Style::parse(style(bad)) catch {
      Unsupported(path~, _) => assert_eq(path, "sources.s.tiles")
      e => fail("unexpected \{Repr(e)}")
    } noraise {
      _ => fail("expected \{bad} to be refused")
    }
  }
}

///|
test "circle layers read radius and stroke, with MapLibre's defaults" {
  let s = @style.Style::parse(
    (
      #|{"layers": [
      #|  {"id": "a", "type": "circle", "source": "s", "source-layer": "pts",
      #|   "paint": {"circle-radius": ["interpolate", ["linear"], ["zoom"], 10, 2, 20, 12],
      #|             "circle-color": "#ff0000", "circle-stroke-width": 1, "circle-stroke-color": "#ffffff"}},
      #|  {"id": "b", "type": "circle"}
      #|]}
    ),
  )
  let a = s.layers[0]
  assert_eq(a.kind, Circle)
  assert_eq(a.radius.eval(15.0, @style.NoFeature::{ }), Num(7.0))
  assert_eq(constant(a.color), Color({ r: 1.0, g: 0.0, b: 0.0, a: 1.0, }))
  assert_eq(constant(a.stroke_width), Num(1.0))
  assert_eq(
    constant(a.stroke_color),
    Color({ r: 1.0, g: 1.0, b: 1.0, a: 1.0, }),
  )
  let b = s.layers[1]
  assert_eq(
    (constant(b.radius), constant(b.stroke_width), constant(b.stroke_opacity)),
    (Num(5.0), Num(0.0), Num(1.0)),
  )
  assert_eq(
    constant(b.stroke_color),
    Color({ r: 0.0, g: 0.0, b: 0.0, a: 1.0, }),
  )
}
