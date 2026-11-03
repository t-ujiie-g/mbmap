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
  self.images.set(name, { width, height, data, pixel_ratio, sdf, })
  self.images_changed(name)
  true
}

///|
/// Removes style image `name`; false if there is none.
pub fn Map::remove_image(self : Map, name : String) -> Bool {
  guard self.images.get(name) is Some(_) else { return false }
  self.images.remove(name)
  self.images_changed(name)
  true
}

///|
pub fn Map::has_image(self : Map, name : String) -> Bool {
  self.images.get(name) is Some(_)
}

///|
/// The names of the style's images.
pub fn Map::image_names(self : Map) -> Array[String] {
  self.images.iter().map(e => e.0).collect()
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
      if !self.missing_images.contains(name) {
        self.missing_images.add(name)
        (self.on_missing_image)(name)
      }
      None
    }
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
  let c = p.color
  for id in t.covering_tiles(0, z) {
    let matrix = t.tile_matrix(id, @core.TILE_EXTENT)
    let matrix = match self.window {
      None => matrix
      Some(w) => w.matrix.mul(matrix)
    }
    self.renderer.draw_background_pattern(
      matrix,
      pos,
      pattern_tile(t, id),
      p.opacity,
      [c.r, c.g, c.b, c.a],
    )
  }
}
