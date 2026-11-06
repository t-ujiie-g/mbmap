///|
/// Highest zoom a `TileId` can address; keeps `TileId::key` within Int64.
pub const MAX_TILE_ZOOM : Int32 = 28

///|
/// A valid tile address in the XYZ scheme (y grows southwards). Construct it
/// with `TileId::new`, which rejects out-of-range coordinates.
#derive(Debug, Eq, Hash)
pub struct TileId {
  z : Int32
  x : Int32
  y : Int32
}

///|
pub fn TileId::new(z : Int32, x : Int32, y : Int32) -> TileId? {
  if z < 0 || z > MAX_TILE_ZOOM {
    return None
  }
  let n = 1 << z
  if x < 0 || x >= n || y < 0 || y >= n {
    return None
  }
  Some({ z, x, y, })
}

///|
/// Unique per tile across all zooms.
pub fn TileId::key(self : TileId) -> Int64 {
  (((1L << self.z) * self.y.to_int64() + self.x.to_int64()) << 5) |
  self.z.to_int64()
}

///|
pub fn TileId::parent(self : TileId) -> TileId? {
  if self.z == 0 {
    None
  } else {
    Some({ z: self.z - 1, x: self.x >> 1, y: self.y >> 1, })
  }
}

///|
/// The four tiles at `z + 1`, ordered NW, NE, SW, SE.
pub fn TileId::children(self : TileId) -> FixedArray[TileId]? {
  if self.z >= MAX_TILE_ZOOM {
    return None
  }
  let z = self.z + 1
  let x = self.x * 2
  let y = self.y * 2
  Some([
    { z, x, y, },
    { z, x: x + 1, y, },
    { z, x, y: y + 1, },
    { z, x: x + 1, y: y + 1, },
  ])
}

///|
/// Bounds in Web Mercator world space ([0, 1] on both axes).
pub fn TileId::mercator_bounds(self : TileId) -> BBox {
  let n = (1 << self.z).to_double()
  {
    min_x: self.x.to_double() / n,
    min_y: self.y.to_double() / n,
    max_x: (self.x + 1).to_double() / n,
    max_y: (self.y + 1).to_double() / n,
  }
}

///|
/// Bounds in degrees: `min_x`/`max_x` are west/east, `min_y`/`max_y` south/north.
pub fn TileId::lnglat_bounds(self : TileId) -> BBox {
  let m = self.mercator_bounds()
  {
    min_x: lng_from_mercator_x(m.min_x),
    min_y: lat_from_mercator_y(m.max_y),
    max_x: lng_from_mercator_x(m.max_x),
    max_y: lat_from_mercator_y(m.min_y),
  }
}

///|
/// The tile at zoom `z` containing `coord`; coordinates outside the world are
/// clamped to the edge tiles. Returns `None` only for an invalid `z`.
pub fn tile_containing(coord : MercatorCoord, z : Int32) -> TileId? {
  if z < 0 || z > MAX_TILE_ZOOM {
    return None
  }
  let n = 1 << z
  let clamp = (v : Double) => {
    let i = (v * n.to_double()).floor()
    if i.is_nan() || i < 0.0 {
      0
    } else if i >= n.to_double() {
      n - 1
    } else {
      i.to_int()
    }
  }
  Some({ z, x: clamp(coord.x), y: clamp(coord.y), })
}

///|
/// The key under which a packed tile's group properties carry the geometry
/// type, for paint that reads `["geometry-type"]`.
pub const GEOMETRY_TYPE_KEY : String = "$type"
