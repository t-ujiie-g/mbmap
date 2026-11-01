///|
/// The style's light at this camera: toward the light from its `position`
/// (MapLibre's `sphericalToCartesian`, azimuth from north), turned with the
/// map's bearing when anchored to the viewport.
fn Map::extrusion_light(self : Map) -> @render_webgl2.ExtrusionLight {
  let light = self.style.light
  let zoom = self.transform.camera.zoom
  let (r, azimuth, polar) = light.position
  let a = (azimuth + 90.0) * @math.PI / 180.0
  let p = polar * @math.PI / 180.0
  let x = r * @math.cos(a) * @math.sin(p)
  let y = r * @math.sin(a) * @math.sin(p)
  let z = r * @math.cos(p)
  let direction = if light.viewport {
    let b = self.transform.camera.bearing * @math.PI / 180.0
    (
      x * @math.cos(b) - y * @math.sin(b),
      x * @math.sin(b) + y * @math.cos(b),
      z,
    )
  } else {
    (x, y, z)
  }
  let c = color_of(light.color, zoom, JsProps::none())
  {
    direction,
    intensity: number_or(light.intensity.eval(zoom, JsProps::none()), 0.5),
    color: (c.r, c.g, c.b),
  }
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
