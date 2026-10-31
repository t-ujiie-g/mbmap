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
    (water.kind, water.source_layer, water.opacity, water.filter),
    (Fill, "waterarea", 0.5, AnyGeometry),
  )
  let road = s.layers[2]
  assert_eq(
    (road.kind, road.width, road.min_zoom, road.filter),
    (Line, 3.0, 12.0, OnlyLineString),
  )
  assert_eq((road.join, road.cap, road.color.r), (Round, Square, 1.0))
  assert_eq(
    (s.layers[0].kind, s.layers[0].max_zoom, road.miter_limit),
    (Background, 24.0, 2.0),
  )
}

///|
test "expressions and other filters are reported, not ignored" {
  let cases = [
    (
      (
        #|{"layers": [{"id": "a", "type": "line", "paint": {"line-width": ["get", "w"]}}]}
      ),
      "layers[0].paint.line-width",
    ),
    (
      (
        #|{"layers": [{"id": "a", "type": "fill", "filter": ["==", ["get", "k"], 1]}]}
      ),
      "layers[0].filter",
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
