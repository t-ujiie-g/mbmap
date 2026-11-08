///|
/// Where `id`'s meshes are drawn: only the part over the tile itself, or with
/// `clip` over that descendant tile (an ancestor standing in for it).
fn Map::placement(
  self : Map,
  id : @core.TileId,
  clip : @core.TileId?,
  dpr : Double,
) -> @render_webgl2.Placement {
  let t = self.transform
  let extent = @core.TILE_EXTENT
  let globe = self.globe_tile(id)
  let rect : FixedArray[Double] = match clip {
    // A tile draws only within itself: features reach into the buffer
    // around it, which its neighbors draw too (twice blended otherwise).
    // On the globe the first and last rows of tiles reach the poles.
    None => {
      let (north, south) = match globe {
        Some(g) => (g.north, g.south)
        None => (false, false)
      }
      [
        0.0,
        if north {
          @globe.NORTH_POLE_Y.to_double()
        } else {
          0.0
        },
        extent.to_double(),
        if south {
          @globe.SOUTH_POLE_Y.to_double() + 1.0
        } else {
          extent.to_double()
        },
      ]
    }
    Some(c) => {
      let dz = c.z - id.z
      let size = (extent >> dz).to_double()
      let x0 = (c.x - (id.x << dz)).to_double() * size
      let y0 = (c.y - (id.y << dz)).to_double() * size
      [x0, y0, x0 + size, y0 + size]
    }
  }
  let matrix = t.tile_matrix(id, extent)
  // Raster tiles at rest sit on the pixel grid, as MapLibre draws them.
  let raster_matrix = t.tile_matrix(id, extent, aligned=!self.is_moving())
  let (matrix, raster_matrix) = match self.window {
    None => (matrix, raster_matrix)
    Some(w) => (w.matrix.mul(matrix), w.matrix.mul(raster_matrix))
  }
  let bounds = id.lnglat_bounds()
  {
    matrix,
    raster_matrix,
    units_per_pixel: 1.0 / (t.tile_scale(id, extent) * dpr),
    center_depth: t.center_depth(),
    clip: rect,
    latitudes: (bounds.max_y, bounds.min_y),
    pattern: pattern_tile(t, id),
    globe,
  }
}

///|
/// Where patterns start in tile `id` (MapLibre's `patternUniformValues`): its
/// corner and size in CSS pixels of the world at the integer zoom.
fn pattern_tile(
  t : @core.Transform,
  id : @core.TileId,
) -> @render_webgl2.PatternTile {
  let zoom = @cmp.maximum(0.0, t.camera.zoom.floor())
  let size = @core.TILE_SIZE * @math.pow(2.0, zoom - id.z.to_double())
  {
    x: size * id.x.to_double(),
    y: size * id.y.to_double(),
    units: size / @core.TILE_EXTENT.to_double(),
    // MapLibre's -2^z / tileSize / 8.
    height_factor: -@math.pow(2.0, id.z.to_double()) / (8.0 * @core.TILE_SIZE),
  }
}

///|
/// The tiles of `src` the view covers at its zoom.
fn Map::cover(self : Map, src : SourceTiles) -> Array[@core.TileId] {
  let t = self.transform
  let s = src.source
  let z = t.tile_zoom(s.min_zoom, s.max_zoom, tile_size=s.tile_size)
  if s.kind is Image {
    []
  } else if self.globe is Some(g) && g.is_globe() {
    let round = s.kind is (Raster | RasterDem)
    self
    .globe_cover(g, s.tile_size, s.min_zoom, s.max_zoom, round)
    .filter(id => s.covers(id.z, id.x, id.y))
  } else if t.camera.zoom + @core.zoom_shift(s.tile_size).to_double() <
    s.min_zoom.to_double() {
    []
  } else {
    // Tiles outside the source's bounds are never asked for.
    t.covering_tiles(s.min_zoom, z).filter(id => s.covers(id.z, id.x, id.y))
  }
}

///|
/// Per source: where its covering tiles' meshes go this frame (once for all
/// of the source's layers), and whether every covering tile has settled.
/// `load` asks for the tiles missing.
fn Map::draws(
  self : Map,
  dpr : Double,
  load~ : Bool,
) -> (@hashmap.HashMap[String, Array[Draw]], Bool) {
  let mut settled = true
  let draws_of : @hashmap.HashMap[String, Array[Draw]] = @hashmap.HashMap([])
  for src in self.sources {
    let s = src.source
    let cover = self.cover(src)
    if load {
      self.update_tiles(src, cover)
    }
    let draws = []
    for id in cover {
      match src.fallback(id) {
        Own(id, meshes) =>
          draws.push({
            id,
            at: self.placement(id, None, dpr),
            meshes,
            bounds: None,
          })
        Ancestor(id, meshes, clip~) =>
          draws.push({
            id,
            at: self.placement(id, Some(clip), dpr),
            meshes,
            bounds: None,
          })
        Children(kids) =>
          for kid in kids {
            draws.push({
              id: kid.0,
              at: self.placement(kid.0, None, dpr),
              meshes: kid.1,
              bounds: None,
            })
          }
        Nothing => ()
      }
      settled = settled && src.settled(id)
    }
    if s.kind is Image {
      let (draw, shown) = self.media_draw(src, dpr)
      if draw is Some(d) {
        draws.push(d)
      }
      settled = settled && shown
    }
    draws_of.set(s.id, draws)
  }
  (draws_of, settled)
}
