// MapLibre GL JS 6.16.0's GlobeTransform (src/geo/projection/globe_transform.ts), its vertical
// perspective (vertical_perspective_transform.ts) and the camera state both share
// (src/geo/transform_helper.ts), BSD-3-Clause, Copyright (c) 2020 MapLibre contributors; see NOTICE.

///|
/// A globe projection's camera, one state that each change constrains in place
/// as MapLibre's transform does (`copy` makes another): drawn as a globe while
/// `transition` is above 0, as mercator (`@core.Transform`) at 0.
pub struct Globe {
  priv mut center : @core.LngLat
  priv mut zoom : Double
  priv mut bearing : Double
  priv mut pitch : Double
  priv mut width : Double
  priv mut height : Double
  priv limits : @core.Limits
  priv projection : Projection
  priv mut globeness : Double
  priv mut constraining : Bool
  priv mut vp : Vp?
}

///|
/// The vertical perspective's matrices (`_calcMatrices`): unit sphere to clip
/// space and back, the projection alone, the camera on the unit sphere's scale
/// and the plane past which the sphere is hidden (normal and offset).
priv struct Vp {
  view : @core.Mat4
  inverse : @core.Mat4
  projection : @core.Mat4
  near : Double
  far : Double
  camera : Vec3
  plane : Vec3
  plane_d : Double
}

///|
/// A globe camera on a `width` x `height` viewport as MapLibre's `jumpTo` gives it
/// once the style sets `projection` (a new globe transform starts as a globe);
/// the transition then follows the zoom it ends at.
pub fn Globe::new(
  camera : @core.Camera,
  width : Double,
  height : Double,
  limits~ : @core.Limits = @core.Limits::default(),
  projection~ : Projection = Globe,
) -> Globe {
  let g = {
    center: { lng: 0.0, lat: 0.0, },
    zoom: limits.min_zoom,
    bearing: 0.0,
    pitch: radians(limits.min_pitch),
    width: 0.0,
    height: 0.0,
    limits,
    projection,
    globeness: if projection is Mercator {
      0.0
    } else {
      1.0
    },
    constraining: false,
    vp: None,
  }
  g.resize(width, height)
  g.jump_to(
    center=camera.center,
    zoom=camera.zoom,
    bearing=camera.bearing,
    pitch=camera.pitch,
  )
  g.update_transition()
  g
}

///|
/// Another camera in the same state.
pub fn Globe::copy(self : Globe) -> Globe {
  { ..self, vp: self.vp, }
}

///|
pub fn Globe::camera(self : Globe) -> @core.Camera {
  {
    center: self.center,
    zoom: self.zoom,
    bearing: self.bearing / @math.PI * 180.0,
    pitch: self.pitch / @math.PI * 180.0,
  }
}

///|
/// The projection the camera follows.
pub fn Globe::projection(self : Globe) -> Projection {
  self.projection
}

///|
/// The zoom, pitch and bounds limits the camera keeps to.
pub fn Globe::limits(self : Globe) -> @core.Limits {
  self.limits
}

///|
/// How far toward the globe the map is drawn, 0 to 1.
pub fn Globe::transition(self : Globe) -> Double {
  self.globeness
}

///|
/// Whether the map is drawn as a globe (MapLibre's `isGlobeRendering`).
pub fn Globe::is_globe(self : Globe) -> Bool {
  self.globeness > 0.0
}

///|
/// Takes the transition from the current zoom, as MapLibre's map does when it
/// draws a frame (`setTransitionState`).
pub fn Globe::update_transition(self : Globe) -> Unit {
  self.globeness = self.projection.transition(self.zoom)
  self.vp = None
}

///|
pub fn Globe::world_size(self : Globe) -> Double {
  @core.TILE_SIZE * zoom_scale(self.zoom)
}

///|
fn Globe::center_distance(self : Globe) -> Double {
  0.5 / @math.tan(@core.FIELD_OF_VIEW / 2.0) * self.height
}

///|
/// The mercator camera of the same state, for a transition of 0.
pub fn Globe::mercator(self : Globe) -> @core.Transform {
  @core.Transform::exact(
    self.camera(),
    self.width,
    self.height,
    limits=self.limits,
  )
}

///|
fn Globe::changed(self : Globe) -> Unit {
  self.vp = None
}

///|
/// The projection's constraint (`defaultConstrain`) of the center and zoom.
fn Globe::constrain(
  self : Globe,
  center : @core.LngLat,
  zoom : Double,
) -> (@core.LngLat, Double) {
  if !self.is_globe() {
    return @core.mercator_constrain(
      center,
      zoom,
      self.limits,
      self.width,
      self.height,
    )
  }
  let zoom = clamp(
    zoom,
    self.limits.min_zoom + zoom_adjustment(0.0, center.lat),
    self.limits.max_zoom,
  )
  let max_lat = self.max_latitude(zoom)
  ({ lng: center.lng, lat: clamp(center.lat, -max_lat, max_lat), }, zoom)
}

///|
/// How close to a pole the center may go at `zoom`: past the mercator limit
/// by as much as half the viewport shows (`_getMaxLatitude`).
fn Globe::max_latitude(self : Globe, zoom : Double) -> Double {
  let area = radians(90.0 - @core.MAX_VALID_LATITUDE)
  let area_pixels = globe_radius(
      @core.TILE_SIZE * zoom_scale(zoom),
      @core.MAX_VALID_LATITUDE,
    ) *
    area
  let reach = @cmp.minimum(self.width, self.height) / 2.0
  let center = @cmp.minimum(area_pixels, reach) *
    remap_saturate(area_pixels, reach, reach * POLE_AREA_FADE_SCALE, 1.0, 0.0)
  @core.MAX_VALID_LATITUDE + degrees(area * center / area_pixels)
}

///|
const POLE_AREA_FADE_SCALE : Double = 4.0

///|
/// `getConstrainedCamera`: constrained, then the zoom again at the new center.
fn Globe::constrained(
  self : Globe,
  center : @core.LngLat,
  zoom : Double,
) -> (@core.LngLat, Double) {
  if self.width == 0.0 || self.height == 0.0 {
    return (center, zoom)
  }
  let (c, z) = self.constrain(center, zoom)
  (c, self.constrain(c, z).1)
}

///|
fn Globe::constrain_state(self : Globe) -> Unit {
  if self.width == 0.0 || self.height == 0.0 || self.constraining {
    return
  }
  self.constraining = true
  let (center, zoom) = self.constrain(self.center, self.zoom)
  self.set_center(center)
  self.set_zoom(zoom)
  self.constraining = false
}

///|
/// Sets the zoom, constrained at the current center.
pub fn Globe::set_zoom(self : Globe, zoom : Double) -> Unit {
  let z = self.constrain(self.center, zoom).1
  if self.zoom == z {
    return
  }
  self.zoom = z
  self.constrain_state()
  self.changed()
}

///|
/// Sets the center, then constrains the camera.
pub fn Globe::set_center(self : Globe, center : @core.LngLat) -> Unit {
  if center.lat == self.center.lat && center.lng == self.center.lng {
    return
  }
  self.center = center
  self.constrain_state()
  self.changed()
}

///|
fn Globe::set_center_and_zoom(
  self : Globe,
  center : @core.LngLat,
  zoom : Double,
) -> Unit {
  self.center = center
  self.zoom = zoom
  self.changed()
}

///|
/// Sets the bearing in degrees, wrapped to (-180, 180].
pub fn Globe::set_bearing(self : Globe, bearing : Double) -> Unit {
  let b = wrap(bearing, -180.0, 180.0) * @math.PI / 180.0
  if self.bearing == b {
    return
  }
  self.bearing = b
  self.changed()
}

///|
/// Sets the pitch in degrees, kept to the limits.
pub fn Globe::set_pitch(self : Globe, pitch : Double) -> Unit {
  let p = clamp(pitch, self.limits.min_pitch, self.limits.max_pitch) /
    180.0 *
    @math.PI
  if self.pitch == p {
    return
  }
  self.pitch = p
  self.changed()
}

///|
/// The same camera on a `width` x `height` viewport, constrained again.
pub fn Globe::resize(self : Globe, width : Double, height : Double) -> Unit {
  self.width = width
  self.height = height
  self.constrain_state()
  self.changed()
}

///|
fn Globe::vp(self : Globe) -> Vp {
  match self.vp {
    Some(vp) => vp
    None => {
      let vp = self.calc_vp()
      self.vp = Some(vp)
      vp
    }
  }
}

///|
fn Globe::calc_vp(self : Globe) -> Vp {
  let r = globe_radius(self.world_size(), self.center.lat)
  let d = self.center_distance()
  let near = 0.5
  let far = d + r * 2.0
  let projection = @core.Mat4::perspective(
    @core.FIELD_OF_VIEW,
    self.width / self.height,
    near,
    far,
  )
  let lng = self.center.lng * @math.PI / 180.0
  let lat = self.center.lat * @math.PI / 180.0
  let view = projection
    .translate(0.0, 0.0, -d)
    .rotate_x(-self.pitch)
    .rotate_z(self.bearing)
    .translate(0.0, 0.0, -r)
    .rotate_x(lat)
    .rotate_y(-lng)
    .scale(r, r, r)
  let camera = ({ x: 0.0, y: 0.0, z: d / r, } : Vec3)
    .rotate_x(self.pitch)
    .rotate_z(-self.bearing)
    .add({ x: 0.0, y: 0.0, z: 1.0, })
    .rotate_x(-lat)
    .rotate_y(lng)
  let (plane, plane_d) = self.clipping_plane(r)
  {
    view,
    inverse: view.invert().unwrap_or(@core.Mat4::identity()),
    projection,
    near,
    far,
    camera,
    plane,
    plane_d,
  }
}

///|
/// The plane through the horizon circle seen from the camera
/// (`_computeClippingPlane`): points of the sphere behind it are hidden.
fn Globe::clipping_plane(self : Globe, r : Double) -> (Vec3, Double) {
  let to_b = self.center_distance() / r
  let to_a = @math.sin(self.pitch) * to_b
  let a_to_c = @math.cos(self.pitch) * to_b + 1.0
  let to_c = (to_a * to_a + a_to_c * a_to_c).sqrt()
  let tangent = 1.0 / to_c
  let len = (to_a * to_a + a_to_c * a_to_c).sqrt()
  let v = ({ x: 0.0, y: -to_a / len, z: a_to_c / len, } : Vec3)
    .rotate_z(-self.bearing)
    .rotate_x(-1.0 * self.center.lat * @math.PI / 180.0)
    .rotate_y(self.center.lng * @math.PI / 180.0)
  let scale = 1.0 / v.length()
  (v.scale(scale), -tangent * scale)
}

///|
/// The camera's position on the unit sphere's scale (globe drawing only).
pub fn Globe::camera_position(self : Globe) -> Vec3 {
  self.vp().camera
}

///|
/// MapLibre's `modelViewProjectionMatrix` of the globe: the unit sphere to
/// clip space.
pub fn Globe::globe_matrix(self : Globe) -> @core.Mat4 {
  self.vp().view
}

///|
/// The globe's projection matrix and its near and far planes (CSS pixels).
pub fn Globe::projection_matrix(self : Globe) -> (@core.Mat4, Double, Double) {
  let vp = self.vp()
  (vp.projection, vp.near, vp.far)
}

///|
/// The horizon plane as `(a, b, c, d)`: points `p` of the sphere with
/// `a*p.x + b*p.y + c*p.z + d < 0` are behind the globe.
pub fn Globe::clipping_plane_of(
  self : Globe,
) -> (Double, Double, Double, Double) {
  let vp = self.vp()
  (vp.plane.x, vp.plane.y, vp.plane.z, vp.plane_d)
}

///|
fn Globe::plane_distance(self : Globe, p : Vec3) -> Double {
  let vp = self.vp()
  vp.plane.dot(p) + vp.plane_d
}

///|
/// The camera's height above the sphere in meters (`getCameraAltitude`).
pub fn Globe::camera_altitude(self : Globe) -> Double {
  if !self.is_globe() {
    return @math.cos(self.pitch) *
      self.center_distance() /
      self.mercator().pixels_per_meter()
  }
  (self.vp().camera.length() - 1.0) * EARTH_RADIUS
}

///|
/// MapLibre's `earthRadius`.
const EARTH_RADIUS : Double = 6371008.8

///|
/// Screen point (CSS pixels) of `p`, also when it is behind the globe.
pub fn Globe::project(self : Globe, p : @core.LngLat) -> (Double, Double) {
  if !self.is_globe() {
    return self.mercator().project(p)
  }
  self.project_vector(surface_vector(p))
}

///|
fn Globe::project_vector(self : Globe, v : Vec3) -> (Double, Double) {
  let (x, y, _, w) = transform(self.vp().view, v)
  ((x / w * 0.5 + 0.5) * self.width, (-(y / w) * 0.5 + 0.5) * self.height)
}

///|
/// Whether `p` is on the far side of the globe (no terrain).
pub fn Globe::occluded(self : Globe, p : @core.LngLat) -> Bool {
  if !self.is_globe() {
    return false
  }
  self.plane_distance(surface_vector(p)) < 0.0
}

///|
/// The unit direction of the ray from the camera through screen point (x, y)
/// (`getRayDirectionFromPixel`, always the globe's).
pub fn Globe::ray_direction(self : Globe, x : Double, y : Double) -> Vec3 {
  let vp = self.vp()
  let (px, py, pz, pw) = vp.inverse.apply(
    x / self.width * 2.0 - 1.0,
    (y / self.height * 2.0 - 1.0) * -1.0,
    1.0,
    1.0,
  )
  ({ x: px / pw, y: py / pw, z: pz / pw, } : Vec3).sub(vp.camera).normalize()
}

///|
/// Whether the ray through screen point (x, y) meets the globe.
pub fn Globe::on_surface(self : Globe, x : Double, y : Double) -> Bool {
  if !self.is_globe() {
    return y > self.height / 2.0 - self.mercator().horizon()
  }
  ray_sphere(self.vp().camera, self.ray_direction(x, y)) is Some(_)
}

///|
/// The place under screen point (x, y); off the globe, the nearest point of
/// the horizon.
pub fn Globe::unproject(self : Globe, x : Double, y : Double) -> @core.LngLat {
  if !self.is_globe() {
    return self.mercator().unproject(x, y)
  }
  let vp = self.vp()
  let origin = vp.camera
  let dir = self.ray_direction(x, y)
  if ray_sphere(origin, dir) is Some((t, _)) {
    return surface_point(origin.add(dir.scale(t)).normalize())
  }
  let along = vp.plane.dot(dir)
  let to_plane = -self.plane_distance(origin) / along
  let on_plane = if to_plane > 0.0 {
    origin.add(dir.scale(to_plane))
  } else {
    let far = origin.add(dir.scale(2.0))
    far.sub(vp.plane.scale(self.plane_distance(far)))
  }
  let disk = vp.plane.scale(-vp.plane_d)
  let radius = (1.0 - vp.plane_d * vp.plane_d).sqrt()
  let rel = on_plane.sub(disk)
  surface_point(disk.add_scaled(rel, radius / rel.length()))
}

///|
/// The box around the places at the viewport's corners and edge midpoints,
/// the whole range of longitudes when a pole is in view (`getBounds`).
pub fn Globe::bounds(self : Globe) -> @core.LngLatBounds {
  if !self.is_globe() {
    return self.mercator().bounds()
  }
  let (w, h) = (self.width, self.height)
  let (mx, my) = (w * 0.5, h * 0.5)
  let mut east = 0.0
  let mut west = 0.0
  let mut north = 0.0
  let mut south = 0.0
  for
    p in [
      (0.0, 0.0),
      (mx, 0.0),
      (w, 0.0),
      (w, my),
      (w, h),
      (mx, h),
      (0.0, h),
      (0.0, my),
    ] {
    let q = self.unproject(p.0, p.1)
    let d_lng = angle_difference(self.center.lng, q.lng)
    let d_lat = angle_difference(self.center.lat, q.lat)
    west = @cmp.minimum(west, d_lng)
    east = @cmp.maximum(east, d_lng)
    south = @cmp.minimum(south, d_lat)
    north = @cmp.maximum(north, d_lat)
  }
  let c = self.center
  let mut b : @core.LngLatBounds = {
    west: c.lng + west,
    south: c.lat + south,
    east: c.lng + east,
    north: c.lat + north,
  }
  if self.surface_on_screen({ x: 0.0, y: 1.0, z: 0.0, }) {
    b = { west: -180.0, south: b.south, east: 180.0, north: 90.0, }
  }
  if self.surface_on_screen({ x: 0.0, y: -1.0, z: 0.0, }) {
    b = { west: -180.0, south: -90.0, east: 180.0, north: b.north, }
  }
  b
}

///|
fn Globe::surface_on_screen(self : Globe, v : Vec3) -> Bool {
  if self.plane_distance(v) < 0.0 {
    return false
  }
  let (x, y, z, w) = transform(self.vp().view, v)
  let (x, y, z) = (x / w, y / w, z / w)
  x > -1.0 && x < 1.0 && y > -1.0 && y < 1.0 && z > -1.0 && z < 1.0
}

///|
/// Moves the camera so `p` is at screen point (x, y) (`setLocationAtPoint`).
pub fn Globe::set_location_at_point(
  self : Globe,
  p : @core.LngLat,
  x : Double,
  y : Double,
) -> Unit {
  let camera = if self.is_globe() {
    self.globe_location_at_point(p, x, y)
  } else {
    self.mercator_location_at_point(p, x, y)
  }
  if camera is Some((center, zoom)) {
    self.set_center_and_zoom(center, zoom)
  }
}

///|
fn Globe::mercator_location_at_point(
  self : Globe,
  p : @core.LngLat,
  x : Double,
  y : Double,
) -> (@core.LngLat, Double)? {
  let t = self.mercator()
  let a = t.ray_ground(x, y)
  let b = t.ray_ground(self.width / 2.0, self.height / 2.0)
  let loc = p.to_mercator()
  let center = (
    { x: loc.x - (a.x - b.x), y: loc.y - (a.y - b.y), } : @core.MercatorCoord).to_lnglat()
  let moved = center.lng != self.center.lng || center.lat != self.center.lat
  let mut camera = if moved {
    Some(self.constrained(center, self.zoom))
  } else {
    None
  }
  let (c, z) = camera.unwrap_or((self.center, self.zoom))
  let w = wrapped(c)
  if w.lng != c.lng {
    camera = Some(self.constrained(w, z))
  }
  camera
}

///|
fn Globe::globe_location_at_point(
  self : Globe,
  p : @core.LngLat,
  x : Double,
  y : Double,
) -> (@core.LngLat, Double)? {
  let at_pixel = surface_vector(self.unproject(x, y))
  let target = surface_vector(p)
  let lng0 = self.center.lng * @math.PI / 180.0
  let lat0 = self.center.lat * @math.PI / 180.0
  let rotated = at_pixel.rotate_y(-lng0).rotate_x(lat0)
  let xz2 = target.x * target.x + target.z * target.z
  let x2 = rotated.x * rotated.x
  if xz2 < x2 {
    return None
  }
  let ia = (xz2 - x2).sqrt()
  let lng_a = rotation_between(target.x, target.z, rotated.x, ia)
  let lng_b = rotation_between(target.x, target.z, rotated.x, -ia)
  let ta = target.rotate_y(-lng_a)
  let lat_a = rotation_between(ta.y, ta.z, rotated.y, rotated.z)
  let tb = target.rotate_y(-lng_b)
  let lat_b = rotation_between(tb.y, tb.z, rotated.y, rotated.z)
  let limit = @math.PI * 0.5
  let valid_a = lat_a >= -limit && lat_a <= limit
  let valid_b = lat_b >= -limit && lat_b <= limit
  let (lng, lat) = if valid_a && valid_b {
    if radian_distance(lng_a, lng0) + radian_distance(lat_a, lat0) <
      radian_distance(lng_b, lng0) + radian_distance(lat_b, lat0) {
      (lng_a, lat_a)
    } else {
      (lng_b, lat_b)
    }
  } else if valid_a {
    (lng_a, lat_a)
  } else if valid_b {
    (lng_b, lat_b)
  } else {
    return None
  }
  let new_lng = lng / @math.PI * 180.0
  let new_lat = clamp(lat / @math.PI * 180.0, -90.0, 90.0)
  let moved = new_lng != self.center.lng || new_lat != self.center.lat
  let (center, zoom) = if moved {
    self.constrained({ lng: new_lng, lat: new_lat, }, self.zoom)
  } else {
    (self.center, self.zoom)
  }
  let adjusted = self.constrain(
      center,
      zoom + zoom_adjustment(self.center.lat, center.lat),
    ).1
  if adjusted != zoom {
    return Some(self.constrained(center, adjusted))
  }
  if moved {
    Some((center, zoom))
  } else {
    None
  }
}

///|
/// Puts the camera at `camera` as it is, unconstrained (MapLibre's
/// `applyUpdatedTransform` taking an animation's or gesture's transform).
pub fn Globe::set_camera(self : Globe, camera : @core.Camera) -> Unit {
  self.center = camera.center
  self.zoom = camera.zoom
  self.bearing = camera.bearing * @math.PI / 180.0
  self.pitch = camera.pitch * @math.PI / 180.0
  self.changed()
}

///|
/// What MapLibre's atmosphere is drawn from: the projection's inverse, the
/// globe's center in the camera's space (CSS pixels), its radius and the
/// share of the atmosphere the camera's height leaves (`drawAtmosphere`).
pub fn Globe::atmosphere(self : Globe) -> (@core.Mat4, Vec3, Double, Double) {
  let vp = self.vp()
  let inverse = vp.projection.invert().unwrap_or(@core.Mat4::identity())
  let (x, y, z, w) = vp.view.apply(0.0, 0.0, 0.0, 1.0)
  let (cx, cy, cz, cw) = inverse.apply(x, y, z, w)
  let center : Vec3 = { x: cx / cw, y: cy / cw, z: cz / cw, }
  let r = globe_radius(self.world_size(), self.center.lat)
  (inverse, center, r, atmosphere_blend(center.length() - r, r))
}

///|
/// A light's direction `v` (the style light's, toward it) as the atmosphere
/// takes the sun: turned with the globe when the light is anchored to the
/// map (`getSunPos`).
pub fn Globe::sun(self : Globe, v : Vec3, map~ : Bool) -> Vec3 {
  let v = v.scale(-1.0)
  if !map {
    return v
  }
  let m = @core.Mat4::identity()
    .rotate_x(-self.pitch)
    .rotate_z(self.bearing)
    .rotate_x(self.center.lat * @math.PI / 180.0)
    .rotate_y(-self.center.lng * @math.PI / 180.0)
  let (x, y, z, w) = m.apply(v.x, v.y, v.z, 1.0)
  { x: x / w, y: y / w, z: z / w, }
}

///|
/// A direction in the axes of the map's plane at the center (x east, y south,
/// z up) in the globe's (MapLibre's `transformLightDirection`).
pub fn Globe::light_direction(self : Globe, v : Vec3) -> Vec3 {
  let s = surface_vector(self.center)
  let right : Vec3 = { x: s.z, y: 0.0, z: -s.x, }
  let down = right.cross(s).normalize()
  let right = right.normalize()
  right.scale(v.x).add(down.scale(v.y)).add(s.scale(v.z)).normalize()
}
