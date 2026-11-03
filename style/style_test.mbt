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
  assert_eq(s.sources.map(x => x.kind), [Vector, Image])
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
        #|{"layers": [{"id": "a", "type": "line", "paint": {"line-width": ["accumulated"]}}]}
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
  assert_eq(s.source("img").map(x => x.kind), Some(Image))
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
    constant(h.shadow[0]),
    Color({ r: 71.0 / 255.0, g: 59.0 / 255.0, b: 36.0 / 255.0, a: 1.0, }),
  )
  let d = s.layers[1].hillshade.unwrap()
  assert_eq(
    (constant(d.direction[0]), constant(d.exaggeration), d.viewport),
    (Num(335.0), Num(0.5), true),
  )
  assert_eq(
    constant(d.highlight[0]),
    Color({ r: 1.0, g: 1.0, b: 1.0, a: 1.0, }),
  )
  assert_eq(constant(d.altitude[0]), Num(45.0))
  assert_true(d.shading is Standard && !d.nearest)
}

///|
test "unknown DEM encodings, odd tile sizes, hillshade methods and resampling are refused" {
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
      "{\"layers\": [{\"id\": \"h\", \"type\": \"hillshade\", \"paint\": {\"hillshade-method\": \"sketch\"}}]}",
      "layers[0].paint.hillshade-method",
    ),
    (
      "{\"layers\": [{\"id\": \"h\", \"type\": \"hillshade\", \"paint\": {\"resampling\": \"cubic\"}}]}",
      "layers[0].paint.resampling",
    ),
    (
      "{\"layers\": [{\"id\": \"h\", \"type\": \"hillshade\", \"paint\": {\"hillshade-illumination-direction\": []}}]}",
      "layers[0].paint.hillshade-illumination-direction",
    ),
    (
      "{\"layers\": [{\"id\": \"h\", \"type\": \"hillshade\", \"paint\": {\"hillshade-shadow-color\": [\"#000\", \"nope\"]}}]}",
      "layers[0].paint.hillshade-shadow-color[1]",
    ),
    (
      "{\"layers\": [{\"id\": \"h\", \"type\": \"hillshade\", \"paint\": {\"hillshade-highlight-color\": [\"#000\", \"#111\", \"#222\", \"#333\", \"#444\", \"#555\", \"#666\", \"#777\", \"#888\"]}}]}",
      "layers[0].paint.hillshade-highlight-color",
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

///|
test "hillshade methods, lists of lights, altitudes and resampling" {
  let s = @style.Style::parse(
    (
      #|{"sources": {"dem": {"type": "raster-dem", "tiles": ["t"]}},
      #| "layers": [
      #|  {"id": "m", "type": "hillshade", "source": "dem",
      #|   "paint": {"hillshade-method": "multidirectional",
      #|             "hillshade-illumination-direction": [270, 315, 0],
      #|             "hillshade-illumination-altitude": 30,
      #|             "hillshade-highlight-color": ["#ff0000", "rgba(0, 255, 0, 0.5)"],
      #|             "hillshade-shadow-color": ["interpolate", ["linear"], ["zoom"], 10, "#000000", 14, "#ffffff"],
      #|             "resampling": "nearest"}},
      #|  {"id": "b", "type": "hillshade", "source": "dem", "paint": {"hillshade-method": "basic"}},
      #|  {"id": "c", "type": "hillshade", "source": "dem", "paint": {"hillshade-method": "combined"}},
      #|  {"id": "i", "type": "hillshade", "source": "dem", "paint": {"hillshade-method": "igor"}}
      #|]}
    ),
  )
  let m = s.layers[0].hillshade.unwrap()
  assert_true(m.shading is Multidirectional && m.nearest)
  assert_eq(m.direction.map(constant), [Num(270.0), Num(315.0), Num(0.0)])
  assert_eq(m.altitude.map(constant), [Num(30.0)])
  assert_eq(m.highlight.map(constant), [
    Color({ r: 1.0, g: 0.0, b: 0.0, a: 1.0, }),
    Color({ r: 0.0, g: 1.0, b: 0.0, a: 0.5, }),
  ])
  assert_eq(m.shadow.length(), 1)
  assert_eq(
    m.shadow[0].eval(14.0, @style.NoFeature::{ }),
    Color({ r: 1.0, g: 1.0, b: 1.0, a: 1.0, }),
  )
  assert_true(s.layers[1].hillshade.unwrap().shading is Basic)
  assert_true(s.layers[2].hillshade.unwrap().shading is Combined)
  assert_true(s.layers[3].hillshade.unwrap().shading is Igor)
}

///|
test "raster layers sample the nearest pixel for either resampling property" {
  let s = @style.Style::parse(
    (
      #|{"sources": {"r": {"type": "raster", "tiles": ["t"]}},
      #| "layers": [
      #|  {"id": "a", "type": "raster", "source": "r", "paint": {"resampling": "nearest"}},
      #|  {"id": "b", "type": "raster", "source": "r", "paint": {"raster-resampling": "nearest"}},
      #|  {"id": "c", "type": "raster", "source": "r", "paint": {"resampling": "linear"}}
      #|]}
    ),
  )
  assert_eq(s.layers.map(l => l.raster.unwrap().nearest), [true, true, false])
}

///|
test "color relief layers keep their ramp's elevation stops" {
  let s = @style.Style::parse(
    (
      #|{"sources": {"dem": {"type": "raster-dem", "tiles": ["t"], "encoding": "terrarium"}},
      #| "layers": [
      #|  {"id": "r", "type": "color-relief", "source": "dem",
      #|   "paint": {"color-relief-color": ["interpolate", ["linear"], ["elevation"], 0, "#2b83ba", 1000, "#ffffbf", 3776, "#d7191c"],
      #|             "color-relief-opacity": ["interpolate", ["linear"], ["zoom"], 10, 1, 14, 0.5],
      #|             "resampling": "nearest"}},
      #|  {"id": "s", "type": "color-relief", "source": "dem",
      #|   "paint": {"color-relief-color": ["step", ["elevation"], "#000000", 100, "#ffffff"]}},
      #|  {"id": "d", "type": "color-relief", "source": "dem"}
      #|]}
    ),
  )
  let r = s.layers[0]
  assert_eq(r.kind, ColorRelief)
  assert_eq(r.relief.unwrap().stops, [0.0, 1000.0, 3776.0])
  assert_true(r.relief.unwrap().nearest)
  assert_eq(r.opacity.eval(14.0, @style.NoFeature::{ }), Num(0.5))
  assert_eq(s.layers[1].relief.unwrap().stops, [])
  assert_eq(s.layers[2].relief.unwrap().stops, [])
  assert_eq(r.color.eval(0.0, @style.NoFeature::{ }), Failed)
}

///|
test "elevation is allowed in color-relief-color only, and zoom is not" {
  let cases = [
    (
      (
        #|{"layers": [{"id": "f", "type": "fill", "source": "s", "paint": {"fill-opacity": ["/", ["elevation"], 1000]}}]}
      ),
      "layers[0]",
    ),
    (
      (
        #|{"layers": [{"id": "r", "type": "color-relief", "source": "s", "paint": {"color-relief-opacity": ["/", ["elevation"], 1000]}}]}
      ),
      "layers[0]",
    ),
    (
      (
        #|{"layers": [{"id": "r", "type": "color-relief", "source": "s", "paint": {"color-relief-color": ["interpolate", ["linear"], ["zoom"], 0, "#000", 10, "#fff"]}}]}
      ),
      "layers[0].paint.color-relief-color",
    ),
    (
      (
        #|{"layers": [{"id": "r", "type": "color-relief", "source": "s", "paint": {"color-relief-color": ["interpolate", ["linear"], ["get", "h"], 0, "#000", 10, "#fff"]}}]}
      ),
      "layers[0].paint.color-relief-color",
    ),
  ]
  for c in cases {
    try @style.Style::parse(c.0) catch {
      Invalid(path~, _) => assert_eq(path, c.1)
      e => fail("\{c.1}: \{e.message()}")
    } noraise {
      _ => fail("expected \{c.1} to be refused")
    }
  }
}
