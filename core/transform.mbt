///|
/// CSS pixels per tile edge at integer zooms, as in MapLibre: the world is
/// `TILE_SIZE * 2^zoom` pixels wide.
pub const TILE_SIZE : Double = 512.0

///|
/// Tile units per tile edge in packed tiles: workers rescale every layer to it.
pub const TILE_EXTENT : Int32 = 4096

///|
/// Where the map looks: its center and zoom. Bearing and pitch come later.
pub(all) struct Camera {
  center : LngLat
  zoom : Double
} derive(Debug, Eq)

///|
/// Affine map from tile units to clip space: `clip = pos * scale + translate`.
pub(all) struct TileTransform {
  scale_x : Double
  scale_y : Double
  translate_x : Double
  translate_y : Double
} derive(Debug, Eq)

///|
/// A camera applied to a viewport of `width` x `height` CSS pixels. Zoom is
/// clamped to `[min_zoom, max_zoom]` and latitude to `MAX_LATITUDE`.
pub struct Transform {
  camera : Camera
  width : Double
  height : Double
  min_zoom : Double
  max_zoom : Double
}

///|
pub fn Transform::new(
  camera : Camera,
  width : Double,
  height : Double,
  min_zoom~ : Double = 0.0,
  max_zoom~ : Double = 22.0,
) -> Transform {
  {
    camera: constrain(camera, min_zoom, max_zoom),
    width,
    height,
    min_zoom,
    max_zoom,
  }
}

///|
fn constrain(camera : Camera, min_zoom : Double, max_zoom : Double) -> Camera {
  let zoom = @cmp.maximum(min_zoom, @cmp.minimum(max_zoom, camera.zoom))
  let lat = @cmp.maximum(
    -MAX_LATITUDE,
    @cmp.minimum(MAX_LATITUDE, camera.center.lat),
  )
  let lng = camera.center.lng
  // Keep longitude in [-180, 180) so panning around the world stays bounded.
  let lng = lng - 360.0 * ((lng + 180.0) / 360.0).floor()
  { center: { lng, lat, }, zoom, }
}

///|
/// The same viewport looking through another camera.
pub fn Transform::with_camera(self : Transform, camera : Camera) -> Transform {
  { ..self, camera: constrain(camera, self.min_zoom, self.max_zoom), }
}

///|
pub fn Transform::resize(
  self : Transform,
  width : Double,
  height : Double,
) -> Transform {
  { ..self, width, height, }
}

///|
/// World width in CSS pixels at the current zoom.
pub fn Transform::world_size(self : Transform) -> Double {
  TILE_SIZE * @math.pow(2.0, self.camera.zoom)
}

///|
/// Mercator position under the screen point (x, y), measured in CSS pixels
/// from the viewport's top-left corner.
pub fn Transform::screen_to_mercator(
  self : Transform,
  x : Double,
  y : Double,
) -> MercatorCoord {
  let c = self.camera.center.to_mercator()
  let ws = self.world_size()
  {
    x: c.x + (x - self.width / 2.0) / ws,
    y: c.y + (y - self.height / 2.0) / ws,
  }
}

///|
/// Screen point (CSS pixels) of a mercator position.
pub fn Transform::mercator_to_screen(
  self : Transform,
  m : MercatorCoord,
) -> (Double, Double) {
  let c = self.camera.center.to_mercator()
  let ws = self.world_size()
  ((m.x - c.x) * ws + self.width / 2.0, (m.y - c.y) * ws + self.height / 2.0)
}

///|
/// The camera after dragging the map by (dx, dy) CSS pixels.
pub fn Transform::panned(self : Transform, dx : Double, dy : Double) -> Camera {
  let m = self.screen_to_mercator(self.width / 2.0 - dx, self.height / 2.0 - dy)
  constrain(
    { center: m.to_lnglat(), zoom: self.camera.zoom, },
    self.min_zoom,
    self.max_zoom,
  )
}

///|
/// The camera at `zoom` that keeps the map point under screen point (x, y) fixed.
pub fn Transform::zoomed_around(
  self : Transform,
  x : Double,
  y : Double,
  zoom : Double,
) -> Camera {
  let zoom = @cmp.maximum(self.min_zoom, @cmp.minimum(self.max_zoom, zoom))
  let anchor = self.screen_to_mercator(x, y)
  let ws = TILE_SIZE * @math.pow(2.0, zoom)
  let center : MercatorCoord = {
    x: anchor.x - (x - self.width / 2.0) / ws,
    y: anchor.y - (y - self.height / 2.0) / ws,
  }
  constrain({ center: center.to_lnglat(), zoom, }, self.min_zoom, self.max_zoom)
}

///|
/// Integer tile zoom for a source with tiles of `TILE_SIZE` pixels, limited
/// to the source's zoom range (higher camera zooms overzoom `max_tile_zoom`).
pub fn Transform::tile_zoom(
  self : Transform,
  min_tile_zoom : Int32,
  max_tile_zoom : Int32,
) -> Int32 {
  let z = self.camera.zoom.floor().to_int()
  @cmp.maximum(min_tile_zoom, @cmp.minimum(max_tile_zoom, z))
}

///|
/// Tiles at zoom `z` that intersect the viewport, nearest to the center first.
pub fn Transform::covering_tiles(self : Transform, z : Int32) -> Array[TileId] {
  let tl = self.screen_to_mercator(0.0, 0.0)
  let br = self.screen_to_mercator(self.width, self.height)
  let n = 1 << z
  let scale = n.to_double()
  let clamp = (v : Double) => {
    let i = (v * scale).floor()
    if i < 0.0 {
      0
    } else if i >= scale {
      n - 1
    } else {
      i.to_int()
    }
  }
  let x0 = clamp(tl.x)
  let x1 = clamp(br.x)
  let y0 = clamp(tl.y)
  let y1 = clamp(br.y)
  let c = self.camera.center.to_mercator()
  let tiles : Array[(Double, TileId)] = []
  for x in x0..<=x1 {
    for y in y0..<=y1 {
      let dx = (x.to_double() + 0.5) / scale - c.x
      let dy = (y.to_double() + 0.5) / scale - c.y
      tiles.push((dx * dx + dy * dy, { z, x, y, }))
    }
  }
  tiles.sort_by((a, b) => a.0.compare(b.0))
  tiles.map(t => t.1)
}

///|
/// Maps tile units (`extent` per tile edge) of `tile` to clip space.
pub fn Transform::tile_transform(
  self : Transform,
  tile : TileId,
  extent : Int32,
) -> TileTransform {
  let ws = self.world_size()
  let tiles = (1 << tile.z).to_double()
  let units = ws / tiles / extent.to_double()
  let c = self.camera.center.to_mercator()
  // Tile origin in screen pixels.
  let ox = (tile.x.to_double() / tiles - c.x) * ws + self.width / 2.0
  let oy = (tile.y.to_double() / tiles - c.y) * ws + self.height / 2.0
  {
    scale_x: units * 2.0 / self.width,
    scale_y: -units * 2.0 / self.height,
    translate_x: ox * 2.0 / self.width - 1.0,
    translate_y: 1.0 - oy * 2.0 / self.height,
  }
}
