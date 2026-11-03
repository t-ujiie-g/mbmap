///|
/// MapLibre's `renderColorRamp` for line gradients: `width` straight RGBA
/// pixels per row, a row per line slice in `clips` (start and end along its
/// line, pairs) whose pixel `i` takes `color` at the progress `i / (width - 1)`
/// of the way from start to end; one row over 0 to 1 when `clips` is empty.
pub fn color_ramp(
  clips : Array[Double],
  width : Int32,
  color : (Double) -> (Double, Double, Double, Double),
) -> FixedArray[Byte] {
  let rows = if clips.is_empty() { 1 } else { clips.length() / 2 }
  let out = FixedArray::make(width * rows * 4, b'\x00')
  let byte = (v : Double) => {
    (@cmp.maximum(0.0, @cmp.minimum(1.0, v)) * 255.0 + 0.5)
    .floor()
    .to_int()
    .to_byte()
  }
  for row in 0..<rows {
    let (start, end) = if clips.is_empty() {
      (0.0, 1.0)
    } else {
      (clips[row * 2], clips[row * 2 + 1])
    }
    for i in 0..<width {
      let p = i.to_double() / (width - 1).to_double()
      let (r, g, b, a) = color(start * (1.0 - p) + end * p)
      let at = (row * width + i) * 4
      // A transparent pixel is 0 throughout (MapLibre divides by its alpha).
      if a > 0.0 {
        out[at] = byte(r)
        out[at + 1] = byte(g)
        out[at + 2] = byte(b)
        out[at + 3] = byte(a)
      }
    }
  }
  out
}

///|
/// MapLibre's ramp width for a step gradient: enough pixels for the longest
/// line (`length` tiles) at 1024 px per tile, over `overzoom` levels deeper,
/// as a power of two from 256 to `max_size`; 256 for an interpolated one.
pub fn ramp_width(
  step~ : Bool,
  length~ : Double,
  overzoom~ : Double,
  max_size~ : Int32,
) -> Int32 {
  if !step {
    return 256
  }
  let want = length * 1024.0 * overzoom
  let mut w = 1
  while w.to_double() < want && w < max_size {
    w = w * 2
  }
  @cmp.maximum(256, @cmp.minimum(max_size, w))
}
