///|
/// A style image (MapLibre's `StyleImage`): `width` x `height` straight RGBA
/// pixels in `data`, `pixel_ratio` of them per CSS pixel; `sdf` for an image
/// whose alpha is a distance field, colored by paint.
pub(all) struct StyleImage {
  width : Int32
  height : Int32
  data : FixedArray[Byte]
  pixel_ratio : Double
  sdf : Bool
}

///|
/// Where a pattern lies in the atlas: its pixels from `tl` to `br` (the image
/// without its padding), as MapLibre's `ImagePosition`.
pub struct PatternPosition {
  tl : (Int32, Int32)
  br : (Int32, Int32)
  pixel_ratio : Double
  sdf : Bool
}

///|
/// The size the pattern repeats at, in CSS pixels.
fn PatternPosition::display_size(self : PatternPosition) -> (Double, Double) {
  (
    (self.br.0 - self.tl.0).to_double() / self.pixel_ratio,
    (self.br.1 - self.tl.1).to_double() / self.pixel_ratio,
  )
}

///|
/// Pixels around each image (MapLibre's `IMAGE_PADDING`): copied from its
/// opposite edge in a pattern atlas so that linear filtering wraps,
/// transparent in an icon atlas.
const PATTERN_PADDING : Int32 = 1

///|
/// The atlas is this wide; it grows in height up to `PATTERN_ATLAS_MAX`.
pub const PATTERN_ATLAS_WIDTH : Int32 = 1024

///|
pub const PATTERN_ATLAS_MAX : Int32 = 4096

///|
/// The patterns (or, without `wrap`, icons) of a style in one texture, packed
/// in shelves as they are first drawn. Positions never move, so the atlas only
/// grows.
pub struct PatternAtlas {
  mut height : Int32
  mut data : FixedArray[Byte]
  priv wrap : Bool
  priv positions : Map[String, PatternPosition]
  priv shelves : Array[(Int32, Int32, Int32)]
  priv mut dirty : Bool
}

///|
pub fn PatternAtlas::new(wrap~ : Bool = true) -> PatternAtlas {
  {
    height: 64,
    data: FixedArray::make(PATTERN_ATLAS_WIDTH * 64 * 4, b'\x00'),
    wrap,
    positions: Map([]),
    shelves: [],
    dirty: false,
  }
}

///|
/// Puts `image` as `name`: over its pixels if it has their size, else in a new
/// place (the old one is left unused, so meshes drawing it stay valid).
pub fn PatternAtlas::put(
  self : PatternAtlas,
  name : String,
  image : StyleImage,
) -> PatternPosition? {
  match self.positions.get(name) {
    Some(p) if p.br.0 - p.tl.0 == image.width &&
      p.br.1 - p.tl.1 == image.height &&
      image.data.length() >= image.width * image.height * 4 => {
      let p = { ..p, pixel_ratio: image.pixel_ratio, sdf: image.sdf, }
      self.copy(image, p.tl.0, p.tl.1)
      self.positions[name] = p
      self.dirty = true
      Some(p)
    }
    _ => self.add(name, image)
  }
}

///|
/// Pattern `name`'s position, if added.
pub fn PatternAtlas::get(
  self : PatternAtlas,
  name : String,
) -> PatternPosition? {
  self.positions.get(name)
}

///|
/// Whether the pixels changed since the last call.
fn PatternAtlas::take_dirty(self : PatternAtlas) -> Bool {
  let d = self.dirty
  self.dirty = false
  d
}

///|
/// Forgets every pattern (when images are replaced or removed).
pub fn PatternAtlas::clear(self : PatternAtlas) -> Unit {
  self.positions.clear()
  self.shelves.clear()
  self.data = FixedArray::make(PATTERN_ATLAS_WIDTH * self.height * 4, b'\x00')
  self.dirty = true
}

///|
/// Adds `image` as pattern `name` and returns its position; None when it does
/// not fit (wider than the atlas, or the atlas is full).
pub fn PatternAtlas::add(
  self : PatternAtlas,
  name : String,
  image : StyleImage,
) -> PatternPosition? {
  let w = image.width + 2 * PATTERN_PADDING
  let h = image.height + 2 * PATTERN_PADDING
  if image.width <= 0 ||
    image.height <= 0 ||
    w > PATTERN_ATLAS_WIDTH ||
    image.data.length() < image.width * image.height * 4 {
    return None
  }
  guard self.place(w, h) is Some((x, y)) else { return None }
  self.copy(image, x + PATTERN_PADDING, y + PATTERN_PADDING)
  let p = {
    tl: (x + PATTERN_PADDING, y + PATTERN_PADDING),
    br: (x + PATTERN_PADDING + image.width, y + PATTERN_PADDING + image.height),
    pixel_ratio: image.pixel_ratio,
    sdf: image.sdf,
  }
  self.positions[name] = p
  self.dirty = true
  Some(p)
}

///|
/// A free `w` x `h` place: on the first shelf (y, height, used width) it
/// fits, or a new shelf, growing the atlas if needed.
fn PatternAtlas::place(
  self : PatternAtlas,
  w : Int32,
  h : Int32,
) -> (Int32, Int32)? {
  for i, s in self.shelves {
    let (y, sh, used) = s
    if h <= sh && used + w <= PATTERN_ATLAS_WIDTH {
      self.shelves[i] = (y, sh, used + w)
      return Some((used, y))
    }
  }
  let y = match self.shelves.last() {
    Some((y, sh, _)) => y + sh
    None => 0
  }
  while y + h > self.height {
    if self.height * 2 > PATTERN_ATLAS_MAX {
      return None
    }
    let grown = FixedArray::make(
      PATTERN_ATLAS_WIDTH * self.height * 2 * 4,
      b'\x00',
    )
    for i, b in self.data {
      grown[i] = b
    }
    self.data = grown
    self.height *= 2
  }
  self.shelves.push((y, h, w))
  Some((0, y))
}

///|
/// Copies `image` to (x, y), in a pattern atlas with each edge's pixels repeated
/// past the opposite edge, as MapLibre's atlas pads patterns.
fn PatternAtlas::copy(
  self : PatternAtlas,
  image : StyleImage,
  x : Int32,
  y : Int32,
) -> Unit {
  let w = image.width
  let h = image.height
  let put = (dx : Int32, dy : Int32, sx : Int32, sy : Int32) => {
    let d = ((y + dy) * PATTERN_ATLAS_WIDTH + x + dx) * 4
    let s = (sy * w + sx) * 4
    for k in 0..<4 {
      self.data[d + k] = image.data[s + k]
    }
  }
  for j in 0..<h {
    for i in 0..<w {
      put(i, j, i, j)
    }
  }
  guard self.wrap else { return }
  for i in 0..<w {
    put(i, -1, i, h - 1)
    put(i, h, i, 0)
  }
  for j in 0..<h {
    put(-1, j, w - 1, j)
    put(w, j, 0, j)
  }
}
