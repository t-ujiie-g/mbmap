///|
/// The frame's shadows: the shadow map's view over world pixels (`flat`) and,
/// on the globe past half its transition, over the unit sphere (`sphere`, which
/// is then used); how dark they are, and the sun's share of the ground's light.
priv struct Shadows {
  flat : @core.ShadowView
  sphere : @core.ShadowView?
  intensity : Double
  ground : Double
}

///|
/// The shadows of the style's `lights` for this frame: None without
/// `cast-shadows`, or with the sun at or below the horizon.
fn Map::frame_shadows(self : Map) -> Shadows? {
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
/// Takes this frame's shadows and, if any, draws the casters (extrusions, and
/// custom layers through their shadow pass) into the shadow map.
fn Map::draw_shadow_map(
  self : Map,
  draws_of : @hashmap.HashMap[String, Array[Draw]],
) -> Unit {
  self.shadows = self.frame_shadows()
  guard self.shadows is Some(s) else {
    self.renderer.set_shadow(0, @core.Mat4::identity(), 0.0, 0.0)
    return
  }
  match s.sphere {
    Some(v) => self.renderer.set_shadow(2, v.matrix, s.intensity, v.texel)
    None =>
      self.renderer.set_shadow(
        1,
        @core.Mat4::identity(),
        s.intensity,
        s.flat.texel,
      )
  }
  let zoom = self.transform.camera.zoom
  let light = self.extrusion_light()
  let on_terrain = self.terrain_source() is Some(_)
  self.renderer.begin_shadow_map()
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
