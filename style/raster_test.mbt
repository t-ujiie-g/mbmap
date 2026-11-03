///|
fn raster_style(source : String, paint : String) -> @style.Style raise {
  @style.Style::parse(
    "{\"sources\": {\"r\": \{source}}, \"layers\": [{\"id\": \"r\", \"type\": \"raster\", \"source\": \"r\", \"paint\": \{paint}}]}",
  )
}

///|
test "raster sources and layers take MapLibre's defaults" {
  let s = raster_style(
    "{\"type\": \"raster\", \"tiles\": [\"https://x/{z}/{x}/{y}.png\"]}", "{\"raster-opacity\": 0.5, \"raster-resampling\": \"nearest\"}",
  )
  assert_eq((s.sources[0].kind, s.sources[0].tile_size), (Raster, 512))
  let r = s.layers[0].raster.unwrap()
  assert_eq(s.layers[0].kind, Raster)
  assert_eq(r.opacity, Lit(Num(0.5)))
  assert_eq(
    (r.hue_rotate, r.brightness_min, r.brightness_max, r.saturation, r.contrast),
    (Lit(Num(0.0)), Lit(Num(0.0)), Lit(Num(1.0)), Lit(Num(0.0)), Lit(Num(0.0))),
  )
  assert_true(r.nearest)
  try
    raster_style(
      "{\"type\": \"raster\", \"tiles\": [\"https://x/{z}/{x}/{y}.png\"]}", "{\"raster-resampling\": \"cubic\"}",
    )
  catch {
    @style.Invalid(path~, why) =>
      assert_eq(
        (path, why),
        ("layers[0].paint.raster-resampling", "unknown resampling cubic"),
      )
    _ => fail("expected Invalid")
  } noraise {
    _ => fail("expected an error")
  }
}

///|
test "bounds limit the tiles a source covers; scheme and PMTiles templates are read" {
  let s = raster_style(
      "{\"type\": \"raster\", \"tiles\": [\"pmtiles://https://x/a.pmtiles/{z}/{x}/{y}\"], \"bounds\": [139.7, 35.6, 139.8, 35.7], \"scheme\": \"tms\"}",
      "{}",
    ).sources[0]
  assert_true(s.tms)
  // z14 tiles around Tokyo Station are in, one far east is out; z0 holds everything.
  assert_true(s.covers(14, 14552, 6451))
  assert_false(s.covers(14, 14700, 6451))
  assert_true(s.covers(0, 0, 0))
  let world = raster_style(
      "{\"type\": \"raster\", \"tiles\": [\"https://x/{z}/{x}/{y}.png\"], \"bounds\": [1, 2]}",
      "{}",
    ).sources[0]
  assert_eq((world.bounds, world.tms), (None, false))
  for
    bad in [
      "{\"type\": \"raster\", \"tiles\": [\"pmtiles://file:///a.pmtiles/{z}/{x}/{y}\"]}",
      "{\"type\": \"raster\", \"tiles\": [\"https://x/{z}/{x}/{y}.png\"], \"scheme\": \"wms\"}",
    ] {
    try raster_style(bad, "{}") catch {
      _ => ()
    } noraise {
      _ => fail("expected \{bad} to be refused")
    }
  }
}

///|
test "image, video and canvas sources are pictures placed by four corners" {
  let corners = "[[139.7, 35.7], [139.8, 35.7], [139.8, 35.6], [139.7, 35.6]]"
  for
    source in [
      "{\"type\": \"image\", \"url\": \"a.png\", \"coordinates\": \{corners}}",
      "{\"type\": \"video\", \"urls\": [\"a.mp4\"], \"coordinates\": \{corners}}",
      "{\"type\": \"canvas\", \"canvas\": \"c\", \"coordinates\": \{corners}}",
    ] {
    let s = raster_style(source, "{}").sources[0]
    assert_eq((s.kind, s.tiles), (Image, []))
  }
}
