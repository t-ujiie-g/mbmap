// MapLibre GL JS 6.16.0's coveringTiles for the vertical perspective: src/geo/projection/covering_tiles.ts,
// globe_covering_tiles_details_provider.ts, mercator_utils.ts's cameraMercatorCoordinate and
// src/util/primitives/ (frustum.ts, convex_volume.ts), BSD-3-Clause, Copyright (c) 2020 MapLibre contributors; see NOTICE.

///|
/// A plane `n·p + d = 0`; points with `n·p + d >= 0` are inside.
priv struct Plane {
  n : Vec3
  d : Double
}

///|
fn Plane::distance(self : Plane, p : Vec3) -> Double {
  self.n.dot(p) + self.d
}

///|
/// A convex volume given by its corner points and the planes bounding it
/// (MapLibre's `Frustum` and `ConvexVolume` alike).
priv struct Volume {
  points : Array[Vec3]
  planes : Array[Plane]
}

///|
/// MapLibre's `IntersectionResult`.
#derive(Eq)
priv enum Hit {
  Outside
  Partial
  Inside
}

///|
/// `ConvexVolume.intersectsFrustum`.
fn Volume::meets_frustum(self : Volume, frustum : Volume) -> Hit {
  let mut inside = true
  for plane in frustum.planes {
    let passed = self.passing(plane)
    if passed == 0 {
      return Outside
    }
    if passed < self.points.length() {
      inside = false
    }
  }
  if inside {
    return Inside
  }
  for plane in self.planes {
    if frustum.passing(plane) == 0 {
      return Outside
    }
  }
  Partial
}

///|
fn Volume::passing(self : Volume, plane : Plane) -> Int32 {
  let mut n = 0
  for p in self.points {
    if plane.distance(p) >= 0.0 {
      n += 1
    }
  }
  n
}

///|
/// `ConvexVolume.intersectsPlane`.
fn Volume::meets_plane(self : Volume, plane : Plane) -> Hit {
  let passed = self.passing(plane)
  if passed == self.points.length() {
    Inside
  } else if passed == 0 {
    Outside
  } else {
    Partial
  }
}

///|
/// `isTileVisible` with the horizon plane.
fn Volume::visibility(self : Volume, frustum : Volume, horizon : Plane) -> Hit {
  let f = self.meets_frustum(frustum)
  if f == Outside {
    return Outside
  }
  let p = self.meets_plane(horizon)
  if p == Outside {
    Outside
  } else if f == Inside && p == Inside {
    Inside
  } else {
    Partial
  }
}

///|
/// `ConvexVolume.fromAabb`.
fn Volume::of_box(min : Vec3, max : Vec3) -> Volume {
  let points = Array::makei(8, i => {
    (
      {
        x: if (i & 1) == 1 {
          max.x
        } else {
          min.x
        },
        y: if ((i >> 1) & 1) == 1 {
          max.y
        } else {
          min.y
        },
        z: if ((i >> 2) & 1) == 1 {
          max.z
        } else {
          min.z
        },
      } : Vec3)
  })
  let planes : Array[Plane] = [
    { n: { x: -1.0, y: 0.0, z: 0.0, }, d: max.x, },
    { n: { x: 1.0, y: 0.0, z: 0.0, }, d: -min.x, },
    { n: { x: 0.0, y: -1.0, z: 0.0, }, d: max.y, },
    { n: { x: 0.0, y: 1.0, z: 0.0, }, d: -min.y, },
    { n: { x: 0.0, y: 0.0, z: -1.0, }, d: max.z, },
    { n: { x: 0.0, y: 0.0, z: 1.0, }, d: -min.z, },
  ]
  { points, planes, }
}

///|
/// The plane through `a`, `b`, `c` facing along `(a - b) x (c - b)`.
fn plane_through(a : Vec3, b : Vec3, c : Vec3) -> Plane {
  let n = a.sub(b).cross(c.sub(b)).normalize()
  { n, d: -n.dot(b), }
}

///|
/// `threePlaneIntersection` (the planes' normals of unit length).
fn meet(p0 : Plane, p1 : Plane, p2 : Plane) -> Vec3 {
  let (a, b, c) = (p0.n, p1.n, p2.n)
  let det = a.x * (c.z * b.y - b.z * c.y) +
    a.y * (-c.z * b.x + b.z * c.x) +
    a.z * (c.y * b.x - b.y * c.x)
  b
  .cross(c)
  .scale(-p0.d)
  .add_scaled(c.cross(a), -p1.d)
  .add_scaled(a.cross(b), -p2.d)
  .scale(1.0 / det)
}

///|
/// The view frustum on the unit sphere's scale, its far plane brought in to
/// the horizon (`Frustum.fromInvProjectionMatrix` as `_calcMatrices` calls it:
/// z flipped, near and far swapped, from the inverse `mat4.clone` rounds to
/// Float32).
fn Globe::frustum(self : Globe) -> Volume {
  let vp = self.vp()
  let corners = [
    (-1.0, 1.0, -1.0),
    (1.0, 1.0, -1.0),
    (1.0, -1.0, -1.0),
    (-1.0, -1.0, -1.0),
    (-1.0, 1.0, 1.0),
    (1.0, 1.0, 1.0),
    (1.0, -1.0, 1.0),
    (-1.0, -1.0, 1.0),
  ]
  let m = vp.inverse.m.map(v => Float::from_double(v).to_double())
  let points = corners.map(c => {
    let (x, y, z) = (c.0, c.1, -c.2)
    let s = 1.0 / (m[3] * x + m[7] * y + m[11] * z + m[15])
    (
      {
        x: (m[0] * x + m[4] * y + m[8] * z + m[12]) * s,
        y: (m[1] * x + m[5] * y + m[9] * z + m[13]) * s,
        z: (m[2] * x + m[6] * y + m[10] * z + m[14]) * s,
      } : Vec3)
  })
  let horizon : Plane = { n: vp.plane, d: vp.plane_d, }
  fit_far_plane(points, horizon)
  let planes = [
    plane_through(points[6], points[5], points[4]),
    plane_through(points[0], points[1], points[2]),
    plane_through(points[0], points[3], points[7]),
    plane_through(points[2], points[1], points[5]),
    plane_through(points[3], points[2], points[6]),
    plane_through(points[0], points[4], points[5]),
  ]
  { points, planes, }
}

///|
/// `adjustFarPlaneByHorizonPlane`: the far corners (0 to 3) moved toward the
/// near ones (4 to 7) until the far plane just takes in the horizon.
fn fit_far_plane(points : Array[Vec3], horizon : Plane) -> Unit {
  let lengths = []
  let dirs = []
  for i in 0..<4 {
    let dir = points[i].sub(points[i + 4])
    let len = dir.length()
    lengths.push(len)
    dirs.push(dir.scale(1.0 / len))
  }
  let mut max_dist = 0.0
  for i in 0..<4 {
    let along = dirs[i].dot(horizon.n)
    let dist = if along == 0.0 {
      None
    } else {
      Some((-points[i + 4].dot(horizon.n) - horizon.d) / along)
    }
    max_dist = match dist {
      Some(d) if d >= 0.0 => @cmp.maximum(max_dist, d)
      _ => @cmp.maximum(max_dist, lengths[i])
    }
  }
  let near = plane_through(points[6], points[5], points[4])
  let near : Plane = { n: near.n, d: -near.n.dot(points[6]), }
  if ideal_far_distance(horizon, near) is Some(ideal) {
    max_dist = @cmp.minimum(max_dist, ideal / dirs[0].dot(near.n))
  }
  for i in 0..<4 {
    points[i] = points[i + 4].add_scaled(
      dirs[i],
      @cmp.minimum(max_dist, lengths[i]),
    )
  }
}

///|
/// `getIdealNearFarPlaneDistance`: how far the horizon circle reaches beyond
/// the near plane, None when looking straight down.
fn ideal_far_distance(horizon : Plane, near : Plane) -> Double? {
  let k = 1.0 / horizon.n.length()
  let n = horizon.n.scale(k)
  let w = horizon.d * k
  let view = near.n.sub(n.scale(near.n.dot(n)))
  let len = view.length()
  if len > 0.0 {
    let radius = (1.0 - w * w).sqrt()
    Some(near.distance(n.scale(-w).add(view.scale(radius / len))))
  } else {
    None
  }
}

///|
/// The volume a tile's surface takes on the unit sphere up to `top` planet
/// radii (`_computeTileBoundingVolume` without terrain).
fn tile_volume(z : Int32, x : Int32, y : Int32, top : Double) -> Volume {
  if z <= 0 {
    return Volume::of_box({ x: -top, y: -top, z: -top, }, {
      x: top,
      y: top,
      z: top,
    })
  }
  if z == 1 {
    return Volume::of_box(
      {
        x: if x == 0 {
          -top
        } else {
          0.0
        },
        y: if y == 0 {
          0.0
        } else {
          -top
        },
        z: -top,
      },
      {
        x: if x == 0 {
          0.0
        } else {
          top
        },
        y: if y == 0 {
          top
        } else {
          0.0
        },
        z: top,
      },
    )
  }
  let e = @core.TILE_EXTENT.to_double()
  let corners = [
    tile_vector(0.0, 0.0, z, x, y),
    tile_vector(e, 0.0, z, x, y),
    tile_vector(e, e, z, x, y),
    tile_vector(0.0, e, z, x, y),
  ]
  let extremes = corners.map(c => c.scale(top))
  if top != 1.0 {
    for c in corners {
      extremes.push(c)
    }
  }
  let last = (1 << z) - 1
  if y == 0 {
    extremes.push({ x: 0.0, y: 1.0, z: 0.0, })
  }
  if y == last {
    extremes.push({ x: 0.0, y: -1.0, z: 0.0, })
  }
  let center = tile_vector(e / 2.0, e / 2.0, z, x, y)
  let east = ({ x: 0.0, y: 1.0, z: 0.0, } : Vec3).cross(center).normalize()
  let north = center.cross(east).normalize()
  let axis_east = corners[2].cross(corners[1]).normalize()
  let axis_west = corners[0].cross(corners[3]).normalize()
  extremes.push(center.scale(top))
  if y >= (1 << z) / 2 {
    extremes.push(tile_vector(e / 2.0, 0.0, z, x, y).scale(top))
  } else {
    extremes.push(tile_vector(e / 2.0, e, z, x, y).scale(top))
  }
  let (up_min, up_max) = axis_range(center, extremes)
  let (ns_min, ns_max) = axis_range(north, extremes)
  let up : Plane = { n: center.scale(-1.0), d: up_max, }
  let down : Plane = { n: center, d: -up_min, }
  let north_plane : Plane = { n: north.scale(-1.0), d: ns_max, }
  let south : Plane = { n: north, d: -ns_min, }
  let east_plane : Plane = { n: axis_east, d: 0.0, }
  let west : Plane = { n: axis_west, d: 0.0, }
  let points = if y == 0 {
    [meet(west, east_plane, up), meet(west, east_plane, down)]
  } else {
    [
      meet(north_plane, east_plane, up),
      meet(north_plane, east_plane, down),
      meet(north_plane, west, up),
      meet(north_plane, west, down),
    ]
  }
  if y == last {
    points.push(meet(west, east_plane, up))
    points.push(meet(west, east_plane, down))
  } else {
    points.push(meet(south, east_plane, up))
    points.push(meet(south, east_plane, down))
    points.push(meet(south, west, up))
    points.push(meet(south, west, down))
  }
  { points, planes: [up, down, north_plane, south, east_plane, west], }
}

///|
/// The smallest and largest `axis·p` over `points` (`findAxisMinMax`).
fn axis_range(axis : Vec3, points : Array[Vec3]) -> (Double, Double) {
  let mut min = @double.infinity
  let mut max = @double.neg_infinity
  for p in points {
    let d = axis.dot(p)
    min = @cmp.minimum(min, d)
    max = @cmp.maximum(max, d)
  }
  (min, max)
}

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
/// V8's `Math.hypot` of two numbers (scaled by the larger, Kahan-summed).
fn hypot(a : Double, b : Double) -> Double {
  let (a, b) = (a.abs(), b.abs())
  if a.is_nan() || b.is_nan() {
    return if a == @double.infinity || b == @double.infinity {
      @double.infinity
    } else {
      @double.not_a_number
    }
  }
  let max = @cmp.maximum(a, b)
  if max == @double.infinity {
    return max
  }
  if max == 0.0 {
    return 0.0
  }
  let mut sum = 0.0
  let mut compensation = 0.0
  for v in [a, b] {
    let n = v / max
    let summand = n * n - compensation
    let preliminary = sum + summand
    compensation = preliminary - sum - summand
    sum = preliminary
  }
  sum.sqrt() * max
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
        @math.cos(radians(MAX_HORIZON_ANGLE - fov)) /
        @math.cos(radians(MAX_HORIZON_ANGLE)),
      ) -
      1.0
    )
  let center_pitch = @math.acos(dz / center_d3)
  let pitch0 = 2.0 * integral_cos_pow(behavior - 1.0, 0.0, radians(fov / 2.0))
  let highest = @cmp.minimum(
    radians(MAX_HORIZON_ANGLE),
    center_pitch + radians(fov / 2.0),
  )
  let lowest = @cmp.minimum(highest, center_pitch - radians(fov / 2.0))
  let count = integral_cos_pow(behavior - 1.0, lowest, highest)
  let tile_pitch = @math.atan(d2 / dz)
  let d3 = hypot(d2, dz)
  let mut z = center_zoom +
    scale_zoom(
      center_d3 / d3 / @cmp.maximum(0.5, @math.cos(radians(fov / 2.0))),
    )
  z += behavior * scale_zoom(@math.cos(tile_pitch)) / 2.0
  z -= scale_zoom(@cmp.maximum(1.0, count / pitch0 / 3.0)) / 2.0
  z
}

///|
fn mercator_y(lat : Double) -> Double {
  (
    180.0 -
    180.0 /
    @math.PI *
    @math.ln(@math.tan(@math.PI / 4.0 + lat * @math.PI / 360.0))
  ) /
  360.0
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
    (2.0 * @math.PI * EARTH_RADIUS * @math.cos(lat * @math.PI / 180.0))
  let distance = self.center_distance() / (units_per_meter * self.world_size())
  let d_merc = distance * units_per_meter
  let (pr, br) = (radians(pitch), radians(bearing))
  let h = @math.sin(pr)
  let center_x = (180.0 + lng) / 360.0
  let center_y = mercator_y(lat)
  let cam_x = center_x + d_merc * -(h * @math.sin(br))
  let cam_y = center_y + d_merc * -(-h * @math.cos(br))
  let cam_z = 0.0 + d_merc * @math.cos(-pr)
  let horizon_gap = MAX_HORIZON_ANGLE - pitch - fov / 2.0
  let near_horizon = clamp((15.0 - horizon_gap) / 15.0, 0.0, 1.0)
  let top = near_horizon * 500.0 / EARTH_RADIUS + 1.0
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
  let center_d3 = hypot(hypot(center_x - cam_x, center_y - cam_y), dz)
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
