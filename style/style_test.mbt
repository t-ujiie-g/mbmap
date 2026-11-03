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
  #|    "photo": { "type": "image", "url": "x" }
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
  assert_eq(s.layers.map(l => l.id), ["bg", "water", "label", "road"])
  let water = s.layers[1]
  assert_eq(
    (water.kind, water.source_layer, water.filter),
    (Fill, "waterarea", None),
  )
  assert_eq(constant(water.opacity), Num(0.5))
  assert_eq(s.layers[2].kind, Symbol)
  let road = s.layers[3]
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
        #|{"layers": [{"id": "a", "type": "line", "paint": {"line-width": ["number-format", 2, {}]}}]}
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

///|
test "layers with identically written filters share a filter_id" {
  let s = @style.Style::parse(
    (
      #|{"layers": [
      #|  {"id": "a", "type": "line", "filter": ["==", ["get", "k"], 1]},
      #|  {"id": "b", "type": "line"},
      #|  {"id": "c", "type": "line", "filter": ["==", ["get", "k"], 2]},
      #|  {"id": "d", "type": "fill", "filter": ["==", ["get", "k"], 1]}
      #|]}
    ),
  )
  assert_eq(s.layers.map(l => l.filter_id), [0, -1, 1, 0])
}

///|
test "GeoJSON sources keep MapLibre's options; their data stays outside" {
  let s = @style.Style::parse(
    (
      #|{"sources": {
      #|  "pts": {"type": "geojson", "data": "points.geojson", "maxzoom": 16, "buffer": 64},
      #|  "inline": {"type": "geojson", "data": {"type": "FeatureCollection", "features": []}},
      #|  "clustered": {"type": "geojson", "data": "p.geojson", "cluster": true, "clusterRadius": 40,
      #|                "clusterMaxZoom": 12, "clusterMinPoints": 3},
      #|  "img": {"type": "image", "url": "x"}},
      #| "layers": []}
    ),
  )
  let pts = s.source("pts").unwrap()
  assert_eq(
    (pts.kind, pts.tiles, pts.max_zoom, pts.buffer, pts.tolerance),
    (GeoJSON, [], 16, 64, 0.375),
  )
  let inline = s.source("inline").unwrap()
  assert_eq((inline.max_zoom, inline.buffer), (18, 128))
  assert_eq(s.source("clustered").map(x => x.kind), Some(GeoJSON))
  assert_eq(s.source("img").map(x => x.id), None)
  for
    bad in [
      (
        "{\"sources\": {\"g\": {\"type\": \"geojson\"}}, \"layers\": []}", "sources.g.data",
      ),
      (
        "{\"sources\": {\"g\": {\"type\": \"geojson\", \"data\": {}, \"buffer\": 600}}, \"layers\": []}",
        "sources.g.buffer",
      ),
      (
        "{\"sources\": {\"g\": {\"type\": \"geojson\", \"data\": {}, \"cluster\": 1}}, \"layers\": []}",
        "sources.g.cluster",
      ),
      (
        "{\"sources\": {\"g\": {\"type\": \"geojson\", \"data\": {}, \"cluster\": true, \"clusterProperties\": {}}}, \"layers\": []}",
        "sources.g.clusterProperties",
      ),
      (
        "{\"sources\": {\"g\": {\"type\": \"geojson\", \"data\": {}, \"clusterRadius\": -1}}, \"layers\": []}",
        "sources.g.clusterRadius",
      ),
      (
        "{\"sources\": {\"g\": {\"type\": \"geojson\", \"data\": {}, \"clusterMinPoints\": \"2\"}}, \"layers\": []}",
        "sources.g.clusterMinPoints",
      ),
    ] {
    try @style.Style::parse(bad.0) catch {
      Invalid(path~, _) | Unsupported(path~, _) => assert_eq(path, bad.1)
    } noraise {
      _ => fail("expected an error at \{bad.1}")
    }
  }
}

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
test "symbol placement on lines, icons and format are unsupported" {
  let cases = [
    ("{\"symbol-placement\": \"line\"}", "layers[0].layout.symbol-placement"),
    ("{\"icon-image\": \"x\"}", "layers[0].layout.icon-image"),
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

///|
test "raster-dem sources and hillshade layers, with MapLibre's defaults" {
  let s = @style.Style::parse(
    (
      #|{"sources": {
      #|   "gsi": {"type": "raster-dem", "tiles": ["https://x/{z}/{x}/{y}.png"], "tileSize": 256,
      #|           "maxzoom": 14, "encoding": "gsi"},
      #|   "rgb": {"type": "raster-dem", "tiles": ["t/{z}/{x}/{y}.png"], "encoding": "custom",
      #|           "redFactor": 655.36, "greenFactor": 2.56, "blueFactor": 0.01},
      #|   "plain": {"type": "raster-dem", "tiles": ["t"]}},
      #| "layers": [
      #|  {"id": "h", "type": "hillshade", "source": "gsi",
      #|   "paint": {"hillshade-illumination-anchor": "map", "hillshade-exaggeration": 0.8,
      #|             "hillshade-shadow-color": "#473b24"}},
      #|  {"id": "d", "type": "hillshade", "source": "rgb"}
      #|]}
    ),
  )
  let gsi = s.source("gsi").unwrap()
  assert_eq(
    (gsi.kind, gsi.tile_size, gsi.max_zoom, gsi.encoding),
    (RasterDem, 256, 14, Gsi),
  )
  assert_eq(s.source("rgb").unwrap().encoding, Custom(655.36, 2.56, 0.01, 0.0))
  let plain = s.source("plain").unwrap()
  assert_eq((plain.tile_size, plain.encoding), (512, Mapbox))
  let h = s.layers[0].hillshade.unwrap()
  assert_eq((s.layers[0].kind, h.viewport), (Hillshade, false))
  assert_eq(constant(h.exaggeration), Num(0.8))
  assert_eq(
    constant(h.shadow),
    Color({ r: 71.0 / 255.0, g: 59.0 / 255.0, b: 36.0 / 255.0, a: 1.0, }),
  )
  let d = s.layers[1].hillshade.unwrap()
  assert_eq(
    (constant(d.direction), constant(d.exaggeration), d.viewport),
    (Num(335.0), Num(0.5), true),
  )
  assert_eq(constant(d.highlight), Color({ r: 1.0, g: 1.0, b: 1.0, a: 1.0, }))
}

///|
test "unknown DEM encodings, odd tile sizes and other hillshade methods are refused" {
  let cases = [
    (
      "{\"sources\": {\"d\": {\"type\": \"raster-dem\", \"tiles\": [\"t\"], \"encoding\": \"x\"}}, \"layers\": []}",
      "sources.d.encoding",
    ),
    (
      "{\"sources\": {\"d\": {\"type\": \"raster-dem\", \"tiles\": [\"t\"], \"tileSize\": 300}}, \"layers\": []}",
      "sources.d.tileSize",
    ),
    (
      "{\"layers\": [{\"id\": \"h\", \"type\": \"hillshade\", \"paint\": {\"hillshade-method\": \"igor\"}}]}",
      "layers[0].paint.hillshade-method",
    ),
  ]
  for c in cases {
    try @style.Style::parse(c.0) catch {
      Invalid(path~, _) | Unsupported(path~, _) => assert_eq(path, c.1)
    } noraise {
      _ => fail("expected \{c.1} to be refused")
    }
  }
}

///|
test "terrain names a raster-dem source and an exaggeration" {
  let base =
    #|{"sources": {"dem": {"type": "raster-dem", "tiles": ["t"]}, "v": {"type": "vector", "tiles": ["t"]}},
    #| "layers": [],
  let s = @style.Style::parse(
    base + "\"terrain\": {\"source\": \"dem\", \"exaggeration\": 1.5}}",
  )
  assert_eq(s.terrain.map(t => (t.source, t.exaggeration)), Some(("dem", 1.5)))
  let plain = @style.Style::parse(base + "\"terrain\": {\"source\": \"dem\"}}")
  assert_eq(plain.terrain.map(t => t.exaggeration), Some(1.0))
  assert_true(@style.Style::parse(base + "\"x\": 1}").terrain is None)
  for
    c in [
      ("\"terrain\": {\"source\": \"v\"}}", "terrain.source"),
      (
        "\"terrain\": {\"source\": \"dem\", \"exaggeration\": -1}}", "terrain.exaggeration",
      ),
      ("\"terrain\": 3}", "terrain"),
    ] {
    try @style.Style::parse(base + c.0) catch {
      Invalid(path~, _) => assert_eq(path, c.1)
      e => fail("unexpected \{Repr(e)}")
    } noraise {
      _ => fail("expected \{c.0} to be invalid")
    }
  }
}

///|
test "sky takes the spec's defaults and zoom expressions" {
  assert_true(@style.Style::parse("{\"layers\": []}").sky is None)
  let plain = @style.Style::parse("{\"layers\": [], \"sky\": {}}").sky.unwrap()
  assert_true(
    constant(plain.sky) is Color({ r, g, b, a: 1.0, }) &&
    r == 136.0 / 255.0 &&
    g == 198.0 / 255.0 &&
    b == 252.0 / 255.0,
  )
  assert_eq(constant(plain.horizon), constant(plain.fog))
  assert_eq(
    (
      constant(plain.fog_ground_blend),
      constant(plain.horizon_fog_blend),
      constant(plain.sky_horizon_blend),
    ),
    (Num(0.5), Num(0.8), Num(0.8)),
  )
  let s = @style.Style::parse(
    (
      #|{"layers": [], "sky": {"fog-color": "#000000", "atmosphere-blend": 1,
      #| "fog-ground-blend": ["interpolate", ["linear"], ["zoom"], 10, 0, 20, 1]}}
    ),
  ).sky.unwrap()
  assert_eq(constant(s.fog), Color({ r: 0.0, g: 0.0, b: 0.0, a: 1.0, }))
  assert_eq(s.fog_ground_blend.eval(15.0, @style.NoFeature::{ }), Num(0.5))
  for
    c in [
      ("{\"layers\": [], \"sky\": 1}", "sky"),
      ("{\"layers\": [], \"sky\": {\"sky-color\": \"nope\"}}", "sky.sky-color"),
    ] {
    try @style.Style::parse(c.0) catch {
      Invalid(path~, _) => assert_eq(path, c.1)
      e => fail("unexpected \{Repr(e)}")
    } noraise {
      _ => fail("expected \{c.0} to be invalid")
    }
  }
}

///|
test "fill-extrusion layers read heights, the gradient and the light" {
  let s = @style.Style::parse(
    (
      #|{"layers": [{"id": "b", "type": "fill-extrusion", "source": "v", "source-layer": "building",
      #|  "paint": {"fill-extrusion-color": "#ff0000", "fill-extrusion-opacity": 0.5,
      #|   "fill-extrusion-height": ["match", ["get", "ftCode"], 3103, 30, 8],
      #|   "fill-extrusion-vertical-gradient": false}}],
      #| "light": {"anchor": "map", "intensity": 0.3, "position": [1.5, 90, 80]}}
    ),
  )
  let l = s.layers[0]
  assert_eq(l.kind, FillExtrusion)
  assert_eq(constant(l.opacity), Num(0.5))
  let e = l.extrusion.unwrap()
  assert_eq(constant(e.base), Num(0.0))
  assert_eq(constant(e.height), Num(8.0))
  assert_true(!e.vertical_gradient)
  assert_eq(
    (s.light.viewport, constant(s.light.intensity), s.light.position),
    (false, Num(0.3), (1.5, 90.0, 80.0)),
  )
  let plain = @style.Style::parse("{\"layers\": []}").light
  assert_eq((plain.viewport, plain.position), (true, (1.15, 210.0, 30.0)))
  assert_eq(constant(plain.intensity), Num(0.5))
  for
    c in [
      (
        "\"paint\": {\"fill-extrusion-translate\": [1, 0]}}]}", "Unsupported", "layers[0].paint.fill-extrusion-translate",
      ),
      (
        "\"paint\": {\"fill-extrusion-vertical-gradient\": 1}}]}", "Invalid", "layers[0].paint.fill-extrusion-vertical-gradient",
      ),
      (
        "\"paint\": {}}], \"light\": {\"anchor\": \"up\"}}", "Invalid", "light.anchor",
      ),
      (
        "\"paint\": {}}], \"light\": {\"position\": [1, 2]}}", "Invalid", "light.position",
      ),
    ] {
    let text = "{\"layers\": [{\"id\": \"b\", \"type\": \"fill-extrusion\", " +
      c.0
    try @style.Style::parse(text) catch {
      Invalid(path~, _) => assert_eq(("Invalid", path), (c.1, c.2))
      Unsupported(path~, _) => assert_eq(("Unsupported", path), (c.1, c.2))
    } noraise {
      _ => fail("expected \{text} to be refused")
    }
  }
}
