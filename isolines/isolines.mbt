///|
/// Whether a grid of `g`'s size may be walked once per break in `breaks`.
fn work_ok(g : Grid, breaks : Int32) -> Bool {
  (g.rows - 1).to_int64() * (g.cols - 1).to_int64() * breaks.to_int64() <=
  MAX_CELL_BREAKS
}

///|
/// Turf's `isolines(grid, breaks, { zProperty })` over Point rows gridded as its
/// `gridToMatrix` does: a MultiLineString row per break. None where Turf throws,
/// for values it keeps as non-numbers or non-finite coordinates, and past the caps.
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
