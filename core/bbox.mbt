///|
/// Axis-aligned box; `min` is inclusive and `max` exclusive for containment.
/// `BBox::empty()` contains nothing.
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
pub fn BBox::contains(self : BBox, x : Double, y : Double) -> Bool {
  x >= self.min_x && x < self.max_x && y >= self.min_y && y < self.max_y
}
