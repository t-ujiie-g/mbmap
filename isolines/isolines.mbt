///|
/// Whether a grid of `g`'s size may be walked once per break in `breaks`.
fn work_ok(g : Grid, breaks : Int32) -> Bool {
  (g.rows - 1).to_int64() * (g.cols - 1).to_int64() * breaks.to_int64() <=
  MAX_CELL_BREAKS
}

///|
/// Turf's `isolines(grid, breaks, { zProperty })` over the table's Point rows
/// and their `z_property` values: a MultiLineString row per break, in order,
/// with `z_property` set to the break (no geometry where it meets no cell).
/// As Turf's `gridToMatrix`, points form rows by latitude (south to north,
/// each west to east, ties in table order) of equal length, at least 2 x 2;
/// rows need not line up, since positions in the matrix are used, rescaled to
/// the points' bounding box. Missing, null, false, "", 0 and NaN values are 0.
/// Turf's `commonProperties` and `breaksProperties` are left to the caller.
/// None where Turf throws (rows other than Points, too few or uneven rows, no
/// rows); for values Turf keeps as non-numbers (true, a non-empty string),
/// whose JavaScript coercions are not followed; for non-finite coordinates,
/// which Turf sorts inconsistently; and past `MAX_GRID_POINTS`, `MAX_BREAKS`,
/// `MAX_CELL_BREAKS`, `MAX_SEGMENTS` and `MAX_ABS_VALUE` (grid values and
/// finite breaks).
pub fn isolines(
  t : @geom.Table,
  breaks : Array[Double],
  z_property : String,
) -> @geom.Table? {
  guard breaks_ok(breaks) && grid_of(t, z_property) is Some(g) else {
    return None
  }
  guard work_ok(g, breaks.length()) else { return None }
  let (scale_x, scale_y) = g.scale()
  let b = @geom.TableBuilder::new()
  let seg = []
  let mut total = 0
  for threshold in breaks {
    seg.clear()
    guard add_segments(g, threshold, seg) else { return None }
    total += seg.length() / 4
    if total > MAX_SEGMENTS {
      return None
    }
    for line in join(seg) {
      for i = 0; i < line.length(); i = i + 2 {
        b.point(line[i] * scale_x + g.min_x, line[i + 1] * scale_y + g.min_y)
      }
      b.end_ring()
      b.end_part()
    }
    b.prop(z_property, Num(threshold))
    b.end_feature(MultiLineString)
  }
  Some(b.finish())
}
