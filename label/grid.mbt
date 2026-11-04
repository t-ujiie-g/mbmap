///|
/// Placed screen boxes and circles in a grid of `cell`-px squares (MapLibre's `GridIndex`): a cell
/// lists boxes by their offset in `boxes`, circles as -1 - their offset in `circles` (x, y, radius);
/// `box_never` and `circle_never` tell whether each was placed by a symbol that never overlaps.
pub struct Grid {
  priv mut width : Double
  priv mut height : Double
  priv mut cols : Int32
  priv mut rows : Int32
  priv cell : Double
  priv mut cells : FixedArray[Array[Int32]]
  priv boxes : Array[Double]
  priv circles : Array[Double]
  priv box_never : Array[Bool]
  priv circle_never : Array[Bool]
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
    circles: [],
    box_never: [],
    circle_never: [],
  }
}

///|
/// Empties the grid and sizes it to a `width` x `height` viewport, keeping its
/// cells' capacity when the cell count stays.
pub fn Grid::reset(self : Grid, width : Double, height : Double) -> Unit {
  let cols = @cmp.maximum(1, (width / self.cell).ceil().to_int())
  let rows = @cmp.maximum(1, (height / self.cell).ceil().to_int())
  if cols * rows == self.cells.length() {
    for c in self.cells {
      c.clear()
    }
  } else {
    self.cells = FixedArray::makei(cols * rows, _ => [])
  }
  self.width = width
  self.height = height
  self.cols = cols
  self.rows = rows
  self.boxes.clear()
  self.circles.clear()
  self.box_never.clear()
  self.circle_never.clear()
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
/// MapLibre's `_circleAndRectCollide`: edges touching included.
fn circle_meets_box(
  x : Double,
  y : Double,
  r : Double,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
) -> Bool {
  let hw = (x1 - x0) / 2.0
  let dx = (x - (x0 + hw)).abs()
  if dx > hw + r {
    return false
  }
  let hh = (y1 - y0) / 2.0
  let dy = (y - (y0 + hh)).abs()
  if dy > hh + r {
    return false
  }
  if dx <= hw || dy <= hh {
    return true
  }
  let ex = dx - hw
  let ey = dy - hh
  ex * ex + ey * ey <= r * r
}

///|
/// Whether the box meets one already inserted, edges touching included, as
/// MapLibre's `GridIndex.hitTest` (a box over the whole grid meets everything);
/// `cooperative`, only those inserted as `never` (MapLibre's `overlapAllowed`).
pub fn Grid::hits(
  self : Grid,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  cooperative~ : Bool = false,
) -> Bool {
  if x1 < 0.0 || x0 > self.width || y1 < 0.0 || y0 > self.height {
    return false
  }
  if x0 <= 0.0 && y0 <= 0.0 && self.width <= x1 && self.height <= y1 {
    return true
  }
  let (c0, c1) = self.span(x0, x1, self.cols)
  let (r0, r1) = self.span(y0, y1, self.rows)
  let b = self.boxes
  let k = self.circles
  let e = 1.0e-6
  for r in r0..<=r1 {
    for c in c0..<=c1 {
      for i in self.cells[r * self.cols + c] {
        if cooperative && !self.never(i) {
          continue
        }
        if i >= 0 {
          if x0 <= b[i + 2] + e &&
            y0 <= b[i + 3] + e &&
            x1 >= b[i] - e &&
            y1 >= b[i + 1] - e {
            return true
          }
        } else {
          let j = -1 - i
          if circle_meets_box(k[j], k[j + 1], k[j + 2], x0, y0, x1, y1) {
            return true
          }
        }
      }
    }
  }
  false
}

///|
/// Whether the circle meets a box or circle already inserted (MapLibre's
/// `hitTestCircle`), as `hits` does with `cooperative`.
pub fn Grid::hits_circle(
  self : Grid,
  x : Double,
  y : Double,
  radius : Double,
  cooperative~ : Bool = false,
) -> Bool {
  if x + radius < 0.0 ||
    x - radius > self.width ||
    y + radius < 0.0 ||
    y - radius > self.height {
    return false
  }
  let (c0, c1) = self.span(x - radius, x + radius, self.cols)
  let (r0, r1) = self.span(y - radius, y + radius, self.rows)
  let b = self.boxes
  let k = self.circles
  for r in r0..<=r1 {
    for c in c0..<=c1 {
      for i in self.cells[r * self.cols + c] {
        if cooperative && !self.never(i) {
          continue
        }
        if i >= 0 {
          if circle_meets_box(x, y, radius, b[i], b[i + 1], b[i + 2], b[i + 3]) {
            return true
          }
        } else {
          let j = -1 - i
          let dx = k[j] - x
          let dy = k[j + 1] - y
          let both = k[j + 2] + radius
          if both * both > dx * dx + dy * dy {
            return true
          }
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
/// Whether cell entry `i` was inserted as `never`.
fn Grid::never(self : Grid, i : Int32) -> Bool {
  if i >= 0 {
    self.box_never[i / 4]
  } else {
    self.circle_never[(-1 - i) / 3]
  }
}

///|
/// Adds a box, of a symbol that `never` overlaps others or not; the parts
/// outside the viewport are not kept.
pub fn Grid::insert(
  self : Grid,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  never~ : Bool = true,
) -> Unit {
  self.box_never.push(never)
  let at = self.boxes.length()
  self.boxes.push(x0)
  self.boxes.push(y0)
  self.boxes.push(x1)
  self.boxes.push(y1)
  self.mark(x0, y0, x1, y1, at)
}

///|
/// Adds a circle, in the cells its bounding square covers, as `insert` a box.
pub fn Grid::insert_circle(
  self : Grid,
  x : Double,
  y : Double,
  radius : Double,
  never~ : Bool = true,
) -> Unit {
  self.circle_never.push(never)
  let at = self.circles.length()
  self.circles.push(x)
  self.circles.push(y)
  self.circles.push(radius)
  self.mark(x - radius, y - radius, x + radius, y + radius, -1 - at)
}

///|
fn Grid::mark(
  self : Grid,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  entry : Int32,
) -> Unit {
  let (c0, c1) = self.span(x0, x1, self.cols)
  let (r0, r1) = self.span(y0, y1, self.rows)
  for r in r0..<=r1 {
    for c in c0..<=c1 {
      self.cells[r * self.cols + c].push(entry)
    }
  }
}
