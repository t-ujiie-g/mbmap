///|
/// Adds or replaces style image `name`: `width` x `height` straight RGBA pixels,
/// `pixel_ratio` of them per CSS pixel, an SDF when `sdf` (MapLibre's `addImage`).
/// False when the pixels do not match the size.
pub fn Map::add_image(
  self : Map,
  name : String,
  width : Int32,
  height : Int32,
  data : FixedArray[Byte],
  pixel_ratio~ : Double = 1.0,
  sdf~ : Bool = false,
) -> Bool {
  if width <= 0 ||
    height <= 0 ||
    data.length() != width * height * 4 ||
    !(pixel_ratio > 0.0) {
    return false
  }
  let image : @render_webgl2.StyleImage = {
    width,
    height,
    data,
    pixel_ratio,
    sdf,
  }
  // Icons are laid out again unless the new pixels have the old size.
  match self.images.get(name) {
    Some(b) if b.width == width &&
      b.height == height &&
      b.pixel_ratio == pixel_ratio &&
      b.sdf == sdf => ()
    _ => self.changed_images.add(name)
  }
  self.images.set(name, image)
  self.renderer.update_icon(name, image)
  self.images_changed(name)
  true
}

///|
/// Removes style image `name`; false if there is none.
pub fn Map::remove_image(self : Map, name : String) -> Bool {
  guard self.images.get(name) is Some(_) else { return false }
  self.images.remove(name)
  self.changed_images.add(name)
  self.images_changed(name)
  true
}

///|
/// Calls `f` with the name of an image the style asks for but lacks, once per
/// name until it is added (MapLibre's `styleimagemissing`).
pub fn Map::on_missing_image(self : Map, f : (String) -> Unit) -> Unit {
  self.on_missing_image = f
}

///|
/// Patterns are packed again from the images as they are next drawn.
fn Map::images_changed(self : Map, name : String) -> Unit {
  self.missing_images.remove(name)
  self.renderer.clear_patterns()
  self.content_version += 1
  self.idle_fired = false
  self.request_render()
}

///|
/// Where pattern `name` lies in the atlas, adding it from the style's images;
/// None (reported once) when the style has no such image.
fn Map::pattern(self : Map, name : String) -> @render_webgl2.PatternPosition? {
  if self.renderer.pattern(name) is Some(p) {
    return Some(p)
  }
  match self.images.get(name) {
    Some(image) => self.renderer.add_pattern(name, image)
    None => {
      self.report_missing(name)
      None
    }
  }
}

///|
/// Fires `on_missing_image` for `name`, once until it is added.
fn Map::report_missing(self : Map, name : String) -> Unit {
  if !self.missing_images.contains(name) && self.images.get(name) is None {
    self.missing_images.add(name)
    (self.on_missing_image)(name)
  }
}

///|
/// Holds tiles with icons in the workers while `loading` (a sprite is on its
/// way), as MapLibre's tiles wait for the sprite.
pub fn Map::hold_images(self : Map, loading : Bool) -> Unit {
  if self.images_loading != loading {
    self.images_loading = loading
    self.changed_images.add("")
    self.request_render()
  }
}

///|
/// `names` and, per image, its width, height, pixel ratio and sdf (0 or 1).
extern "js" fn post_images(
  w : Worker,
  names : FixedArray[String],
  sizes : FixedArray[Double],
  loading : Bool,
) -> Unit =
  #|(w, names, d, loading) => w.postMessage({ type: "images", loading,
  #|  images: names.map((n, i) => [n, d[i * 4], d[i * 4 + 1], d[i * 4 + 2], d[i * 4 + 3] === 1]) })

///|
/// Tells the workers the images' sizes when some changed, and loads again the
/// tiles whose icons used the changed ones; tiles still loading too, unless
/// the workers were holding them for a sprite.
fn Map::send_images(self : Map) -> Unit {
  guard !self.changed_images.is_empty() else { return }
  let names = FixedArray::make(self.images.length(), "")
  let sizes = FixedArray::make(self.images.length() * 4, 0.0)
  let mut i = 0
  for name, image in self.images {
    names[i] = name
    sizes[i * 4] = image.width.to_double()
    sizes[i * 4 + 1] = image.height.to_double()
    sizes[i * 4 + 2] = image.pixel_ratio
    sizes[i * 4 + 3] = if image.sdf { 1.0 } else { 0.0 }
    i += 1
  }
  let sources = []
  for l in self.style.layers {
    if l.icon is Some(_) {
      sources.push(l.source)
    }
  }
  let held = self.images_held
  self.images_held = self.images_loading && sources.length() > 0
  for w in self.workers {
    post_images(w, names, sizes, self.images_held)
  }
  for src in self.sources {
    guard sources.contains(src.source.id) else { continue }
    let gone = []
    for key, e in src.tiles {
      match e.state {
        Ready(m) if uses_images(m, self.changed_images) => e.state = Stale(m)
        Loading(_) if !held && !self.cancel_load(e) => gone.push(key)
        _ => ()
      }
    }
    for key in gone {
      src.tiles.remove(key)
    }
  }
  self.changed_images.clear()
}

///|
fn uses_images(
  meshes : Array[LayerMesh],
  names : @hashset.HashSet[String],
) -> Bool {
  for m in meshes {
    if m.labels is Some({ icon: Some(ic), .. }) {
      for n in ic.names {
        if names.contains(n) {
          return true
        }
      }
    }
  }
  false
}

///|
/// Frees mesh `m`'s icons, if it has any.
fn release_icons(r : @render_webgl2.Renderer, m : LayerMesh) -> Unit {
  if m.labels is Some({ icon: Some(ic), .. }) {
    r.release(ic.mesh)
  }
}

///|
/// Draws fill mesh `m` with its pattern (nothing while the image is missing, as
/// MapLibre); its outline, in the pattern unless it has an outline color, goes
/// to `outlines`.
fn Map::draw_fill_pattern(
  self : Map,
  index : Int32,
  layer : @style.StyleLayer,
  m : LayerMesh,
  p : Paint,
  at : @render_webgl2.Placement,
  outlines : Array[() -> Unit],
) -> Unit {
  let zoom = self.transform.camera.zoom
  guard p.pattern is Some(name) && self.pattern(name) is Some(pos) else {
    return
  }
  self.draw_by_state(m, layer, p, zoom, p => {
    let slots = self.slots(index, m, p, zoom)
    self.renderer.draw_fill_pattern(m.mesh, at, slots, pos, at.pattern)
  })
  if layer.antialias {
    outlines.push(() => {
      self.draw_by_state(m, layer, p, zoom, outline=true, p => {
        let slots = self.slots(index, m, p, zoom)
        if layer.outline_color is Some(_) {
          self.renderer.draw_fill_outline(m.mesh, at, slots)
        } else {
          self.renderer.draw_fill_outline_pattern(
            m.mesh,
            at,
            slots,
            pos,
            at.pattern,
          )
        }
      })
    })
  }
}

///|
/// Draws a background pattern over the tiles that cover the view (MapLibre's
/// `drawBackground` with a pattern).
fn Map::draw_background_pattern(self : Map, layer : @style.StyleLayer) -> Unit {
  let t = self.transform
  let p = paint_of(layer, t.camera.zoom, JsProps::none())
  guard p.pattern is Some(name) && self.pattern(name) is Some(pos) else {
    return
  }
  let z = t.tile_zoom(0, @core.MAX_TILE_ZOOM)
  let tiles = match self.globe {
    Some(g) if g.is_globe() =>
      self.globe_cover(g, 512, 0, @core.MAX_TILE_ZOOM, false)
    _ => t.covering_tiles(0, z)
  }
  for id in tiles {
    let matrix = t.tile_matrix(id, @core.TILE_EXTENT)
    let matrix = match self.window {
      None => matrix
      Some(w) => w.matrix.mul(matrix)
    }
    self.renderer.draw_background_pattern(
      matrix,
      globe?=self.globe_tile(id),
      pos,
      pattern_tile(t, id),
      p.opacity,
      rgba_of(p.color),
    )
  }
}
