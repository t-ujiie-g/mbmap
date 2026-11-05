///|
/// How RGB holds an elevation: `r * R + g * G + b * B - base` meters, with
/// GSI's wrap-around for negative values and its no-data value when `gsi`.
pub(all) struct Unpack {
  r : Double
  g : Double
  b : Double
  base : Double
  gsi : Bool
}

///|
pub fn Unpack::mapbox() -> Unpack {
  { r: 6553.6, g: 25.6, b: 0.1, base: 10000.0, gsi: false, }
}

///|
pub fn Unpack::terrarium() -> Unpack {
  { r: 256.0, g: 1.0, b: 1.0 / 256.0, base: 32768.0, gsi: false, }
}

///|
pub fn Unpack::gsi() -> Unpack {
  { r: 655.36, g: 2.56, b: 0.01, base: 0.0, gsi: true, }
}

///|
/// Elevations in meters of RGBA pixels (4 bytes each, alpha ignored); NaN where
/// a GSI tile has no data.
pub fn elevations(rgba : BytesView, unpack : Unpack) -> FixedArray[Double] {
  let n = rgba.length() / 4
  FixedArray::makei(n, i => {
    let r = rgba[i * 4].to_int()
    let g = rgba[i * 4 + 1].to_int()
    let b = rgba[i * 4 + 2].to_int()
    if unpack.gsi {
      // 0.01 m steps of a 24-bit two's complement value; 2^23 is no data.
      let v = (r << 16) | (g << 8) | b
      if v == 1 << 23 {
        @double.not_a_number
      } else if v > 1 << 23 {
        (v - (1 << 24)).to_double() * 0.01
      } else {
        v.to_double() * 0.01
      }
    } else {
      r.to_double() * unpack.r +
      g.to_double() * unpack.g +
      b.to_double() * unpack.b -
      unpack.base
    }
  })
}

///|
/// The log2 of the equator's length in meters (the Web Mercator world's width),
/// written out so no log is computed.
const LOG2_WORLD_WIDTH : Double = 25.256199785269995

///|
/// MapLibre's slope scale (hillshade_prepare.fragment.glsl) for a tile of
/// `size` pixels at zoom `z`, exaggerated below zoom 15.
fn slope_scale(
  size : Int32,
  z : Int32,
  pow : (Double, Double) -> Double,
) -> Double {
  let zoom = z.to_double()
  let factor = if zoom < 2.0 { 0.4 } else if zoom < 4.5 { 0.35 } else { 0.3 }
  let exaggeration = if zoom < 15.0 { (zoom - 15.0) * factor } else { 0.0 }
  size.to_double() / pow(2.0, exaggeration + (3.0 + LOG2_WORLD_WIDTH - zoom))
}

///|
/// One slope as stored: around 128, 8 units per byte step of the scaled slope.
fn slope_byte(d : Double) -> Byte {
  let v = d / 8.0 + 128.0 / 255.0
  (@cmp.maximum(0.0, @cmp.minimum(1.0, v)) * 255.0).round().to_int().to_byte()
}

///|
/// The Sobel slopes east and south of the 3 x 3 window `a`-`i` (row by row).
fn sobel(
  a : Double,
  b : Double,
  c : Double,
  d : Double,
  f : Double,
  g : Double,
  h : Double,
  i : Double,
) -> (Double, Double) {
  (c + f + f + i - (a + d + d + g), g + h + h + i - (a + b + b + c))
}

///|
fn ground(v : Double) -> Double {
  if v.is_nan() {
    0.0
  } else {
    v
  }
}

///|
/// MapLibre's hillshade_prepare of a `size` x `size` tile at zoom `z`: slopes east
/// and south per pixel, two bytes around 128, with a pixel of border. Edges repeat
/// the tile's own pixels until `edge_slopes` redoes them; no data counts as 0 m.
pub fn hillshade_slopes(
  elev : FixedArray[Double],
  size : Int32,
  z : Int32,
  pow~ : (Double, Double) -> Double = @math.pow,
) -> Bytes {
  let at = (x : Int32, y : Int32) => {
    ground(
      elev[@cmp.maximum(0, @cmp.minimum(size - 1, y)) * size +
      @cmp.maximum(0, @cmp.minimum(size - 1, x))],
    )
  }
  let scale = slope_scale(size, z, pow)
  let side = size + 2
  let out = FixedArray::make(side * side * 2, b'\x00')
  for y in -1..<=size {
    for x in -1..<=size {
      let (sx, sy) = sobel(
        at(x - 1, y - 1),
        at(x, y - 1),
        at(x + 1, y - 1),
        at(x - 1, y),
        at(x + 1, y),
        at(x - 1, y + 1),
        at(x, y + 1),
        at(x + 1, y + 1),
      )
      out[((y + 1) * side + x + 1) * 2] = slope_byte(sx * scale)
      out[((y + 1) * side + x + 1) * 2 + 1] = slope_byte(sy * scale)
    }
  }
  Bytes::from_array(out[:])
}

///|
/// Border runs of `size` elevations each, for the next tiles' edges: rows 0, 1,
/// `size - 2`, `size - 1`, then columns 0, 1, `size - 2`, `size - 1`.
pub fn dem_edges(elev : FixedArray[Double], size : Int32) -> FixedArray[Double] {
  let runs = [0, 1, size - 2, size - 1]
  FixedArray::makei(8 * size, k => {
    let run = k / size
    let i = k % size
    if run < 4 {
      ground(elev[runs[run] * size + i])
    } else {
      ground(elev[i * size + runs[run - 4]])
    }
  })
}

///|
/// The slopes (two bytes per pixel, along the side) of one side of a tile whose
/// `dem_edges` are `own`, using `next`, the `dem_edges` of the tile beyond that
/// side. Sides are 0 top, 1 bottom, 2 left, 3 right.
pub fn edge_slopes(
  own : FixedArray[Double],
  next : FixedArray[Double],
  side : Int32,
  size : Int32,
  z : Int32,
) -> Bytes {
  let run = (edges : FixedArray[Double], r : Int32, i : Int32) => {
    edges[r * size + @cmp.maximum(0, @cmp.minimum(size - 1, i))]
  }
  // The three runs across the side, from outside top/left to bottom/right.
  let (before, middle, after) : (
    (FixedArray[Double], Int32),
    (FixedArray[Double], Int32),
    (FixedArray[Double], Int32),
  ) = match side {
    0 => ((next, 3), (own, 0), (own, 1))
    1 => ((own, 2), (own, 3), (next, 0))
    2 => ((next, 7), (own, 4), (own, 5))
    _ => ((own, 6), (own, 7), (next, 4))
  }
  let scale = slope_scale(size, z, @math.pow)
  let out = FixedArray::make(size * 2, b'\x00')
  for i in 0..<size {
    let p = (e : (FixedArray[Double], Int32), k : Int32) => run(e.0, e.1, k)
    let (sx, sy) = if side < 2 {
      sobel(
        p(before, i - 1),
        p(before, i),
        p(before, i + 1),
        p(middle, i - 1),
        p(middle, i + 1),
        p(after, i - 1),
        p(after, i),
        p(after, i + 1),
      )
    } else {
      sobel(
        p(before, i - 1),
        p(middle, i - 1),
        p(after, i - 1),
        p(before, i),
        p(after, i),
        p(before, i + 1),
        p(middle, i + 1),
        p(after, i + 1),
      )
    }
    out[i * 2] = slope_byte(sx * scale)
    out[i * 2 + 1] = slope_byte(sy * scale)
  }
  Bytes::from_array(out[:])
}
