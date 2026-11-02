// The camera kept in bounds as MapLibre GL JS 6.16.0's `defaultConstrain` (src/geo/projection/
// mercator_camera_helper.ts), BSD-3-Clause, Copyright (c) 2020 MapLibre contributors; see NOTICE.

///|
/// `camera` kept to `limits` on a `width` x `height` viewport, as MapLibre's
/// `defaultConstrain` (no padding): zoom and pitch clamped, bearing and longitude
/// wrapped, the center moved or the zoom raised to keep the view in bounds.
fn constrain(
  camera : Camera,
  limits : Limits,
  width : Double,
  height : Double,
) -> Camera {
  let zoom = @cmp.maximum(
    limits.min_zoom,
    @cmp.minimum(limits.max_zoom, camera.zoom),
  )
  let camera = {
    ..camera,
    zoom,
    bearing: wrap180(camera.bearing),
    pitch: @cmp.maximum(
      limits.min_pitch,
      @cmp.minimum(limits.max_pitch, camera.pitch),
    ),
  }
  // MapLibre sets the zoom before the center and constrains each time: the
  // zoom rises until the ranges fill the view, then the center is kept in.
  let clamp = (z : Double) => {
    @cmp.maximum(limits.min_zoom, @cmp.minimum(limits.max_zoom, z))
  }
  let mut zoom = zoom
  for _ in 0..<3 {
    let (_, z) = constrain_center(camera.center, zoom, limits, width, height)
    if clamp(z) == zoom {
      break
    }
    zoom = clamp(z)
  }
  let (center, _) = constrain_center(camera.center, zoom, limits, width, height)
  { ..camera, center: { lng: wrap180(center.lng), lat: center.lat, }, zoom, }
}

///|
/// `camera` after one pass of MapLibre's constraint (`applyConstrain`), as
/// its moves take their end point: a zoom raised to fit a range centers that
/// range and leaves the other axis alone.
fn constrain_once(
  camera : Camera,
  limits : Limits,
  width : Double,
  height : Double,
) -> Camera {
  let zoom = @cmp.maximum(
    limits.min_zoom,
    @cmp.minimum(limits.max_zoom, camera.zoom),
  )
  let (center, zoom) = constrain_center(
    camera.center,
    zoom,
    limits,
    width,
    height,
  )
  { ..camera, center: { lng: wrap180(center.lng), lat: center.lat, }, zoom, }
}

///|
/// The latitude limit MapLibre keeps the view to (`MAX_VALID_LATITUDE`,
/// `MAX_LATITUDE` rounded).
const MAX_VALID_LATITUDE : Double = 85.051129

///|
fn constrain_center(
  center : LngLat,
  zoom : Double,
  limits : Limits,
  width : Double,
  height : Double,
) -> (LngLat, Double) {
  let world = TILE_SIZE * @math.pow(2.0, zoom)
  let (south, north, lng_range) = match limits.bounds {
    Some(b) => (b.south, b.north, Some((b.west, b.east)))
    None => (-MAX_VALID_LATITUDE, MAX_VALID_LATITUDE, None)
  }
  let min_y = mercator_y_from_lat(north) * world
  let max_y = mercator_y_from_lat(south) * world
  let scale_y = if max_y - min_y < height {
    height / (max_y - min_y)
  } else {
    0.0
  }
  let (min_x, max_x, scale_x) = match lng_range {
    Some((west, east)) => {
      let min_x = wrap_range(mercator_x_from_lng(west) * world, 0.0, world)
      let max_x = wrap_range(mercator_x_from_lng(east) * world, 0.0, world)
      let max_x = if max_x < min_x { max_x + world } else { max_x }
      (
        min_x,
        max_x,
        if max_x - min_x < width {
          width / (max_x - min_x)
        } else {
          0.0
        },
      )
    }
    None => (0.0, world, 0.0)
  }
  let x = mercator_x_from_lng(center.lng) * world
  let y = mercator_y_from_lat(center.lat) * world
  let scale = @cmp.maximum(scale_x, scale_y)
  if scale > 0.0 {
    let m : MercatorCoord = {
      x: (if scale_x > 0.0 { (max_x + min_x) / 2.0 } else { x }) / world,
      y: (if scale_y > 0.0 { (max_y + min_y) / 2.0 } else { y }) / world,
    }
    let c = m.to_lnglat()
    return ({ lng: wrap180(c.lng), lat: c.lat, }, zoom + @math.log2(scale))
  }
  let mut new_y = y
  if y - height / 2.0 < min_y {
    new_y = min_y + height / 2.0
  }
  if y + height / 2.0 > max_y {
    new_y = max_y - height / 2.0
  }
  let mut new_x = x
  if lng_range is Some(_) {
    let mid = (min_x + max_x) / 2.0
    let wrapped = wrap_range(x, mid - world / 2.0, mid + world / 2.0)
    if wrapped - width / 2.0 < min_x {
      new_x = min_x + width / 2.0
    }
    if wrapped + width / 2.0 > max_x {
      new_x = max_x - width / 2.0
    }
  }
  if new_x == x && new_y == y {
    return (center, zoom)
  }
  let c = ({ x: new_x / world, y: new_y / world, } : MercatorCoord).to_lnglat()
  ({ lng: wrap180(c.lng), lat: c.lat, }, zoom)
}

///|
/// `v` in (`min`, `max`] (MapLibre's `wrap`).
fn wrap_range(v : Double, min : Double, max : Double) -> Double {
  // Values already in range stay exact (the modulo below would round them).
  if v > min && v <= max {
    return v
  }
  let d = max - min
  let w = ((v - min) % d + d) % d + min
  if w == min {
    max
  } else {
    w
  }
}

///|
/// `v` in (-180, 180], so longitudes and bearings stay bounded.
fn wrap180(v : Double) -> Double {
  wrap_range(v, -180.0, 180.0)
}

///|
fn finite(camera : Camera) -> Bool {
  let ok = (x : Double) => !x.is_nan() && !x.is_inf()
  ok(camera.zoom) &&
  ok(camera.center.lng) &&
  ok(camera.center.lat) &&
  ok(camera.bearing) &&
  ok(camera.pitch)
}
