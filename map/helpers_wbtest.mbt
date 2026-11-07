///|
fn style_of_json(json : Json) -> @style.Style {
  @style.Style::from_json(json, strict=false) catch {
    e => abort(e.message())
  }
}

///|
fn placement_stub() -> @render_webgl2.Placement {
  {
    matrix: @core.Mat4::identity(),
    raster_matrix: @core.Mat4::identity(),
    units_per_pixel: 1.0,
    center_depth: 1.0,
    clip: [0.0, 0.0, 8192.0, 8192.0],
    latitudes: (0.0, 0.0),
    pattern: { x: 0.0, y: 0.0, units: 1.0, height_factor: -1.0, },
  }
}

///|
/// A label set over `labels` (`LABEL_FLOATS` per label), nothing placed yet.
fn label_set(labels : @render_webgl2.JsBuffer, count : Int32) -> LabelSet {
  {
    labels,
    count,
    allow_overlap: false,
    cooperative: false,
    ignore_placement: false,
    padding: 0.0,
    anchors: [],
    line: None,
    icon: None,
    has_text: true,
    shown: FixedArray::make(count, false),
    anchor: FixedArray::make(count, -1),
    variant: FixedArray::make(count, 0),
    shifts: FixedArray::make(count * 2, 0.0),
    boxes: FixedArray::make(count * BOX_FLOATS, 0.0),
    heights: FixedArray::make(count, 0.0),
    heights_at: 0,
    round: 0,
    drawn: 0,
    changed: false,
    moved: false,
    order: [],
    sorted_at: 0.0,
  }
}

///|
test "fog_opacity is none up to 60 degrees of pitch and full from 70" {
  assert_eq(fog_opacity(0.0), 0.0)
  assert_eq(fog_opacity(60.0), 0.0)
  assert_eq(fog_opacity(65.0), 0.5)
  assert_eq(fog_opacity(70.0), 1.0)
  assert_eq(fog_opacity(85.0), 1.0)
}

///|
test "snap keeps whole units, truncated toward zero as Int16 boxes are" {
  assert_eq(snap(5.7, 2.0), 4.0)
  assert_eq(snap(6.0, 2.0), 6.0)
  assert_eq(snap(-3.0, 2.0), -2.0)
}

///|
test "pattern_tile places a tile in CSS pixels of the world at the integer zoom" {
  let t = @core.Transform::new(
    { center: { lng: 0.0, lat: 0.0, }, zoom: 3.7, bearing: 0.0, pitch: 0.0, },
    800.0,
    600.0,
  )
  let p = pattern_tile(t, @core.TileId::new(2, 1, 3).unwrap())
  // 512 px tiles: a z2 tile is 1024 px wide at zoom 3.
  assert_eq(p.x, 1024.0)
  assert_eq(p.y, 3072.0)
  assert_eq(p.units, 1024.0 / @core.TILE_EXTENT.to_double())
  assert_eq(p.height_factor, -4.0 / 4096.0)
}

///|
test "placement_order puts deeper tiles first, then by x and y" {
  let at = placement_stub()
  let draw = (z, x, y) => {
    let d : Draw = {
      id: @core.TileId::new(z, x, y).unwrap(),
      at,
      meshes: [],
      bounds: None,
    }
    d
  }
  let order = placement_order([
    draw(1, 1, 0),
    draw(2, 0, 0),
    draw(1, 0, 1),
    draw(1, 0, 0),
  ])
  assert_eq(order.map(d => (d.id.z, d.id.x, d.id.y)), [
    (2, 0, 0),
    (1, 0, 0),
    (1, 0, 1),
    (1, 1, 0),
  ])
}

///|
test "y_order sorts labels by anchor y on the turned map, the later feature first on ties" {
  let row = (x : Double, y : Double, feature : Double) => {
    let r = FixedArray::make(LABEL_FLOATS, 0.0)
    r[LABEL_X] = x
    r[LABEL_Y] = y
    r[LABEL_FEATURE] = feature
    r
  }
  let rows = [row(3.0, 10.0, 0.0), row(1.0, 5.0, 1.0), row(2.0, 10.0, 2.0)]
  let flat = FixedArray::make(rows.length() * LABEL_FLOATS, 0.0)
  for i, r in rows {
    for k in 0..<LABEL_FLOATS {
      flat[i * LABEL_FLOATS + k] = r[k]
    }
  }
  let s = label_set(f32_buffer(flat), 3)
  assert_eq(y_order(s, 0.0), [1, 2, 0])
  // Turned a quarter, the map's y runs along the anchors' x.
  assert_eq(y_order(s, @math.PI / 2.0), [1, 2, 0])
  assert_eq(y_order(s, -@math.PI / 2.0), [0, 2, 1])
}

///|
test "sorts_by_y: viewport-y, or auto without a sort key, when labels may overlap" {
  let layer = (layout : Json) => {
    let style = style_of_json({
      "version": 8,
      "sources": { "s": { "type": "geojson", "data": null } },
      "layers": [
        { "id": "l", "type": "symbol", "source": "s", "layout": layout },
      ],
    })
    style.layers[0]
  }
  assert_true(
    sorts_by_y(layer({ "text-field": "a", "text-allow-overlap": true })),
  )
  assert_false(sorts_by_y(layer({ "text-field": "a" })))
  assert_false(
    sorts_by_y(
      layer({
        "text-field": "a",
        "text-allow-overlap": true,
        "symbol-sort-key": 1,
      }),
    ),
  )
  assert_true(
    sorts_by_y(
      layer({
        "text-field": "a",
        "text-ignore-placement": true,
        "symbol-sort-key": 1,
        "symbol-z-order": "viewport-y",
      }),
    ),
  )
}

///|
test "draws_from: a source used by a layer other than the background, or by the terrain" {
  let style = style_of_json({
    "version": 8,
    "sources": {
      "v": { "type": "vector", "tiles": ["https://example.com/{z}/{x}/{y}"] },
      "dem": {
        "type": "raster-dem",
        "tiles": ["https://example.com/{z}/{x}/{y}.png"],
      },
      "unused": {
        "type": "vector",
        "tiles": ["https://example.com/{z}/{x}/{y}"],
      },
    },
    "terrain": { "source": "dem" },
    "layers": [
      { "id": "bg", "type": "background" },
      { "id": "f", "type": "fill", "source": "v", "source-layer": "a" },
    ],
  })
  assert_true(draws_from(style, "v"))
  assert_true(draws_from(style, "dem"))
  assert_false(draws_from(style, "unused"))
}

///|
test "same_layers keeps tiles while paint changes, not when a filter does" {
  let style = (filter : Json, color : String) => {
    style_of_json({
      "version": 8,
      "sources": {
        "v": { "type": "vector", "tiles": ["https://example.com/{z}/{x}/{y}"] },
        "r": { "type": "raster", "tiles": ["https://example.com/{z}/{x}/{y}"] },
      },
      "layers": [
        {
          "id": "f",
          "type": "fill",
          "source": "v",
          "source-layer": "a",
          "filter": filter,
          "paint": { "fill-color": color },
        },
        { "id": "r", "type": "raster", "source": "r" },
      ],
    })
  }
  let a = style(["==", ["get", "k"], 1], "red")
  let src = a.sources.iter().find_first(s => s.id == "v").unwrap()
  let raster = a.sources.iter().find_first(s => s.id == "r").unwrap()
  assert_true(same_layers(src, a, style(["==", ["get", "k"], 1], "blue")))
  let refiltered = style(["==", ["get", "k"], 2], "red")
  assert_false(same_layers(src, a, refiltered))
  assert_true(same_layers(raster, a, refiltered))
}
