///|
/// Rectangles for glyph bitmaps in a texture of `width` x `height`, packed in
/// shelves as they come, with a pixel of space around each; a glyph keeps its
/// place once given one.
pub struct Atlas {
  width : Int32
  height : Int32
  priv shelves : Array[(Int32, Int32, Int32)]
  priv rects : Map[Int32, (Int32, Int32, Int32, Int32)]
}

///|
pub fn Atlas::new(width : Int32, height : Int32) -> Atlas {
  { width, height, shelves: [], rects: Map([]), }
}

///|
/// Glyph `cp`'s rectangle (x, y, width, height), if it has one.
pub fn Atlas::rect(self : Atlas, cp : Int32) -> (Int32, Int32, Int32, Int32)? {
  self.rects.get(cp)
}

///|
/// Places glyph `cp` of `w` x `h` pixels; None when the atlas is full (or the
/// glyph already has a place, which stays as it was).
pub fn Atlas::place(
  self : Atlas,
  cp : Int32,
  w : Int32,
  h : Int32,
) -> (Int32, Int32)? {
  if self.rects.contains(cp) || w <= 0 || h <= 0 {
    return None
  }
  let cw = w + 1
  let ch = h + 1
  // The shortest shelf it fits, (y, height, used width) each.
  let mut best = -1
  for i, s in self.shelves {
    if s.1 >= ch &&
      s.2 + cw <= self.width &&
      (best < 0 || s.1 < self.shelves[best].1) {
      best = i
    }
  }
  if best < 0 {
    let top = match self.shelves.last() {
      Some(s) => s.0 + s.1
      None => 0
    }
    if top + ch > self.height || cw > self.width {
      return None
    }
    self.shelves.push((top, ch, 0))
    best = self.shelves.length() - 1
  }
  let (y, sh, used) = self.shelves[best]
  self.shelves[best] = (y, sh, used + cw)
  self.rects[cp] = (used, y, w, h)
  Some((used, y))
}
