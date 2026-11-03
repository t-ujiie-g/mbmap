///|
/// How many zoom levels deeper tiles of `tile_size` pixels (a power of two up to
/// `TILE_SIZE`) are than `TILE_SIZE` ones at the same camera zoom.
pub fn zoom_shift(tile_size : Int32) -> Int32 {
  let mut shift = 0
  while shift < 8 && tile_size << shift < TILE_SIZE.to_int() {
    shift += 1
  }
  shift
}

///|
/// Integer tile zoom for a source with tiles of `tile_size` pixels (a power of
/// two up to `TILE_SIZE`: 256-pixel tiles take one zoom more), limited to the
/// source's zoom range (higher camera zooms overzoom `max_tile_zoom`).
pub fn Transform::tile_zoom(
  self : Transform,
  min_tile_zoom : Int32,
  max_tile_zoom : Int32,
  tile_size~ : Int32 = 512,
) -> Int32 {
  let z = self.camera.zoom.floor().to_int() + zoom_shift(tile_size)
  @cmp.maximum(min_tile_zoom, @cmp.minimum(max_tile_zoom, z))
}

///|
/// How far from the camera tiles stay at the full tile zoom, in camera
/// distances; each doubling beyond it drops one zoom level. 1.5 keeps every
/// tile of an unpitched view with an aspect ratio up to about 3 at full zoom.
const LOD_DISTANCE : Double = 1.5

///|
/// Zoom levels below a source's `min_z` that distant ground may want and still
/// be drawn from `min_z` tiles; farther ground is left to the fog.
const MIN_ZOOM_SLACK : Int32 = 2

///|
/// Non-overlapping tiles over the view, nearest the center first: `max_z` near
/// the camera, lower zooms for distant ground down to `min_z`; ground wanting
/// more than `MIN_ZOOM_SLACK` below `min_z` gets none (MapLibre drops it).
pub fn Transform::covering_tiles(
  self : Transform,
  min_z : Int32,
  max_z : Int32,
) -> Array[TileId] {
  let ws = self.world_size()
  let c = self.camera.center.to_mercator()
  // The view's footprint on the ground, in mercator units.
  let footprint = [
    self.screen_to_mercator(0.0, 0.0),
    self.screen_to_mercator(self.width, 0.0),
    self.screen_to_mercator(self.width, self.height),
    self.screen_to_mercator(0.0, self.height),
  ]
  // The camera's ground position and height, in world pixels from the center.
  let d = center_distance(self.height)
  let pitch = radians(self.camera.pitch)
  let bearing = radians(self.camera.bearing)
  let behind = d * @math.sin(pitch)
  let cam_x = -@math.sin(bearing) * behind
  let cam_y = @math.cos(bearing) * behind
  let cam_z = d * @math.cos(pitch)
  let tiles : Array[(Double, TileId)] = []
  let stack : Array[TileId] = [{ z: 0, x: 0, y: 0, }]
  while stack.pop() is Some(tile) {
    let b = tile.mercator_bounds()
    if !overlaps(footprint, b) {
      continue
    }
    // Distance from the camera to the tile's nearest ground point.
    let nx = (
        @cmp.maximum(b.min_x, @cmp.minimum(b.max_x, c.x + cam_x / ws)) - c.x
      ) *
      ws -
      cam_x
    let ny = (
        @cmp.maximum(b.min_y, @cmp.minimum(b.max_y, c.y + cam_y / ws)) - c.y
      ) *
      ws -
      cam_y
    let dist = (nx * nx + ny * ny + cam_z * cam_z).sqrt()
    let near = (levels : Int32) => {
      dist < LOD_DISTANCE * d * @math.pow(2.0, levels.to_double())
    }
    let split = if tile.z < min_z {
      if !near(max_z - min_z + MIN_ZOOM_SLACK) {
        continue
      }
      true
    } else {
      tile.z < max_z && near(max_z - tile.z - 1)
    }
    if split && tile.children() is Some(kids) {
      for k in kids {
        stack.push(k)
      }
    } else {
      let dx = (b.min_x + b.max_x) / 2.0 - c.x
      let dy = (b.min_y + b.max_y) / 2.0 - c.y
      tiles.push((dx * dx + dy * dy, tile))
    }
  }
  tiles.sort_by((a, b) => a.0.compare(b.0))
  tiles.map(t => t.1)
}

///|
/// Whether the convex polygon `poly` and the box `b` intersect: no separating
/// axis among the box's axes and the polygon's edge normals.
fn overlaps(poly : Array[MercatorCoord], b : BBox) -> Bool {
  let n = poly.length()
  // Box axes: the polygon's extent against the box's.
  let mut x0 = poly[0].x
  let mut x1 = x0
  let mut y0 = poly[0].y
  let mut y1 = y0
  for p in poly {
    x0 = @cmp.minimum(x0, p.x)
    x1 = @cmp.maximum(x1, p.x)
    y0 = @cmp.minimum(y0, p.y)
    y1 = @cmp.maximum(y1, p.y)
  }
  if x1 < b.min_x || x0 > b.max_x || y1 < b.min_y || y0 > b.max_y {
    return false
  }
  // Edge normals: the box lies wholly outside an edge if even its corner
  // farthest along the inward normal is outside. `poly` turns one way, so
  // the sign of `turn` says which side is inside.
  let turn = (poly[1].x - poly[0].x) * (poly[2].y - poly[1].y) -
    (poly[1].y - poly[0].y) * (poly[2].x - poly[1].x)
  for i in 0..<n {
    let p = poly[i]
    let q = poly[(i + 1) % n]
    // Inward normal of edge p -> q.
    let (nx, ny) = if turn > 0.0 {
      (p.y - q.y, q.x - p.x)
    } else {
      (q.y - p.y, p.x - q.x)
    }
    let cx = if nx > 0.0 { b.max_x } else { b.min_x }
    let cy = if ny > 0.0 { b.max_y } else { b.min_y }
    if (cx - p.x) * nx + (cy - p.y) * ny < 0.0 {
      return false
    }
  }
  true
}
