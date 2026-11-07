// Ports @turf/point-grid, @turf/square-grid, @turf/rectangle-grid,
// @turf/hex-grid and @turf/triangle-grid 7.4.0 (MIT License, Copyright (c)
// 2017 TurfJS) without their `mask` option. See NOTICE.

///|
/// The most rows a grid may have (each triangle of a hex grid's `triangles`
/// counts), and the most steps of a loop that adds none; past it a grid is
/// `None`, where Turf would allocate without bound or never return.
pub const MAX_GRID_CELLS : Int32 = 1_000_000

///|
/// How many times Turf's `while (current <= stop) { current += step }` runs,
/// or `None` past `MAX_GRID_CELLS`.
fn steps(start : Double, stop : Double, step : Double) -> Int32? {
  let mut n = 0
  let mut current = start
  while current <= stop {
    n += 1
    if n > MAX_GRID_CELLS {
      return None
    }
    current += step
  }
  Some(n)
}

///|
/// `steps` of an inner loop, which runs only if its outer loop does.
fn inner_steps(
  outer : Int32,
  start : Double,
  stop : Double,
  step : Double,
) -> Int32? {
  if outer == 0 {
    Some(0)
  } else {
    steps(start, stop, step)
  }
}

///|
/// Whether `columns` loops of `rows` rows each stay within `MAX_GRID_CELLS`.
fn within_cap(columns : Int32, rows : Int32) -> Bool {
  rows == 0 || columns.to_int64() * rows.to_int64() <= MAX_GRID_CELLS.to_int64()
}

///|
fn add_point(b : @geom.TableBuilder, x : Double, y : Double) -> Unit {
  b.point(x, y)
  b.end_ring()
  b.end_part()
  b.end_feature(Point)
}

///|
/// Closes the polygon of the ring just added; false where Turf's `polygon`
/// throws, as its first and last positions (NaN) differ.
fn end_polygon(b : @geom.TableBuilder) -> Bool {
  let t = b.table
  let first = @geom.start_of_last(t.point_ends) * 2
  b.end_ring()
  b.end_part()
  b.end_feature(Polygon)
  !(t.coords[first].is_nan() || t.coords[first + 1].is_nan())
}

///|
/// Turf's `pointGrid([x0, y0, x1, y1], cell_side)` (kilometers): Point rows by
/// column from the west, each from the south. `None` for a `cell_side` that is
/// NaN or not positive, or past `MAX_GRID_CELLS`.
pub fn point_grid(
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  cell_side : Double,
  trig~ : Trig = Trig::moonbit(),
) -> @geom.Table? {
  guard cell_side > 0.0 else { return None }
  let x_fraction = cell_side / distance(trig, x0, y0, x1, y0)
  let cell_width = x_fraction * (x1 - x0)
  let y_fraction = cell_side / distance(trig, x0, y0, x0, y1)
  let cell_height = y_fraction * (y1 - y0)
  let bbox_width = x1 - x0
  let bbox_height = y1 - y0
  let columns = (bbox_width / cell_width).floor()
  let rows = (bbox_height / cell_height).floor()
  let start_x = x0 + (bbox_width - columns * cell_width) / 2.0
  let start_y = y0 + (bbox_height - rows * cell_height) / 2.0
  guard steps(start_x, x1, cell_width) is Some(nx) else { return None }
  guard inner_steps(nx, start_y, y1, cell_height) is Some(ny) else {
    return None
  }
  guard within_cap(nx, ny) else { return None }
  let b = @geom.TableBuilder::new()
  let mut x = start_x
  for _ in 0..<nx {
    let mut y = start_y
    for _ in 0..<ny {
      add_point(b, x, y)
      y += cell_height
    }
    x += cell_width
  }
  Some(b.finish())
}

///|
/// `@turf/rectangle-grid` with cells `width` by `height` kilometers.
fn rectangle_grid(
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  width : Double,
  height : Double,
) -> @geom.Table? {
  guard width > 0.0 && height > 0.0 else { return None }
  let bbox_width = x1 - x0
  let cell_width = width / km_factor * degree_factor
  let bbox_height = y1 - y0
  let cell_height = height / km_factor * degree_factor
  let columns = (bbox_width.abs() / cell_width).floor()
  let rows = (bbox_height.abs() / cell_height).floor()
  let cap = MAX_GRID_CELLS.to_double()
  guard !(columns > cap) else { return None }
  let nx = if columns >= 1.0 { columns.to_int() } else { 0 }
  guard nx == 0 || !(rows > cap) else { return None }
  let ny = if rows >= 1.0 && nx > 0 { rows.to_int() } else { 0 }
  guard within_cap(nx, ny) else { return None }
  let delta_x = (bbox_width - columns * cell_width) / 2.0
  let delta_y = (bbox_height - rows * cell_height) / 2.0
  let b = @geom.TableBuilder::new()
  let mut x = x0 + delta_x
  for _ in 0..<nx {
    let mut y = y0 + delta_y
    for _ in 0..<ny {
      b.point(x, y)
      b.point(x, y + cell_height)
      b.point(x + cell_width, y + cell_height)
      b.point(x + cell_width, y)
      b.point(x, y)
      guard end_polygon(b) else { return None }
      y += cell_height
    }
    x += cell_width
  }
  Some(b.finish())
}

///|
/// Turf's `squareGrid([x0, y0, x1, y1], cell_side)` (kilometers, turned into
/// degrees along a great circle, so `trig` goes unused): Polygon rows by
/// column from the west, each ring closed. `None` for a `cell_side` that is
/// NaN or not positive, where Turf throws (a ring starting at NaN) or past
/// `MAX_GRID_CELLS`.
pub fn square_grid(
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  cell_side : Double,
  trig~ : Trig = Trig::moonbit(),
) -> @geom.Table? {
  ignore(trig)
  rectangle_grid(x0, y0, x1, y1, cell_side, cell_side)
}

///|
/// Turf's `hexGrid([x0, y0, x1, y1], cell_side, { triangles })` (kilometers):
/// flat-topped hexagons (or each one's six triangles from its center) as
/// Polygon rows by column from the west. `None` for a `cell_side` that is NaN
/// or not positive, where Turf throws (a ring starting at NaN) or past
/// `MAX_GRID_CELLS`.
pub fn hex_grid(
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  cell_side : Double,
  triangles~ : Bool = false,
  trig~ : Trig = Trig::moonbit(),
) -> @geom.Table? {
  guard cell_side > 0.0 else { return None }
  let center_y = (y0 + y1) / 2.0
  let center_x = (x0 + x1) / 2.0
  let x_fraction = cell_side * 2.0 / distance(trig, x0, center_y, x1, center_y)
  let cell_width = x_fraction * (x1 - x0)
  let y_fraction = cell_side * 2.0 / distance(trig, center_x, y0, center_x, y1)
  let cell_height = y_fraction * (y1 - y0)
  let radius = cell_width / 2.0
  let hex_width = radius * 2.0
  let hex_height = (3.0 : Double).sqrt() / 2.0 * cell_height
  let box_width = x1 - x0
  let box_height = y1 - y0
  let x_interval = 3.0 / 4.0 * hex_width
  let y_interval = hex_height
  let x_count = ((box_width - hex_width) / (hex_width - radius / 2.0)).floor()
  let x_adjust = (x_count * x_interval - radius / 2.0 - box_width) / 2.0 -
    radius / 2.0 +
    x_interval / 2.0
  let y_count = ((box_height - hex_height) / hex_height).floor()
  let mut y_adjust = (box_height - y_count * hex_height) / 2.0
  let has_offset_y = y_count * hex_height - box_height > hex_height / 2.0
  if has_offset_y {
    y_adjust -= hex_height / 4.0
  }
  let cap = MAX_GRID_CELLS.to_double()
  guard !(x_count >= cap) else { return None }
  let nx = if x_count >= 0.0 { x_count.to_int() + 1 } else { 0 }
  guard nx == 0 || !(y_count >= cap) else { return None }
  let ny = if y_count >= 0.0 && nx > 0 { y_count.to_int() + 1 } else { 0 }
  let skipped = if ny == 0 { 0 } else if has_offset_y { nx } else { nx / 2 }
  let cells = (nx.to_int64() * ny.to_int64() - skipped.to_int64()) *
    (if triangles { 6L } else { 1L })
  guard cells <= MAX_GRID_CELLS.to_int64() else { return None }
  let cosines = FixedArray::make(6, 0.0)
  let sines = FixedArray::make(6, 0.0)
  for i in 0..<6 {
    let angle = 2.0 * PI / 6.0 * i.to_double()
    cosines[i] = (trig.cos)(angle)
    sines[i] = (trig.sin)(angle)
  }
  let rx = cell_width / 2.0
  let ry = cell_height / 2.0
  let b = @geom.TableBuilder::new()
  for x in 0..<nx {
    for y in 0..<ny {
      let is_odd = x % 2 == 1
      if y == 0 && (is_odd || has_offset_y) {
        continue
      }
      let cx = x.to_double() * x_interval + x0 - x_adjust
      let mut cy = y.to_double() * y_interval + y0 + y_adjust
      if is_odd {
        cy -= hex_height / 2.0
      }
      if triangles {
        for i in 0..<6 {
          let j = (i + 1) % 6
          b.point(cx, cy)
          b.point(cx + rx * cosines[i], cy + ry * sines[i])
          b.point(cx + rx * cosines[j], cy + ry * sines[j])
          b.point(cx, cy)
          guard end_polygon(b) else { return None }
        }
      } else {
        for i in 0..<6 {
          b.point(cx + rx * cosines[i], cy + ry * sines[i])
        }
        b.point(cx + rx * cosines[0], cy + ry * sines[0])
        guard end_polygon(b) else { return None }
      }
    }
  }
  Some(b.finish())
}

///|
/// Turf's `triangleGrid([x0, y0, x1, y1], cell_side)` (kilometers): two
/// Polygon rows per cell, by column from the west, the diagonals alternating
/// as Turf's do. `None` for a `cell_side` that is NaN or not positive, where
/// Turf throws (a ring starting at NaN, as on a flat box) or past
/// `MAX_GRID_CELLS`.
pub fn triangle_grid(
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  cell_side : Double,
  trig~ : Trig = Trig::moonbit(),
) -> @geom.Table? {
  guard cell_side > 0.0 else { return None }
  let x_fraction = cell_side / distance(trig, x0, y0, x1, y0)
  let w = x_fraction * (x1 - x0)
  let y_fraction = cell_side / distance(trig, x0, y0, x0, y1)
  let h = y_fraction * (y1 - y0)
  guard steps(x0, x1, w) is Some(nx) else { return None }
  guard inner_steps(nx, y0, y1, h) is Some(ny) else { return None }
  guard within_cap(nx, ny * 2) else { return None }
  let b = @geom.TableBuilder::new()
  let mut x = x0
  for xi in 0..<nx {
    let mut y = y0
    for yi in 0..<ny {
      if xi % 2 == yi % 2 {
        b.point(x, y)
        b.point(x, y + h)
        b.point(x + w, y)
        b.point(x, y)
        guard end_polygon(b) else { return None }
        b.point(x, y + h)
        b.point(x + w, y + h)
        b.point(x + w, y)
        b.point(x, y + h)
        guard end_polygon(b) else { return None }
      } else if xi % 2 == 0 {
        b.point(x, y)
        b.point(x + w, y + h)
        b.point(x + w, y)
        b.point(x, y)
        guard end_polygon(b) else { return None }
        b.point(x, y)
        b.point(x, y + h)
        b.point(x + w, y + h)
        b.point(x, y)
        guard end_polygon(b) else { return None }
      } else {
        b.point(x, y)
        b.point(x, y + h)
        b.point(x + w, y + h)
        b.point(x, y)
        guard end_polygon(b) else { return None }
        b.point(x, y)
        b.point(x + w, y + h)
        b.point(x + w, y)
        b.point(x, y)
        guard end_polygon(b) else { return None }
      }
      y += h
    }
    x += w
  }
  Some(b.finish())
}
