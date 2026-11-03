///|
/// A `raster-dem` tile's border elevations (`@raster.dem_edges`, to redo its
/// neighbors' edge slopes), its heights (a Float32Array, row by row) for terrain
/// lookups, and the `lowest` and `highest` of them.
priv struct DemTile {
  edges : FixedArray[Double]
  heights : @render_webgl2.JsBuffer
  size : Int32
  lowest : Double
  highest : Double
}

///|
/// The lowest and highest of `heights`.
extern "js" fn height_range(
  heights : @render_webgl2.JsBuffer,
) -> FixedArray[Double] =
  #|(h) => { let lo = Infinity, hi = -Infinity; for (const v of h) { if (v < lo) lo = v; if (v > hi) hi = v; } return [lo, hi]; }

///|
extern "js" fn f64_array(
  buffer : @render_webgl2.JsBuffer,
) -> FixedArray[Double] =
  #|(b) => Array.from(b)

///|
fn dem_of(meshes : Array[LayerMesh]) -> (@render_webgl2.Mesh, DemTile)? {
  for m in meshes {
    if m.dem is Some(d) {
      return Some((m.mesh, d))
    }
  }
  None
}

///|
/// Redoes the edge slopes between `id` and its loaded neighbors on both sides of
/// each shared edge, so a hillshade shows no seams (MapLibre backfills borders
/// the same way). Sides are 0 top, 1 bottom, 2 left, 3 right.
fn Map::stitch_dem(self : Map, src : SourceTiles, id : @core.TileId) -> Unit {
  guard src.ready(id).bind(dem_of) is Some((mesh, own)) else { return }
  self.content_version += 1
  let n = 1 << id.z
  let neighbors = [(0, 0, -1, 1), (1, 0, 1, 0), (2, -1, 0, 3), (3, 1, 0, 2)]
  for s in neighbors {
    let (side, dx, dy, opposite) = s
    let y = id.y + dy
    guard y >= 0 && y < n else { continue }
    let x = (id.x + dx + n) % n
    guard @core.TileId::new(id.z, x, y) is Some(nid) &&
      src.ready(nid).bind(dem_of) is Some((nmesh, other)) &&
      other.size == own.size else {
      continue
    }
    let mine = @raster.edge_slopes(own.edges, other.edges, side, own.size, id.z)
    let theirs = @raster.edge_slopes(
      other.edges,
      own.edges,
      opposite,
      own.size,
      id.z,
    )
    // Each tile's border is the other's edge, as in MapLibre's prepared slopes.
    self.renderer.update_slopes(mesh, side, mine)
    self.renderer.update_slopes(mesh, side, theirs, border=true)
    self.renderer.update_slopes(nmesh, opposite, theirs)
    self.renderer.update_slopes(nmesh, opposite, mine, border=true)
  }
}

///|
/// The height in meters at (`x`, `y`), tile fractions, between pixel centers.
/// Past the outer centers it reads `neighbor(dx, dy)` (a same-size tile beside
/// it) or repeats the edge pixels, as MapLibre backfills borders.
fn DemTile::height_at(
  self : DemTile,
  x : Double,
  y : Double,
  neighbor~ : (Int32, Int32) -> DemTile? = (_, _) => None,
) -> Double {
  let size = self.size
  let fx = x * size.to_double() - 0.5
  let fy = y * size.to_double() - 0.5
  let side = (v : Int32) => if v < 0 { -1 } else if v >= size { 1 } else { 0 }
  let at = (x : Int32, y : Int32) => {
    let (dx, dy) = (side(x), side(y))
    if (dx != 0 || dy != 0) && neighbor(dx, dy) is Some(n) && n.size == size {
      f32_at(n.heights, (y - dy * size) * size + x - dx * size)
    } else {
      let cx = @cmp.maximum(0, @cmp.minimum(size - 1, x))
      let cy = @cmp.maximum(0, @cmp.minimum(size - 1, y))
      f32_at(self.heights, cy * size + cx)
    }
  }
  let x0 = fx.floor().to_int()
  let y0 = fy.floor().to_int()
  let tx = fx - x0.to_double()
  let ty = fy - y0.to_double()
  let top = at(x0, y0) * (1.0 - tx) + at(x0 + 1, y0) * tx
  let bottom = at(x0, y0 + 1) * (1.0 - tx) + at(x0 + 1, y0 + 1) * tx
  top * (1.0 - ty) + bottom * ty
}

///|
/// How a color relief packs a source's elevations into RGB (MapLibre's
/// `getUnpackVector`): the source's own encoding, or Terrarium's for GSI's
/// (which no linear unpacking reads).
fn relief_unpack(e : @style.DemEncoding) -> FixedArray[Double] {
  match e {
    Mapbox => [6553.6, 25.6, 0.1, 10000.0]
    Terrarium | Gsi => [256.0, 1.0, 1.0 / 256.0, 32768.0]
    Custom(r, g, b, base) => [r, g, b, base]
  }
}

///|
/// The ramp of `color-relief-color` `e` at elevation `stops` (MapLibre's
/// `_createColorRamp`: none is one transparent stop at 0 m, one is repeated a
/// meter higher), made once per expression and encoding.
fn Map::relief_ramp(
  self : Map,
  e : @style.Expr,
  stops : Array[Double],
  encoding : @style.DemEncoding,
) -> @render_webgl2.Gradient {
  match self.relief_ramps.search_by(r => r.0 == e && r.1 == encoding) {
    Some(i) => self.relief_ramps[i].2
    None => {
      let at : Array[Double] = if stops.is_empty() { [0.0] } else { stops }
      let colors = at.map(h => {
        match e.eval(0.0, { ..JsProps::none(), elevation: h, }) {
          Color(c) if !stops.is_empty() => (c.r, c.g, c.b, c.a)
          _ => (0.0, 0.0, 0.0, 0.0)
        }
      })
      let at = if at.length() < 2 { [at[0], at[0] + 1.0] } else { at }
      let pixels = FixedArray::make(at.length() * 4, b'\x00')
      let byte = (v : Double) => (v * 255.0).round().to_int().to_byte()
      for i in 0..<at.length() {
        let (r, g, b, a) = colors[@cmp.minimum(i, colors.length() - 1)]
        if a > 0.0 {
          pixels[i * 4] = byte(r)
          pixels[i * 4 + 1] = byte(g)
          pixels[i * 4 + 2] = byte(b)
          pixels[i * 4 + 3] = byte(a)
        }
      }
      let g = self.renderer.relief_ramp(
        FixedArray::from_array(at),
        pixels,
        relief_unpack(encoding),
      )
      self.relief_ramps.push((e, encoding, g))
      g
    }
  }
}

///|
/// Draws a DEM tile's color relief with a layer's opacity at the current zoom.
fn Map::draw_relief(
  self : Map,
  layer : @style.StyleLayer,
  relief : @style.ColorReliefPaint,
  m : LayerMesh,
  at : @render_webgl2.Placement,
) -> Unit {
  guard m.dem is Some(_) && self.style.source(layer.source) is Some(s) else {
    return
  }
  guard self.renderer.has_relief(m.mesh) else { return }
  let unpack = relief_unpack(s.encoding)
  let ramp = self.relief_ramp(layer.color, relief.stops, s.encoding)
  let opacity = number_or(
    layer.opacity.eval(self.transform.camera.zoom, JsProps::none()),
    1.0,
  )
  self.renderer.draw_relief(
    m.mesh,
    at,
    ramp,
    unpack,
    opacity~,
    nearest=relief.nearest,
  )
}

///|
/// The same-size DEM tile (`dx`, `dy`) beside `id` in `src`, if loaded.
fn dem_beside(
  src : SourceTiles,
  id : @core.TileId,
  dx : Int32,
  dy : Int32,
  size : Int32,
) -> (@render_webgl2.Mesh, DemTile)? {
  let n = 1 << id.z
  let y = id.y + dy
  guard y >= 0 && y < n else { return None }
  guard @core.TileId::new(id.z, (id.x + dx + n) % n, y) is Some(nid) &&
    src.ready(nid).bind(dem_of) is Some((mesh, dem)) &&
    dem.size == size else {
    return None
  }
  Some((mesh, dem))
}

///|
let neighbor_offsets : FixedArray[(Int32, Int32)] = [
  (-1, -1),
  (0, -1),
  (1, -1),
  (-1, 0),
  (1, 0),
  (-1, 1),
  (0, 1),
  (1, 1),
]

///|
/// Gives the DEM tiles color relief layers draw this frame their packed heights,
/// bordered by their loaded neighbors' (as MapLibre backfills DEM borders).
fn Map::prepare_relief(
  self : Map,
  draws_of : @hashmap.HashMap[String, Array[Draw]],
) -> Unit {
  for src in self.sources {
    let s = src.source
    guard self.style.layers
      .iter()
      .any(l => l.relief is Some(_) && l.source == s.id) else {
      continue
    }
    let unpack = relief_unpack(s.encoding)
    for d in draws_of.get(s.id).unwrap_or([]) {
      guard dem_of(d.meshes) is Some((mesh, own)) &&
        !self.renderer.has_relief(mesh) else {
        continue
      }
      self.renderer.relief_heights(mesh, own.heights, own.size, unpack)
      for o in neighbor_offsets {
        let (dx, dy) = o
        if dem_beside(src, d.id, dx, dy, own.size) is Some((_, other)) {
          self.renderer.relief_border(
            mesh,
            other.heights,
            own.size,
            unpack,
            dx~,
            dy~,
          )
        }
      }
    }
  }
}

///|
/// Fills the borders of `id`'s neighbors' packed heights from its own, just loaded.
fn Map::border_relief(self : Map, src : SourceTiles, id : @core.TileId) -> Unit {
  guard src.ready(id).bind(dem_of) is Some((_, own)) else { return }
  let unpack = relief_unpack(src.source.encoding)
  for o in neighbor_offsets {
    let (dx, dy) = o
    if dem_beside(src, id, dx, dy, own.size) is Some((mesh, _)) &&
      self.renderer.has_relief(mesh) {
      self.renderer.relief_border(
        mesh,
        own.heights,
        own.size,
        unpack,
        dx=-dx,
        dy=-dy,
      )
    }
  }
}
