///|
/// Most points `concave` and `convex` take: past it they give an empty table
/// (AGENTS.md §8.2).
pub const MAX_HULL_POINTS : Int32 = 1_000_000

///|
/// concaveman's hull of every vertex of `t` (rows in order, each ring's closing
/// vertex included, as Turf's `coordEach` visits a FeatureCollection), as a
/// one-row table holding the closed ring as a Polygon, without properties.
/// `concavity` and `length_threshold` are concaveman's (2 and 0 are its
/// defaults; NaN `length_threshold` reads as 0). Vertices with a non-finite
/// coordinate are left out. The table is empty when no vertex is left, when
/// the ring has fewer than 4 points (where Turf's `convex` gives null) or when
/// there are more than `MAX_HULL_POINTS` vertices.
pub fn concave(
  t : @geom.Table,
  concavity : Double,
  length_threshold : Double,
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
  let ring = concaveman(xs, ys, concavity, length_threshold)
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
pub fn convex(t : @geom.Table) -> @geom.Table {
  concave(t, @double.infinity, 0.0)
}

///|
fn finite(x : Double) -> Bool {
  !x.is_nan() && !x.is_inf()
}
