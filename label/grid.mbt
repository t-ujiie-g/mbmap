///|
/// Screen boxes in a grid of `cell`-pixel squares, to test new boxes against
/// those already placed without comparing every pair.
pub struct Grid {
  priv width : Double
  priv height : Double
  priv cols : Int32
  priv rows : Int32
  priv cell : Double
  priv cells : FixedArray[Array[Int32]]
  priv boxes : Array[Double]
}

///|
/// A grid over a `width` x `height` viewport.
pub fn Grid::new(
  width : Double,
  height : Double,
  cell~ : Double = 64.0,
) -> Grid {
  let cols = @cmp.maximum(1, (width / cell).ceil().to_int())
  let rows = @cmp.maximum(1, (height / cell).ceil().to_int())
  {
    width,
    height,
    cols,
    rows,
    cell,
    cells: FixedArray::makei(cols * rows, _ => []),
    boxes: [],
  }
}

///|
fn Grid::span(
  self : Grid,
  lo : Double,
  hi : Double,
  n : Int32,
) -> (Int32, Int32) {
  let a = @cmp.maximum(0, (lo / self.cell).floor().to_int())
  let b = @cmp.minimum(n - 1, (hi / self.cell).floor().to_int())
  (a, b)
}

///|
/// Whether the box meets one already inserted, edges touching included, as
/// MapLibre's `GridIndex.hitTest` (a box over the whole grid meets everything).
pub fn Grid::hits(
  self : Grid,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
) -> Bool {
  if x1 < 0.0 || x0 > self.width || y1 < 0.0 || y0 > self.height {
    return false
  }
  if x0 <= 0.0 && y0 <= 0.0 && self.width <= x1 && self.height <= y1 {
    return !self.boxes.is_empty()
  }
  let (c0, c1) = self.span(x0, x1, self.cols)
  let (r0, r1) = self.span(y0, y1, self.rows)
  let b = self.boxes
  let e = 1.0e-6
  for r in r0..<=r1 {
    for c in c0..<=c1 {
      for i in self.cells[r * self.cols + c] {
        if x0 <= b[i + 2] + e &&
          y0 <= b[i + 3] + e &&
          x1 >= b[i] - e &&
          y1 >= b[i + 1] - e {
          return true
        }
      }
    }
  }
  false
}

///|
/// Whether some of the box lies on the grid (MapLibre's `isInsideGrid`).
pub fn Grid::inside(
  self : Grid,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
) -> Bool {
  x1 >= 0.0 && x0 < self.width && y1 >= 0.0 && y0 < self.height
}

///|
/// Adds a box; the parts outside the viewport are not kept.
pub fn Grid::insert(
  self : Grid,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
) -> Unit {
  let at = self.boxes.length()
  self.boxes.push(x0)
  self.boxes.push(y0)
  self.boxes.push(x1)
  self.boxes.push(y1)
  let (c0, c1) = self.span(x0, x1, self.cols)
  let (r0, r1) = self.span(y0, y1, self.rows)
  for r in r0..<=r1 {
    for c in c0..<=c1 {
      self.cells[r * self.cols + c].push(at)
    }
  }
}
