// MapLibre GL JS 6.16.0's symbol helpers of src/geo/projection/vertical_perspective_transform.ts and
// globe_transform.ts, BSD-3-Clause, Copyright (c) 2020 MapLibre contributors; see NOTICE.

///|
/// MapLibre's `projectTileCoordinates` on the globe: point (x, y) of tile `id`
/// on the ground in clip space (x, y, w), and whether the globe hides it.
pub fn Globe::project_tile(
  self : Globe,
  x : Double,
  y : Double,
  id : @core.TileId,
) -> (Double, Double, Double, Bool) {
  let v = tile_vector(x, y, id.z, id.x, id.y)
  let vp = self.vp()
  let (cx, cy, _, cw) = vp.view.apply(v.x, v.y, v.z, 1.0)
  let side = vp.plane.x * v.x + vp.plane.y * v.y + vp.plane.z * v.z + vp.plane_d
  (cx, cy, cw, side < 0.0)
}

///|
/// MapLibre's `getCircleRadiusCorrection`: how much a parallel shrinks at the
/// center while the globe is drawn, 1 otherwise.
pub fn Globe::radius_correction(self : Globe) -> Double {
  if self.is_globe() {
    planet_scale(self.center.lat)
  } else {
    1.0
  }
}

///|
/// MapLibre's `getPitchedTextCorrection` at row `y` of tile `id`: how much
/// larger text lying on the globe is there than at the center, toward 1 as
/// the globe turns into mercator.
pub fn Globe::pitched_text_correction(
  self : Globe,
  y : Double,
  id : @core.TileId,
) -> Double {
  let scale = 1.0 / (1 << id.z).to_double()
  let my = y / @core.TILE_EXTENT.to_double() * scale + id.y.to_double() * scale
  let lat = 2.0 * @math.atan(@math.exp(@math.PI - my * @math.PI * 2.0)) -
    @math.PI * 0.5
  let vertical = planet_scale(self.center.lat) / @math.cos(lat)
  lerp(1.0, vertical, self.globeness)
}

///|
/// The world copy MapLibre's globe covering gives tile `id` (its `getWrap`):
/// -1, 0 or 1, whichever puts it nearest the center's longitude.
pub fn Globe::tile_wrap(self : Globe, id : @core.TileId) -> Int32 {
  let scale = (1 << id.z).to_double()
  let size = 1.0 / scale
  let x = id.x.to_double() / scale
  let center = (180.0 + self.center.lng) / 360.0
  let distance = (tile : Double) => {
    let delta = center - tile
    if delta < 0.0 {
      -delta
    } else {
      @cmp.maximum(0.0, delta - size)
    }
  }
  let current = distance(x)
  let left = distance(x - 1.0)
  let right = distance(x + 1.0)
  let smallest = @cmp.minimum(current, @cmp.minimum(left, right))
  if smallest == right {
    1
  } else if smallest == left {
    -1
  } else {
    0
  }
}
