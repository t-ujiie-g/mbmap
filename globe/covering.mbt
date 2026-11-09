// MapLibre GL JS 6.16.0's coveringTiles for the vertical perspective: src/geo/projection/
// covering_tiles.ts, globe_covering_tiles_details_provider.ts and mercator_utils.ts's
// cameraMercatorCoordinate, BSD-3-Clause, Copyright (c) 2020 MapLibre contributors; see NOTICE.

///|
fn distance_simple(point : Double, tile : Double, size : Double) -> Double {
  let delta = point - tile
  if delta < 0.0 {
    -delta
  } else {
    @cmp.maximum(0.0, delta - size)
  }
}

///|
fn distance_wrap_x(
  px : Double,
  py : Double,
  tx : Double,
  ty : Double,
  size : Double,
) -> Double {
  let dx = px - tx
  let distance_x = if dx < 0.0 {
    @cmp.minimum(-dx, 1.0 + dx - size)
  } else if dx > size {
    @cmp.minimum(@cmp.maximum(dx - size, 0.0), 1.0 - dx)
  } else {
    0.0
  }
  @cmp.maximum(distance_x, distance_simple(py, ty, size))
}

///|
/// Mercator distance from (px, py) to tile `z/x/y` across the antimeridian
/// and the poles (`distanceToTile2d` of the globe).
fn tile_distance(
  px : Double,
  py : Double,
  z : Int32,
  x : Int32,
  y : Int32,
) -> Double {
  let scale = (1 << z).to_double()
  let size = 1.0 / scale
  let tx = x.to_double() / scale
  let ty = y.to_double() / scale
  let mut d = 2.0
  d = @cmp.minimum(d, distance_wrap_x(px, py, tx, ty, size))
  d = @cmp.minimum(d, distance_wrap_x(px, py, tx + 0.5, -ty - size, size))
  @cmp.minimum(
    d,
    distance_wrap_x(px, py, tx + 0.5, 1.0 + 1.0 - ty - size, size),
  )
}

///|
/// MapLibre's `maxMercatorHorizonAngle`, in degrees.
const MAX_HORIZON_ANGLE : Double = 89.25

///|
/// Midpoint integral of `cos(x)^p` from `x1` to `x2` (`integralOfCosXByP`).
fn integral_cos_pow(p : Double, x1 : Double, x2 : Double) -> Double {
  let dx = (x2 - x1) / 10.0
  let mut sum = 0.0
  for i in 0..<10 {
    let x = x1 + (i.to_double() + 0.5) / 10.0 * (x2 - x1)
    sum += dx * @math.pow(@math.cos(x), p)
  }
  sum
}

///|
/// The zoom a tile `d2` mercator units away wants at high pitch
/// (`defaultCalculateTileZoom`: 9.314 zoom levels on screen, a tile count
/// ratio of 3).
fn tile_zoom(
  center_zoom : Double,
  d2 : Double,
  dz : Double,
  center_d3 : Double,
  fov : Double,
) -> Double {
  let behavior = 2.0 *
    (
      (9.314 - 1.0) /
      scale_zoom(
        @math.cos(@core.radians(MAX_HORIZON_ANGLE - fov)) /
        @math.cos(@core.radians(MAX_HORIZON_ANGLE)),
      ) -
      1.0
    )
  let center_pitch = @math.acos(dz / center_d3)
  let pitch0 = 2.0 *
    integral_cos_pow(behavior - 1.0, 0.0, @core.radians(fov / 2.0))
  let highest = @cmp.minimum(
    @core.radians(MAX_HORIZON_ANGLE),
    center_pitch + @core.radians(fov / 2.0),
  )
  let lowest = @cmp.minimum(highest, center_pitch - @core.radians(fov / 2.0))
  let count = integral_cos_pow(behavior - 1.0, lowest, highest)
  let tile_pitch = @math.atan(d2 / dz)
  let d3 = @core.js_hypot(d2, dz)
  let mut z = center_zoom +
    scale_zoom(
      center_d3 / d3 / @cmp.maximum(0.5, @math.cos(@core.radians(fov / 2.0))),
    )
  z += behavior * scale_zoom(@math.cos(tile_pitch)) / 2.0
  z -= scale_zoom(@cmp.maximum(1.0, count / pitch0 / 3.0)) / 2.0
  z
}

///|
/// The canonical tiles of a `tile_size` source covering the view, nearest the
/// center first (MapLibre's `coveringTiles`, no terrain); `max_zoom` defaults
/// to the camera's. Only valid while `is_globe()`.
pub fn Globe::covering_tiles(
  self : Globe,
  tile_size~ : Int32 = 512,
  min_zoom~ : Int32 = 0,
  max_zoom? : Int32,
  round_zoom~ : Bool = false,
) -> Array[@core.TileId] {
  let frustum = self.frustum()
  let vp = self.vp()
  let horizon : Plane = { n: vp.plane, d: vp.plane_d, }
  let max_lat = @core.MAX_VALID_LATITUDE
  let lng = self.center.lng
  let lat = clamp(self.center.lat, -max_lat, max_lat)
  let pitch = self.pitch / @math.PI * 180.0
  let bearing = self.bearing / @math.PI * 180.0
  let fov = @core.FIELD_OF_VIEW / @math.PI * 180.0
  let units_per_meter = 1.0 /
    (2.0 * @math.PI * @core.EARTH_RADIUS * @math.cos(lat * @math.PI / 180.0))
  let distance = self.center_distance() / (units_per_meter * self.world_size())
  let d_merc = distance * units_per_meter
  let (pr, br) = (@core.radians(pitch), @core.radians(bearing))
  let h = @math.sin(pr)
  let center_x = (180.0 + lng) / 360.0
  let center_y = @core.LngLat::{ lng: 0.0, lat, }.to_mercator().y
  let cam_x = center_x + d_merc * -(h * @math.sin(br))
  let cam_y = center_y + d_merc * -(-h * @math.cos(br))
  let cam_z = 0.0 + d_merc * @math.cos(-pr)
  let horizon_gap = MAX_HORIZON_ANGLE - pitch - fov / 2.0
  let near_horizon = clamp((15.0 - horizon_gap) / 15.0, 0.0, 1.0)
  let top = near_horizon * 500.0 / @core.EARTH_RADIUS + 1.0
  let level = self.zoom + scale_zoom(512.0 / tile_size.to_double())
  let pick = if round_zoom { @core.js_round } else { Double::floor }
  let desired = @cmp.maximum(0.0, pick(level))
  let variable = desired > 4.0
  let max_z = match max_zoom {
    Some(z) => z.to_double()
    None => self.limits.max_zoom
  }
  let min_z = min_zoom.to_double()
  let nominal = @cmp.minimum(@cmp.maximum(0.0, desired), max_z)
  let tiles = @math.pow(2.0, nominal)
  let center_px = tiles * center_x
  let center_py = tiles * center_y
  let dz = (0.0 - cam_z).abs()
  let center_d3 = @core.js_hypot(
    @core.js_hypot(center_x - cam_x, center_y - cam_y),
    dz,
  )
  let stack : Array[(Int32, Int32, Int32, Bool)] = [(0, 0, 0, false)]
  let found : Array[@core.TileId] = []
  let keys : Array[Double] = []
  while stack.pop() is Some((z, x, y, parent_inside)) {
    let mut inside = parent_inside
    if !inside {
      match tile_volume(z, x, y, top).visibility(frustum, horizon) {
        Outside => continue
        hit => inside = hit == Inside
      }
    }
    let mut want = desired
    if variable {
      let d2 = tile_distance(cam_x, cam_y, z, x, y)
      want = tile_zoom(level, d2, dz, center_d3, fov)
    }
    let want = @cmp.minimum(@cmp.maximum(0.0, pick(want)), max_z)
    if z.to_double() >= want {
      if z.to_double() < min_z {
        continue
      }
      let dx = center_px - 0.5 - x.to_double()
      let dy = center_py - 0.5 - y.to_double()
      found.push(@core.TileId::new(z, x, y).unwrap())
      keys.push(dx * dx + dy * dy)
      continue
    }
    for i in 0..<4 {
      stack.push((z + 1, (x << 1) + i % 2, (y << 1) + (i >> 1), inside))
    }
  }
  let order = @core.stable_order(keys[:])
  Array::makei(order.length(), i => found[order[i]])
}
