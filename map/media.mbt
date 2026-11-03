///|
/// What image, video or canvas source `id` shows: its `picture` (JS null for
/// none) placed by `quad` (`Map::set_media`) over `tile`, uploaded into `mesh`
/// once and again when `dirty`, and every frame while `playing` (a video
/// playing, a canvas animating).
priv struct Media {
  id : String
  mut picture : @render_webgl2.Picture
  mut quad : FixedArray[Double]
  mut tile : @core.TileId?
  mut mesh : @render_webgl2.Mesh?
  mut dirty : Bool
  mut playing : Bool
}

///|
extern "js" fn picture_is_null(p : @render_webgl2.Picture) -> Bool = "(p) => p == null"

///|
fn Map::media_of(self : Map, id : String) -> Media? {
  self.media.search_by(m => m.id == id).map(i => self.media[i])
}

///|
/// Shows `picture` (JS null for nothing) for image, video or canvas source `id`
/// placed by `quad` (`Map::set_media_quad`). Until this is called for each such
/// source, the map is not idle.
pub fn Map::set_media(
  self : Map,
  id : String,
  picture : @render_webgl2.Picture,
  quad : FixedArray[Double],
) -> Unit {
  match self.media_of(id) {
    Some(m) => {
      m.picture = picture
      m.dirty = true
    }
    None =>
      self.media.push({
        id,
        picture,
        quad: [],
        tile: None,
        mesh: None,
        dirty: true,
        playing: false,
      })
  }
  self.set_media_quad(id, quad)
}

///|
/// Places source `id`'s picture by `quad`, as MapLibre's `ImageSource`
/// computes it (`npm/src/media.ts` `quadOf`): the tile z, x, y holding it, its
/// top left, top right, bottom right and bottom left corners in that tile's
/// `@core.TILE_EXTENT` units, the warp's two perspective terms and its blend,
/// 1 to draw it over a grid, and its Mercator bounds; empty for nowhere.
pub fn Map::set_media_quad(
  self : Map,
  id : String,
  quad : FixedArray[Double],
) -> Unit {
  guard self.media_of(id) is Some(m) else { return }
  m.quad = quad
  m.tile = if quad.length() == 19 {
    @core.TileId::new(quad[0].to_int(), quad[1].to_int(), quad[2].to_int())
  } else {
    None
  }
  self.changed()
}

///|
/// Whether source `id`'s picture changes by itself (a video playing, a canvas
/// animating): it is then uploaded and drawn every frame. Unlike MapLibre, the
/// map still goes idle, once the picture is shown.
pub fn Map::set_media_playing(self : Map, id : String, playing : Bool) -> Unit {
  guard self.media_of(id) is Some(m) else { return }
  m.playing = playing
  // The picture it stopped at, taken now as MapLibre's `pause` does.
  if !playing && !picture_is_null(m.picture) {
    m.mesh = self.renderer.upload_picture(m.picture, m.mesh)
  }
  self.changed()
}

///|
fn Map::changed(self : Map) -> Unit {
  self.content_version += 1
  self.idle_fired = false
  self.request_render()
}

///|
/// Forgets the pictures of sources that are no longer image sources in
/// `style`, and frees the GPU copies of those no layer draws (uploaded again
/// once one does: the facade shows a picture only once).
fn Map::prune_media(self : Map, style : Array[@style.Source]) -> Unit {
  let kept = []
  for m in self.media {
    let drawn = self.sources.iter().any(s => s.source.id == m.id)
    if !drawn && m.mesh is Some(mesh) {
      self.renderer.release(mesh)
      m.mesh = None
    }
    if style.iter().any(s => s.id == m.id && s.kind is Image) {
      kept.push(m)
    }
  }
  self.media.clear()
  self.media.push_iter(kept.iter())
}

///|
/// Image source `src`'s draw this frame, its picture uploaded if due, and
/// whether it has settled: shown, or nothing to show.
fn Map::media_draw(
  self : Map,
  src : SourceTiles,
  dpr : Double,
) -> (Draw?, Bool) {
  guard self.media_of(src.source.id) is Some(m) else { return (None, false) }
  guard !picture_is_null(m.picture) && m.tile is Some(tile) else {
    return (None, true)
  }
  if m.mesh is None || m.dirty || m.playing {
    let mesh = self.renderer.upload_picture(m.picture, m.mesh)
    if mesh is Some(_) {
      m.dirty = false
    }
    m.mesh = mesh
  }
  guard m.mesh is Some(mesh) else { return (None, false) }
  self.renderer.set_quad(mesh, m.quad)
  // Pictures reach past their tile and are not clipped (MapLibre's raster draw).
  let at = {
    ..self.placement(tile, None, dpr),
    clip: [-1.0e9, -1.0e9, 1.0e9, 1.0e9],
  }
  let layer : LayerMesh = {
    entry: 0,
    states: [],
    layer: -1,
    kind: KIND_RASTER,
    mesh,
    owned: false,
    props: None,
    paint: None,
    vertex_paint: None,
    labels: None,
    ground: None,
    dem: None,
    clips: None,
    gradient: None,
  }
  let q = m.quad
  let draw = {
    id: tile,
    at,
    meshes: [layer],
    bounds: Some((q[15], q[16], q[17], q[18])),
  }
  (Some(draw), true)
}

///|
/// Whether a picture changes by itself, so frames keep coming.
fn Map::media_playing(self : Map) -> Bool {
  self.media.iter().any(m => m.playing && !picture_is_null(m.picture))
}
