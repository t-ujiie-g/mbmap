///|
/// Most points `concave` and `convex` take: past it they give None (AGENTS.md
/// §8.2).
pub const MAX_HULL_POINTS : Int32 = 1_000_000

///|
/// concaveman's hull of `t`'s finite vertices as a one-row Polygon table (rbush's
/// logarithms through `trig`); empty under 4 ring points (Turf's `convex` gives
/// null); None past `MAX_HULL_POINTS` vertices.
pub fn concave(
  t : @geom.Table,
  concavity : Double,
  length_threshold : Double,
  trig~ : @core.Trig = @core.Trig::moonbit(),
) -> @geom.Table? {
  let n = t.coords.length() / 2
  guard n <= MAX_HULL_POINTS else { return None }
  let b = @geom.TableBuilder::new()
  let xs = []
  let ys = []
  for i in 0..<n {
    let x = t.coords[2 * i]
    let y = t.coords[2 * i + 1]
    if x.is_finite() && y.is_finite() {
      xs.push(x)
      ys.push(y)
    }
  }
  if xs.length() == 0 {
    return Some(b.finish())
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
  Some(b.finish())
}

///|
/// The convex hull as Turf 7.4.0's `convex` with its default options makes it
/// (concaveman with infinite concavity), under `concave`'s rules.
pub fn convex(
  t : @geom.Table,
  trig~ : @core.Trig = @core.Trig::moonbit(),
) -> @geom.Table? {
  concave(t, @double.infinity, 0.0, trig~)
}
