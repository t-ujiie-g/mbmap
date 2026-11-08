///|
/// Point (x, y) at height `z` of tile `id` drawn by `at` in clip space (x, y, w) and whether the
/// globe hides it, as MapLibre's `projectTileCoordinates`: on the globe its own projection, not the
/// blend the shaders draw on the way to mercator.
fn Map::label_clip(
  self : Map,
  at : @render_webgl2.Placement,
  id : @core.TileId,
  x : Double,
  y : Double,
  z : Double,
) -> (Double, Double, Double, Bool) {
  match self.globe {
    Some(g) if g.is_globe() => g.project_tile(x, y, id)
    _ => {
      let (cx, cy, _, cw) = at.matrix.apply(x, y, z, 1.0)
      (cx, cy, cw, false)
    }
  }
}

///|
/// How much larger text lying on the map is at row `y` of tile `id` than at
/// the center (MapLibre's `getPitchedTextCorrection`): 1 off the globe.
fn Map::text_correction(self : Map, id : @core.TileId, y : Double) -> Double {
  match self.globe {
    Some(g) => g.pitched_text_correction(y, id)
    None => 1.0
  }
}
