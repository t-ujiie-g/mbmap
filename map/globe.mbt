///|
/// The globe camera of a style whose `projection` is not mercator.
fn globe_projection(style : @style.Style) -> @globe.Projection? {
  match style.projection {
    Mercator => None
    Globe => Some(Globe)
    VerticalPerspective => Some(VerticalPerspective)
  }
}

///|
/// Whether the map is drawn as a globe this frame.
fn Map::on_globe(self : Map) -> Bool {
  self.globe is Some(g) && g.is_globe()
}

///|
/// Takes the style's projection: a globe camera from `camera` (the current
/// one by default), or the mercator camera back.
fn Map::follow_projection(self : Map, camera? : @core.Camera) -> Unit {
  let t = self.transform
  match (globe_projection(self.style), self.globe) {
    (None, None) => ()
    (None, Some(g)) => {
      self.globe = None
      self.transform = t.with_camera(g.camera())
    }
    (Some(p), Some(g)) if g.projection() == p => ()
    (Some(p), _) => {
      let g = @globe.Globe::new(
        camera.unwrap_or(t.camera),
        t.width,
        t.height,
        limits=t.limits,
        projection=p,
      )
      self.globe = Some(g)
      self.transform = g.mercator()
    }
  }
}

///|
/// The camera after a gesture's frame on the globe (MapLibre's handler
/// manager): turned and zoomed about screen point (x, y), dragged by `pan`.
fn Map::globe_gesture(
  self : Map,
  g : @globe.Globe,
  x : Double,
  y : Double,
  pan~ : (Double, Double) = (0.0, 0.0),
  zoom~ : Double = 0.0,
  bearing~ : Double = 0.0,
  pitch~ : Double = 0.0,
) -> @core.Camera {
  let _ = self
  let h = g.copy()
  h.apply_controls(x, y, pan~, zoom~, bearing~, pitch~)
  h.camera()
}

///|
/// Where tile `id` goes on the globe this frame, or None when drawn flat.
fn Map::globe_tile(self : Map, id : @core.TileId) -> @render_webgl2.GlobeTile? {
  guard self.globe is Some(g) && g.is_globe() else { return None }
  let n = (1 << id.z).to_double()
  let unit = 1.0 / n / @core.TILE_EXTENT.to_double()
  let (a, b, c, d) = g.clipping_plane_of()
  Some({
    matrix: g.globe_matrix().m,
    tile: [id.x.to_double() / n, id.y.to_double() / n, unit, unit],
    plane: [a, b, c, d],
    transition: g.transition(),
    // MapLibre's globe extrude scale: a tile unit's share of the circumference,
    // corrected by the center's latitude (`getCircleRadiusCorrection`).
    angle: 2.0 *
    @math.PI /
    (n * @core.TILE_EXTENT.to_double()) *
    @globe.planet_scale(g.camera().center.lat),
    // MapLibre's `getPixelScale`, between mercator's and the globe's.
    pixel_scale: 1.0 +
    (1.0 / @globe.planet_scale(g.camera().center.lat) - 1.0) * g.transition(),
    granularity: @globe.tile_granularity(id.z),
    north: id.y == 0,
    south: id.y == (1 << id.z) - 1,
  })
}

///|
/// The tiles of a source with tiles of `tile_size` the globe view covers,
/// `round` to the nearest zoom as raster sources take it.
fn Map::globe_cover(
  self : Map,
  g : @globe.Globe,
  tile_size : Int32,
  min_zoom : Int32,
  max_zoom : Int32,
  round : Bool,
) -> Array[@core.TileId] {
  let _ = self
  g.covering_tiles(tile_size~, min_zoom~, max_zoom~, round_zoom=round)
}

///|
/// Draws a background layer's color over the globe, tile by tile (MapLibre's
/// `drawBackground` on the globe).
fn Map::draw_globe_background(self : Map, layer : @style.StyleLayer) -> Unit {
  guard self.globe is Some(g) else { return }
  let p = paint_of(layer, self.transform.camera.zoom, JsProps::none())
  let color = rgba_of(p.color)
  color[3] = color[3] * p.opacity
  for id in self.globe_cover(g, 512, 0, @core.MAX_TILE_ZOOM, false) {
    self.renderer.draw_globe_background(self.placement(id, None, 1.0), color)
  }
}

///|
/// Draws the atmosphere around the globe (MapLibre's `drawAtmosphere`).
fn Map::draw_globe_atmosphere(self : Map) -> Unit {
  guard self.globe is Some(g) && g.is_globe() else { return }
  let zoom = self.transform.camera.zoom
  let blend = number_or(
    self.style.atmosphere_blend.eval(zoom, JsProps::none()),
    0.8,
  )
  let (inverse, center, radius, altitude) = g.atmosphere()
  let blend = blend * g.transition() * altitude
  if blend == 0.0 {
    return
  }
  let light = self.style.light
  let (x, y, z) = light_direction(light.position, false, 0.0)
  let sun = g.sun({ x, y, z, }, map=!light.viewport)
  self.renderer.draw_atmosphere(
    inverse,
    (sun.x, sun.y, sun.z),
    (center.x, center.y, center.z),
    radius,
    blend,
  )
}
