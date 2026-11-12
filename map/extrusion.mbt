///|
/// The direction toward a light at `position` (radial distance, azimuth from
/// north and polar angle in degrees: MapLibre's `sphericalToCartesian`), turned
/// by `bearing` degrees when it is anchored to the viewport.
fn light_direction(
  position : (Double, Double, Double),
  viewport : Bool,
  bearing : Double,
) -> (Double, Double, Double) {
  let (r, azimuth, polar) = position
  let a = @core.radians(azimuth + 90.0)
  let p = @core.radians(polar)
  let x = r * @math.cos(a) * @math.sin(p)
  let y = r * @math.sin(a) * @math.sin(p)
  let z = r * @math.cos(p)
  if viewport {
    let b = @core.radians(bearing)
    (
      x * @math.cos(b) - y * @math.sin(b),
      x * @math.sin(b) + y * @math.cos(b),
      z,
    )
  } else {
    (x, y, z)
  }
}

///|
/// The style's light at this camera.
fn Map::extrusion_light(self : Map) -> @render_webgl2.ExtrusionLight {
  let light = self.style.light
  let zoom = self.transform.camera.zoom
  let c = color_of(light.color, zoom, JsProps::none())
  let lights = self.lights()
  let direction = match self.style.lights {
    Some(l) => light_direction((1.0, l.direction.0, l.direction.1), false, 0.0)
    None =>
      light_direction(
        light.position,
        light.viewport,
        self.transform.camera.bearing,
      )
  }
  let globe_direction = match self.globe {
    Some(g) if g.is_globe() => {
      let d = g.light_direction({
        x: direction.0,
        y: direction.1,
        z: direction.2,
      })
      (d.x, d.y, d.z)
    }
    _ => direction
  }
  {
    direction,
    globe_direction,
    intensity: number_or(light.intensity.eval(zoom, JsProps::none()), 0.5),
    color: (c.r, c.g, c.b),
    lights: lights.map(l => (l.0, l.1)),
  }
}

///|
/// The style's `lights` at this zoom: the ambient and the directional light's
/// colors times their intensities, and the direction toward the directional one
/// (east, north, up); None without `lights`.
pub fn Map::lights(
  self : Map,
) -> (
  (Double, Double, Double),
  (Double, Double, Double),
  (Double, Double, Double),
)? {
  guard self.style.lights is Some(l) else { None }
  let zoom = self.transform.camera.zoom
  let scaled = (color : @style.Expr, intensity : @style.Expr) => {
    let c = color_of(color, zoom, JsProps::none())
    let k = number_or(intensity.eval(zoom, JsProps::none()), 0.0)
    (c.r * k, c.g * k, c.b * k)
  }
  let (x, y, z) = light_direction(
    (1.0, l.direction.0, l.direction.1),
    false,
    0.0,
  )
  // MapLibre's light axes (which its extrusions' normals are in) run west and north.
  Some(
    (
      scaled(l.ambient_color, l.ambient_intensity),
      scaled(l.sun_color, l.sun_intensity),
      (-x, y, z),
    ),
  )
}

///|
/// Looks up the ground under the features of `d`'s extrusion meshes again if
/// a DEM tile arrived since they were last.
fn Map::ground_extrusions(self : Map, src : SourceTiles, d : Draw) -> Unit {
  let n = (1 << d.id.z).to_double()
  let extent = @core.TILE_EXTENT.to_double()
  for m in d.meshes {
    guard m.ground is Some(g) && g.at != self.dem_version else { continue }
    g.at = self.dem_version
    let runs = g.runs
    let heights = FixedArray::make(runs.length() / 3, 0.0)
    for r in 0..<heights.length() {
      let c : @core.MercatorCoord = {
        x: (d.id.x.to_double() + runs[r * 3 + 1].to_double() / extent) / n,
        y: (d.id.y.to_double() + runs[r * 3 + 2].to_double() / extent) / n,
      }
      heights[r] = elevation_at(src, c).unwrap_or(0.0)
    }
    self.renderer.set_ground(m.mesh, runs, heights)
  }
}

///|
/// Draws `index`'s extrusion meshes of one tile, raised onto terrain if any.
fn Map::draw_extrusions(
  self : Map,
  index : Int32,
  layer : @style.StyleLayer,
  e : @style.ExtrusionPaint,
  shared : Paint,
  d : Draw,
  light : @render_webgl2.ExtrusionLight,
  on_terrain : Bool,
  pass : Int32,
) -> Unit {
  let t = self.transform
  let zoom = t.camera.zoom
  // Heights were taken at the tile's zoom and one deeper.
  let mix = @cmp.maximum(0.0, @cmp.minimum(1.0, zoom - d.id.z.to_double()))
  let exaggeration = if on_terrain { self.exaggeration() } else { 0.0 }
  let shadow = self.tile_shadow(d.id)
  let cut = self.cut_frame.map(f => {
    self.transform.tile_light_matrix(f, d.id, @core.TILE_EXTENT)
  })
  for m in d.meshes {
    if m.layer != index || m.ground is None {
      continue
    }
    let p = mesh_paint(m, layer, shared, zoom)
    // A pattern draws nothing while its image is missing, as in MapLibre.
    let pattern = match p.pattern {
      Some(name) =>
        match self.pattern(name) {
          Some(pos) => Some(pos)
          None => continue
        }
      None => None
    }
    let at = self.translated(d.at, layer, d.id)
    self.draw_by_state(m, layer, p, zoom, p => {
      self.renderer.draw_extrusion(
        m.mesh,
        at,
        (p.r, p.g, p.b),
        if pattern is Some(_) {
          p.opacity
        } else {
          p.a
        },
        light,
        e.vertical_gradient,
        mix,
        t.pixels_per_meter(),
        exaggeration,
        pattern~,
        pass~,
        shadow~,
        cut~,
      )
    })
  }
}
