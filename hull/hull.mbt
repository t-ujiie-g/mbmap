///|
/// Most points `concave` and `convex` take: past it they give an empty table
/// (AGENTS.md §8.2).
pub const MAX_HULL_POINTS : Int32 = 1_000_000

///|
/// concaveman's hull of `t`'s finite vertices as a one-row Polygon table (rbush's
/// logarithms through `trig`); empty under 4 ring points (Turf's `convex` gives
/// null) or past `MAX_HULL_POINTS` vertices.
pub fn concave(
  t : @geom.Table,
  concavity : Double,
  length_threshold : Double,
  trig~ : @core.Trig = @core.Trig::moonbit(),
) -> @geom.Table {
  let b = @geom.TableBuilder::new()
  let n = t.coords.length() / 2
  if n > MAX_HULL_POINTS {
    return b.finish()
  }
  let xs = []
  let ys = []
  for i in 0..<n {
    let x = t.coords[2 * i]
    let y = t.coords[2 * i + 1]
    if finite(x) && finite(y) {
      xs.push(x)
      ys.push(y)
    }
  }
  if xs.length() == 0 {
    return b.finish()
  }
  let ring = concaveman(xs, ys, concavity, length_threshold, trig)
  if ring.length() > 3 {
    for p in ring {
      b.point(xs[p], ys[p])
    }
    b.end_ring()
    b.end_part()
    b.end_feature(Polygon)
  }
  b.finish()
}

///|
/// The convex hull as Turf 7.4.0's `convex` with its default options makes it
/// (concaveman with infinite concavity), under `concave`'s rules.
pub fn convex(
  t : @geom.Table,
  trig~ : @core.Trig = @core.Trig::moonbit(),
) -> @geom.Table {
  concave(t, @double.infinity, 0.0, trig~)
}

///|
fn finite(x : Double) -> Bool {
  !x.is_nan() && !x.is_inf()
}
