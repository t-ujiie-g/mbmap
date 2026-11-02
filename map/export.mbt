///|
/// The part of a larger frame being drawn: `matrix` takes the whole frame's
/// clip space to the part's, `bottom` is the part's bottom edge in device
/// pixels from the whole frame's bottom.
priv struct Window {
  matrix : @core.Mat4
  bottom : Double
}

///|
/// Whether the map has settled: its tiles loaded and drawn (`idle` fired since
/// the last change).
pub fn Map::is_idle(self : Map) -> Bool {
  self.idle_fired
}

///|
/// The largest side `render_region` draws at once.
pub fn Map::max_region(self : Map) -> Int32 {
  self.renderer.max_side()
}

///|
/// Pixels (a Uint8ClampedArray, RGBA, top row first) of the `width` x `height`
/// device-pixel part at (`x`, `y`) of the current view drawn `ratio` device
/// pixels to the CSS pixel, with the tiles loaded now. The canvas is left as
/// it is.
pub fn Map::render_region(
  self : Map,
  ratio : Double,
  x : Int32,
  y : Int32,
  width : Int32,
  height : Int32,
) -> @render_webgl2.JsBuffer {
  let t = self.transform
  let full_w = (t.width * ratio).round()
  let full_h = (t.height * ratio).round()
  let (w, h) = (width.to_double(), height.to_double())
  let bottom = full_h - y.to_double() - h
  let matrix = @core.Mat4::identity()
    .translate(
      (full_w - 2.0 * x.to_double()) / w - 1.0,
      (full_h - 2.0 * bottom) / h - 1.0,
      0.0,
    )
    .scale(full_w / w, full_h / h, 1.0)
  self.window = Some({ matrix, bottom, })
  self.frame_count += 1
  self.renderer.begin_offscreen(width, height)
  let (draws_of, _) = self.draws(ratio, load=false)
  self.draw_frame(draws_of, ratio)
  self.window = None
  self.renderer.end_offscreen()
}
