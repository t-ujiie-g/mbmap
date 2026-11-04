// Ported from @maplibre/geojson-vt 6.3.0: MIT License, Copyright (c) 2025
// MapLibre contributors, and ISC License, Copyright (c) 2024, Mapbox. See NOTICE.

///|
/// geojson-vt's options and defaults: tiles to `index_max_zoom` (or `index_max_points`)
/// cut up front, the rest on demand; `tolerance`, `buffer` in tile units; `line_metrics`
/// tells line features where they lie along their line (`CLIP_START`, `CLIP_END`).
pub(all) struct TilerOptions {
  max_zoom : Int32
  index_max_zoom : Int32
  index_max_points : Int32
  tolerance : Double
  extent : Int32
  buffer : Int32
  wrap : Bool
  line_metrics : Bool
}

///|
pub fn TilerOptions::default() -> TilerOptions {
  {
    max_zoom: 14,
    index_max_zoom: 5,
    index_max_points: 100000,
    tolerance: 3.0,
    extent: @core.TILE_EXTENT,
    buffer: 64,
    wrap: true,
    line_metrics: false,
  }
}

///|
/// Cuts a table's features into vector tiles: some up front, the rest when
/// `tile` asks for them (geojson-vt's `GeoJSONVT` with a `TileIndex`).
pub struct Tiler {
  priv options : TilerOptions
  priv tiles : Map[Int64, Tile]
}

///|
fn tile_key(z : Int32, x : Int32, y : Int32) -> Int64 {
  ((1L << z) * y.to_int64() + x.to_int64()) * 32L + z.to_int64()
}

///|
/// Deepest zoom tiles are cut at, geojson-vt's limit on `maxZoom`.
pub const MAX_ZOOM : Int32 = 24

///|
/// Indexes `table`, whose coordinates are longitude and latitude (`trig`
/// projects them; see `Trig`).
pub fn Tiler::new(
  table : @geom.Table,
  options~ : TilerOptions = TilerOptions::default(),
  trig~ : Trig = Trig::moonbit(),
) -> Tiler {
  let max_zoom = @cmp.maximum(0, @cmp.minimum(MAX_ZOOM, options.max_zoom))
  let options = { ..options, max_zoom, }
  let t : Tiler = { options, tiles: Map([]), }
  let z = (1 << max_zoom).to_double() * options.extent.to_double()
  let sq_tolerance = options.tolerance / z * (options.tolerance / z)
  let metrics = options.line_metrics
  let mut set = convert(table, sq_tolerance, trig, metrics~)
  let buffer = options.buffer.to_double() / options.extent.to_double()
  if options.wrap {
    set = wrap(set, buffer, metrics~)
  } else {
    let inf = @double.infinity
    let in_x = clip(set, 1.0, -buffer, 1.0 + buffer, 0, -inf, inf, metrics~).unwrap_or([],
    )
    set = clip(in_x, 1.0, -buffer, 1.0 + buffer, 1, -inf, inf, metrics~).unwrap_or([],
    )
  }
  if !set.is_empty() {
    t.split(set, 0, 0, 0, None)
  }
  t
}

///|
/// geojson-vt's `splitTile`: cuts `set` from tile (z, x, y) down, either as
/// far as the index limits (`target` None) or toward the target tile.
fn Tiler::split(
  self : Tiler,
  set : Array[FRef],
  z : Int32,
  x : Int32,
  y : Int32,
  target : (Int32, Int32, Int32)?,
) -> Unit {
  let o = self.options
  let stack : Array[(Array[FRef], Int32, Int32, Int32)] = [(set, z, x, y)]
  while stack.pop() is Some((features, z, x, y)) {
    let z2 = (1 << z).to_double()
    let key = tile_key(z, x, y)
    let tile = match self.tiles.get(key) {
      Some(t) => t
      None => {
        let t = create_tile(features, z, x, y, o)
        self.tiles[key] = t
        t
      }
    }
    // Kept so that a later request can drill down from here.
    tile.source = Some(features)
    match target {
      None =>
        if z == o.index_max_zoom || tile.num_points <= o.index_max_points {
          continue
        }
      Some((cz, cx, cy)) => {
        if z == o.max_zoom || z == cz {
          continue
        }
        let steps = cz - z
        if x != cx >> steps || y != cy >> steps {
          continue
        }
      }
    }
    tile.source = None
    if features.is_empty() {
      continue
    }
    let k1 = 0.5 * o.buffer.to_double() / o.extent.to_double()
    let k2 = 0.5 - k1
    let k3 = 0.5 + k1
    let k4 = 1.0 + k1
    let xd = x.to_double()
    let yd = y.to_double()
    let left = clip(
      features,
      z2,
      xd - k1,
      xd + k3,
      0,
      tile.min_x,
      tile.max_x,
      metrics=o.line_metrics,
    )
    let right = clip(
      features,
      z2,
      xd + k2,
      xd + k4,
      0,
      tile.min_x,
      tile.max_x,
      metrics=o.line_metrics,
    )
    let mut tl = None
    let mut bl = None
    let mut tr = None
    let mut br = None
    if left is Some(l) {
      tl = clip(
        l,
        z2,
        yd - k1,
        yd + k3,
        1,
        tile.min_y,
        tile.max_y,
        metrics=o.line_metrics,
      )
      bl = clip(
        l,
        z2,
        yd + k2,
        yd + k4,
        1,
        tile.min_y,
        tile.max_y,
        metrics=o.line_metrics,
      )
    }
    if right is Some(r) {
      tr = clip(
        r,
        z2,
        yd - k1,
        yd + k3,
        1,
        tile.min_y,
        tile.max_y,
        metrics=o.line_metrics,
      )
      br = clip(
        r,
        z2,
        yd + k2,
        yd + k4,
        1,
        tile.min_y,
        tile.max_y,
        metrics=o.line_metrics,
      )
    }
    stack.push((tl.unwrap_or([]), z + 1, x * 2, y * 2))
    stack.push((bl.unwrap_or([]), z + 1, x * 2, y * 2 + 1))
    stack.push((tr.unwrap_or([]), z + 1, x * 2 + 1, y * 2))
    stack.push((br.unwrap_or([]), z + 1, x * 2 + 1, y * 2 + 1))
  }
}

///|
/// The tile (z, x, y), cutting it from the nearest indexed ancestor if
/// needed; None if no feature reaches it (geojson-vt's `getTile`). x wraps
/// around the world when `wrap` is on.
pub fn Tiler::tile(self : Tiler, z : Int32, x : Int32, y : Int32) -> TileData? {
  if z < 0 || z > 30 {
    return None
  }
  let z2 = 1 << z
  if !self.options.wrap && (x < 0 || x >= z2) {
    return None
  }
  let x = (x + z2) & (z2 - 1)
  let key = tile_key(z, x, y)
  if self.tiles.get(key) is Some(t) {
    return Some(t.transform(self.options.extent))
  }
  let mut z0 = z
  let mut x0 = x
  let mut y0 = y
  let mut parent = None
  while parent is None && z0 > 0 {
    z0 -= 1
    x0 = x0 >> 1
    y0 = y0 >> 1
    parent = self.tiles.get(tile_key(z0, x0, y0))
  }
  guard parent is Some(p) && p.source is Some(source) else { return None }
  self.split(source, z0, x0, y0, Some((z, x, y)))
  self.tiles.get(key).map(t => t.transform(self.options.extent))
}
