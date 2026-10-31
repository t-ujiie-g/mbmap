///|
/// Axis-aligned box; `min` is inclusive and `max` exclusive for containment.
/// `BBox::empty()` contains nothing and is the identity for `add_point`.
pub(all) struct BBox {
  min_x : Double
  min_y : Double
  max_x : Double
  max_y : Double
} derive(Debug, Eq)

///|
pub fn BBox::empty() -> BBox {
  {
    min_x: @double.infinity,
    min_y: @double.infinity,
    max_x: @double.neg_infinity,
    max_y: @double.neg_infinity,
  }
}

///|
pub fn BBox::is_empty(self : BBox) -> Bool {
  self.min_x > self.max_x || self.min_y > self.max_y
}

///|
pub fn BBox::add_point(self : BBox, x : Double, y : Double) -> BBox {
  {
    min_x: @cmp.minimum(self.min_x, x),
    min_y: @cmp.minimum(self.min_y, y),
    max_x: @cmp.maximum(self.max_x, x),
    max_y: @cmp.maximum(self.max_y, y),
  }
}

///|
pub fn BBox::union(self : BBox, other : BBox) -> BBox {
  self.add_point(other.min_x, other.min_y).add_point(other.max_x, other.max_y)
}

///|
pub fn BBox::contains(self : BBox, x : Double, y : Double) -> Bool {
  x >= self.min_x && x < self.max_x && y >= self.min_y && y < self.max_y
}

///|
pub fn BBox::intersects(self : BBox, other : BBox) -> Bool {
  self.min_x < other.max_x &&
  other.min_x < self.max_x &&
  self.min_y < other.max_y &&
  other.min_y < self.max_y
}
