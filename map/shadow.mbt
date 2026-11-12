///|
/// The frame's shadows: the shadow map's view over world pixels (`flat`) and, on the globe past half its
/// transition, over the unit sphere (`sphere`, which is then used); how dark they are, the sun's share of the
/// ground's light; or with `spot` a viewshed's view, `ground` the strength of its tint.
priv struct Shadows {
  flat : @core.ShadowView
  sphere : @core.ShadowView?
  intensity : Double
  ground : Double
  spot : Bool
}

///|
/// How strongly a viewshed tints what it covers.
const VIEWSHED_TINT : Double = 0.4

///|
/// Shows from now on what is seen from `v` (longitude, latitude, meters up, heading clockwise from north
/// and pitch up from level, horizontal and vertical field of view, all degrees, and the distance in meters)
/// instead of the lights' shadows, or none with None.
pub fn Map::set_viewshed(self : Map, v : FixedArray[Double]?) -> Unit {
  self.viewshed = v
  self.request_render()
}

///|
/// The viewshed's view for this frame (`set_viewshed`).
fn Map::viewshed_view(self : Map, v : FixedArray[Double]) -> Shadows {
  let t = self.transform
  let ppm = t.pixels_per_meter()
  let from = self.world_point((v[0], v[1], v[2]))
  let (heading, pitch) = (@core.radians(v[3]), @core.radians(v[4]))
  let dir = (
    @math.sin(heading) * @math.cos(pitch),
    -@math.cos(heading) * @math.cos(pitch),
    @math.sin(pitch),
  )
  let fov = @core.radians(v[6])
  let aspect = @math.tan(@core.radians(v[5]) / 2.0) / @math.tan(fov / 2.0)
  let view = @core.spot_view(from, dir, fov, aspect, ppm, v[7] * ppm)
  {
    flat: view,
    sphere: None,
    intensity: 1.0,
    ground: VIEWSHED_TINT,
    spot: true,
  }
}

///|
/// The shadows of the style's `lights` for this frame: None without
/// `cast-shadows`, or with the sun at or below the horizon.
fn Map::frame_shadows(self : Map) -> Shadows? {
  if self.viewshed is Some(v) && v.length() == 8 {
    return Some(self.viewshed_view(v))
  }
  guard self.style.lights is Some({ shadows: Some(k), .. }) && k > 0.0 else {
    None
  }
  guard self.lights() is Some((ambient, sun, dir)) && dir.2 > 0.01 else { None }
  let lum = (c : (Double, Double, Double)) => {
    0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2
  }
  let direct = lum(sun) * dir.2
  guard direct > 0.0 else { None }
  let t = self.transform
  let sphere = match self.globe {
    Some(g) if g.is_globe() && g.transition() > 0.5 =>
      Some(t.shadow_sphere_view(dir))
    _ => None
  }
  Some({
    flat: t.shadow_view(dir),
    sphere,
    intensity: k,
    ground: direct / (lum(ambient) + direct),
    spot: false,
  })
}

///|
/// The shadow map's matrix for tile units of `id`, while there are shadows.
fn Map::tile_shadow(self : Map, id : @core.TileId) -> @core.Mat4? {
  self.shadows.map(s => {
    self.transform.tile_light_matrix(s.flat.matrix, id, @core.TILE_EXTENT)
  })
}

///|
/// The light's view as `world_matrix` takes points (world pixels from the
/// world's corner, meters up).
fn Map::world_light(self : Map, s : Shadows) -> @core.Mat4 {
  let t = self.transform
  let ws = t.world_size()
  let c = t.camera.center.to_mercator()
  s.flat.matrix
  .translate(-c.x * ws, -c.y * ws, 0.0)
  .scale(1.0, 1.0, t.pixels_per_meter())
}

///|
/// Takes this frame's shadows and, if any, draws the casters into the shadow map.
fn Map::draw_shadow_map(
  self : Map,
  draws_of : @hashmap.HashMap[String, Array[Draw]],
) -> Unit {
  self.shadows = self.frame_shadows()
  self.use_shadows()
  if self.shadows is Some(s) {
    self.draw_casters(draws_of, s, None)
  }
}

///|
/// Tells the renderer how draws receive `self.shadows`.
fn Map::use_shadows(self : Map) -> Unit {
  let identity = @core.Mat4::identity()
  match self.shadows {
    None => self.renderer.set_shadow(0, identity, 0.0, 0.0)
    Some({ sphere: Some(v), intensity, .. }) =>
      self.renderer.set_shadow(2, v.matrix, intensity, v.texel)
    Some({ flat, intensity, spot, .. }) =>
      self.renderer.set_shadow(
        if spot {
          3
        } else {
          1
        },
        identity,
        intensity,
        flat.texel,
      )
  }
}

///|
/// Draws the casters (extrusions, and custom layers through their shadow pass)
/// of `s`'s view into the shadow map, or into its corner `size` texels across.
fn Map::draw_casters(
  self : Map,
  draws_of : @hashmap.HashMap[String, Array[Draw]],
  s : Shadows,
  size : Int32?,
) -> Unit {
  let zoom = self.transform.camera.zoom
  let light = self.extrusion_light()
  let on_terrain = self.terrain_source() is Some(_)
  self.renderer.begin_shadow_map(size?)
  for index, layer in self.style.layers {
    if zoom < layer.min_zoom || zoom >= layer.max_zoom {
      continue
    }
    if layer.kind is Custom {
      call_custom(self.custom, layer.id, CUSTOM_SHADOW, self.shadow_numbers(s))
    } else if layer.extrusion is Some(e) {
      let shared = paint_of(layer, zoom, JsProps::none())
      for d in draws_of.get(layer.source).unwrap_or([]) {
        self.draw_extrusions(index, layer, e, shared, d, light, on_terrain, 3)
      }
    }
  }
  self.renderer.end_shadow_map()
}

///|
/// Texels across the corner of the shadow map a ray is drawn into, and its
/// width either side (meters).
const RAY_TEXELS : Int32 = 8

///|
const RAY_PAD : Double = 0.02

///|
/// Where the segment from `from` to `to` (longitude, latitude, meters up) first meets an extrusion,
/// a custom layer's casters, the terrain or else sea level, short of `to` by `margin` meters; None if
/// nothing is in the way. Drawn as the last frame's tiles stand, through the shadow map.
pub fn Map::cast_ray(
  self : Map,
  from : (Double, Double, Double),
  to : (Double, Double, Double),
  margin : Double,
) -> (Double, Double, Double)? {
  let a = self.world_point(from)
  let b = self.world_point(to)
  let (dx, dy, dz) = (b.0 - a.0, b.1 - a.1, b.2 - a.2)
  let length = (dx * dx + dy * dy + dz * dz).sqrt()
  guard length > 0.0 else { return None }
  let dir = (dx / length, dy / length, dz / length)
  let short = length - margin * self.transform.pixels_per_meter()
  guard short > 0.0 && self.raycast_px(a, dir, short) is Some(d) else {
    return None
  }
  Some(self.world_place((a.0 + dir.0 * d, a.1 + dir.1 * d, a.2 + dir.2 * d)))
}

///|
/// `p` (longitude, latitude, meters up) in world pixels relative to the center, z up.
fn Map::world_point(
  self : Map,
  p : (Double, Double, Double),
) -> (Double, Double, Double) {
  let t = self.transform
  let ws = t.world_size()
  let c = t.camera.center.to_mercator()
  let m = ({ lng: p.0, lat: p.1, } : @core.LngLat).to_mercator()
  ((m.x - c.x) * ws, (m.y - c.y) * ws, p.2 * t.pixels_per_meter())
}

///|
/// The longitude, latitude and meters up of world point `p` (as `world_point` gives).
fn Map::world_place(
  self : Map,
  p : (Double, Double, Double),
) -> (Double, Double, Double) {
  let t = self.transform
  let ws = t.world_size()
  let c = t.camera.center.to_mercator()
  let m : @core.MercatorCoord = { x: c.x + p.0 / ws, y: c.y + p.1 / ws, }
  let q = m.to_lnglat()
  (q.lng, q.lat, p.2 / t.pixels_per_meter())
}

///|
/// `raycast` in world pixels relative to the center (z up).
fn Map::raycast_px(
  self : Map,
  from : (Double, Double, Double),
  dir : (Double, Double, Double),
  length : Double,
) -> Double? {
  let t = self.transform
  let ground = t.ground_hit(from, dir, length, self.terrain_pick())
  guard length > 0.0 else { return ground }
  let view = @core.ray_view(from, dir, length, RAY_PAD * t.pixels_per_meter())
  let saved = self.shadows
  let s = {
    flat: view,
    sphere: None,
    intensity: 0.0,
    ground: 0.0,
    spot: false,
  }
  self.shadows = Some(s)
  self.use_shadows()
  self.draw_casters(self.drawn, s, Some(RAY_TEXELS))
  let depth = self.renderer.shadow_depth_at(RAY_TEXELS / 2, RAY_TEXELS / 2)
  self.shadows = saved
  self.use_shadows()
  // The shadow map now holds the ray: the next frame draws it again.
  if saved is Some(_) {
    self.request_render()
  }
  let surface = if depth < 1.0 { Some(depth * length) } else { None }
  match (surface, ground) {
    (Some(a), Some(b)) => Some(@cmp.minimum(a, b))
    (Some(a), None) | (None, Some(a)) => Some(a)
    (None, None) => None
  }
}

///|
/// The point (longitude, latitude, meters up) under screen point (x, y): where
/// its ray first meets what is drawn (extrusions, custom layers' casters,
/// terrain, sea level); None if nothing, or on the globe off its ground.
pub fn Map::pick_position(
  self : Map,
  x : Double,
  y : Double,
) -> (Double, Double, Double)? {
  if self.globe is Some(g) && g.is_globe() {
    let p = g.unproject(x, y)
    return Some((p.lng, p.lat, 0.0))
  }
  let t = self.transform
  let (from, dir, length) = t.eye_ray(x, y)
  guard self.raycast_px(from, dir, length) is Some(d) else { return None }
  Some(
    self.world_place(
      (from.0 + dir.0 * d, from.1 + dir.1 * d, from.2 + dir.2 * d),
    ),
  )
}

///|
/// Darkens the ground in shadow over the view's tiles (not on terrain).
fn Map::draw_ground_shadows(self : Map, s : Shadows, dpr : Double) -> Unit {
  let t = self.transform
  let tiles = match self.globe {
    Some(g) if g.is_globe() =>
      self.globe_cover(g, 512, 0, @core.MAX_TILE_ZOOM, false)
    _ => t.covering_tiles(0, t.tile_zoom(0, @core.MAX_TILE_ZOOM))
  }
  for id in tiles {
    let light = t.tile_light_matrix(s.flat.matrix, id, @core.TILE_EXTENT)
    self.renderer.draw_ground_shadow(
      self.placement(id, None, dpr),
      light,
      s.ground,
    )
  }
}

///|
/// The numbers a custom layer draws its shadow casters with: `custom_numbers`
/// with the light's view as the model-view-projection (on the globe's sphere
/// as the globe's matrix, nothing clipped by its horizon).
fn Map::shadow_numbers(self : Map, s : Shadows) -> FixedArray[Double] {
  let out = self.custom_numbers()
  for i, v in self.world_light(s).m {
    out[i] = v
  }
  match s.sphere {
    Some(v) => {
      out[CUSTOM_TRANSITION] = 1.0
      for i, x in v.matrix.m {
        out[CUSTOM_TRANSITION + 1 + i] = x
      }
      for i, x in [0.0, 0.0, 0.0, 1.0] {
        out[CUSTOM_PLANE + i] = x
      }
    }
    None => out[CUSTOM_TRANSITION] = 0.0
  }
  out
}

///|
/// Clips extrusions from now on (`Map.setClipping`): `c` is the origin (longitude, latitude, meters up)
/// and then what `Renderer::set_cut` takes; empty clips nothing.
pub fn Map::set_clipping(self : Map, c : FixedArray[Double]) -> Unit {
  self.clipping = if clipping_ok(c) { c } else { [] }
  self.request_render()
}

///|
/// Whether `c` is laid out as `Map::set_clipping` takes it, with at most `@core.MAX_CLIP_PLANES`,
/// `MAX_CLIP_RINGS` and `MAX_CLIP_POINTS` (the shaders' arrays), every number finite.
fn clipping_ok(c : FixedArray[Double]) -> Bool {
  let n = c.length()
  guard n >= 11 && c.iter().all(x => x.is_finite()) else { return n == 0 }
  let planes = c[9]
  guard planes >= 0.0 &&
    planes <= @core.MAX_CLIP_PLANES.to_double() &&
    planes == planes.floor() else {
    return false
  }
  let at = 10 + 4 * planes.to_int()
  guard at < n else { return false }
  let rings = c[at]
  guard rings >= 0.0 &&
    rings <= @core.MAX_CLIP_RINGS.to_double() &&
    rings == rings.floor() else {
    return false
  }
  let first = at + 1 + rings.to_int()
  guard first <= n else { return false }
  let mut points = 0.0
  for i in (at + 1)..<first {
    guard c[i] >= 0.0 && c[i] == c[i].floor() else { return false }
    points += c[i]
  }
  points <= @core.MAX_CLIP_POINTS.to_double() &&
  (n - first).to_double() == 2.0 * points
}

///|
/// Takes this frame's clipping: its frame at the origin and what the renderer cuts with.
fn Map::use_clipping(self : Map) -> Unit {
  let c = self.clipping
  guard c.length() > 3 else {
    self.cut_frame = None
    self.renderer.set_cut([], 1.0)
    return
  }
  let t = self.transform
  self.cut_frame = Some(t.enu_matrix((c[0], c[1], c[2])))
  let cut = FixedArray::makei(c.length() - 3, i => c[i + 3])
  self.renderer.set_cut(cut, 1.0 / (t.center_depth() * t.pixels_per_meter()))
}
