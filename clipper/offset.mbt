// Ports Clipper2 2.0.1 src/clipper.offset.cpp and InflatePaths and Ellipse of
// include/clipper2/clipper.h (commit 642390d), Boost Software License 1.0,
// Copyright (c) Angus Johnson 2010-2026. See NOTICE.

///|
/// How offset paths turn corners (`JoinType`): `Square` cuts them at exactly
/// the offset distance, `Bevel` cuts them closer in, `Round` follows an arc,
/// `Miter` extends edges up to the miter limit.
pub(all) enum JoinType {
  Square
  Bevel
  Round
  Miter
} derive(Eq)

///|
/// How paths are closed or capped when offset (`EndType`): `Polygon` offsets
/// one side of a closed path, `Joined` both sides of a path closed by joining
/// its ends, and `Butt`, `Square` and `Round` both sides of an open path with
/// those caps.
pub(all) enum EndType {
  Polygon
  Joined
  Butt
  Square
  Round
} derive(Eq)

///|
const FLOATING_POINT_TOLERANCE : Double = 1.0e-12

///|
/// Default arc tolerance as a share of the offset (1/500).
const ARC_CONST : Double = 0.002

///|
const PI : Double = 3.141592653589793

///|
priv struct PointD {
  x : Double
  y : Double
}

///|
/// `x` rounded half away from zero (`std::round`).
fn round_away(x : Double) -> Int64 {
  let t = if x < 0.0 { x.ceil() } else { x.floor() }
  if (x - t).abs() >= 0.5 {
    if x < 0.0 {
      (t - 1.0).to_int64()
    } else {
      (t + 1.0).to_int64()
    }
  } else {
    t.to_int64()
  }
}

///|
/// A Point64 from doubles, rounded as Clipper2's `Point64(double, double)`.
fn point64(x : Double, y : Double) -> Point64 {
  { x: round_away(x), y: round_away(y), }
}

///|
fn hypot(x : Double, y : Double) -> Double {
  (x * x + y * y).sqrt()
}

///|
fn get_unit_normal(pt1 : Point64, pt2 : Point64) -> PointD {
  if pt1 == pt2 {
    return { x: 0.0, y: 0.0, }
  }
  let dx = (pt2.x - pt1.x).to_double()
  let dy = (pt2.y - pt1.y).to_double()
  let inverse_hypot = 1.0 / hypot(dx, dy)
  { x: dy * inverse_hypot, y: -(dx * inverse_hypot), }
}

///|
fn normalize_vector(v : PointD) -> PointD {
  let h = hypot(v.x, v.y)
  if h.abs() < 0.001 {
    return { x: 0.0, y: 0.0, }
  }
  let inverse_hypot = 1.0 / h
  { x: v.x * inverse_hypot, y: v.y * inverse_hypot, }
}

///|
fn get_perpendic(pt : Point64, norm : PointD, delta : Double) -> Point64 {
  point64(pt.x.to_double() + norm.x * delta, pt.y.to_double() + norm.y * delta)
}

///|
fn get_perpendic_d(pt : Point64, norm : PointD, delta : Double) -> PointD {
  {
    x: pt.x.to_double() + norm.x * delta,
    y: pt.y.to_double() + norm.y * delta,
  }
}

///|
/// `GetLineIntersectPt` for doubles: None when parallel.
fn get_line_intersect_pt_d(
  ln1a : PointD,
  ln1b : PointD,
  ln2a : PointD,
  ln2b : PointD,
) -> PointD? {
  let dx1 = ln1b.x - ln1a.x
  let dy1 = ln1b.y - ln1a.y
  let dx2 = ln2b.x - ln2a.x
  let dy2 = ln2b.y - ln2a.y
  let det = dy1 * dx2 - dy2 * dx1
  if det == 0.0 {
    return None
  }
  let t = ((ln1a.x - ln2a.x) * dy2 - (ln1a.y - ln2a.y) * dx2) / det
  if t <= 0.0 {
    Some(ln1a)
  } else if t >= 1.0 {
    Some(ln1b)
  } else {
    Some({ x: ln1a.x + t * dx1, y: ln1a.y + t * dy1, })
  }
}

///|
/// Strips consecutive duplicates, and for closed paths a last point equal to
/// the first (`StripDuplicates`).
fn strip_duplicates(path : Array[Point64], is_closed : Bool) -> Array[Point64] {
  let out = []
  for p in path {
    if out.is_empty() || out[out.length() - 1] != p {
      out.push(p)
    }
  }
  if is_closed {
    while out.length() > 1 && out[out.length() - 1] == out[0] {
      out.pop() |> ignore
    }
  }
  out
}

///|
priv struct OffsetGroup {
  paths_in : Array[Array[Point64]]
  lowest_path_idx : Int32?
  is_reversed : Bool
  join_type : JoinType
  end_type : EndType
}

///|
/// The path holding the lowest point (largest y, then smallest x) and
/// whether its area is negative (`GetLowestClosedPathInfo`).
fn get_lowest_closed_path_info(paths : Array[Array[Point64]]) -> (Int32?, Bool) {
  let mut idx = None
  let mut is_neg_area = false
  let mut bot_x = @int64.MAX_VALUE
  let mut bot_y = @int64.MIN_VALUE
  for i, path in paths {
    let mut a = @double.max_value
    for pt in path {
      if pt.y < bot_y || (pt.y == bot_y && pt.x >= bot_x) {
        continue
      }
      if a == @double.max_value {
        a = area(path[:])
        if a == 0.0 {
          break
        }
        is_neg_area = a < 0.0
      }
      idx = Some(i)
      bot_x = pt.x
      bot_y = pt.y
    }
  }
  (idx, is_neg_area)
}

///|
fn OffsetGroup::new(
  paths : Array[Array[Point64]],
  join_type : JoinType,
  end_type : EndType,
) -> OffsetGroup {
  let is_joined = end_type == Polygon || end_type == Joined
  let paths_in = paths.map(p => strip_duplicates(p, is_joined))
  if end_type == Polygon {
    let (idx, neg) = get_lowest_closed_path_info(paths_in)
    {
      paths_in,
      lowest_path_idx: idx,
      is_reversed: idx is Some(_) && neg,
      join_type,
      end_type,
    }
  } else {
    {
      paths_in,
      lowest_path_idx: None,
      is_reversed: false,
      join_type,
      end_type,
    }
  }
}

///|
/// Inflates or shrinks paths (Clipper2's `ClipperOffset`): add groups of
/// paths with their join and end types, then `execute` with a distance.
pub struct ClipperOffset {
  priv mut delta : Double
  priv mut group_delta : Double
  priv mut temp_lim : Double
  priv mut steps_per_rad : Double
  priv mut step_sin : Double
  priv mut step_cos : Double
  priv norms : Array[PointD]
  priv path_out : Array[Point64]
  priv solution : Array[Array[Point64]]
  priv groups : Array[OffsetGroup]
  priv mut join_type : JoinType
  priv mut end_type : EndType
  priv miter_limit : Double
  priv arc_tolerance : Double
  priv preserve_collinear : Bool
  priv reverse_solution : Bool
}

///|
/// An offsetter; `arc_tolerance` 0 means the offset distance / 500.
pub fn ClipperOffset::new(
  miter_limit~ : Double = 2.0,
  arc_tolerance~ : Double = 0.0,
  preserve_collinear~ : Bool = false,
  reverse_solution~ : Bool = false,
) -> ClipperOffset {
  {
    delta: 0.0,
    group_delta: 0.0,
    temp_lim: 0.0,
    steps_per_rad: 0.0,
    step_sin: 0.0,
    step_cos: 0.0,
    norms: [],
    path_out: [],
    solution: [],
    groups: [],
    join_type: Bevel,
    end_type: Polygon,
    miter_limit,
    arc_tolerance,
    preserve_collinear,
    reverse_solution,
  }
}

///|
/// Adds paths to offset together with `join_type` and `end_type`.
pub fn ClipperOffset::add_paths(
  self : ClipperOffset,
  paths : Array[Array[Point64]],
  join_type : JoinType,
  end_type : EndType,
) -> Unit {
  if paths.is_empty() {
    return
  }
  self.groups.push(OffsetGroup::new(paths, join_type, end_type))
}

///|
fn ClipperOffset::build_normals(
  self : ClipperOffset,
  path : Array[Point64],
) -> Unit {
  self.norms.clear()
  if path.is_empty() {
    return
  }
  for i in 0..<(path.length() - 1) {
    self.norms.push(get_unit_normal(path[i], path[i + 1]))
  }
  self.norms.push(get_unit_normal(path[path.length() - 1], path[0]))
}

///|
fn ClipperOffset::do_bevel(
  self : ClipperOffset,
  path : Array[Point64],
  j : Int32,
  k : Int32,
) -> Unit {
  let n = self.norms
  let px = path[j].x.to_double()
  let py = path[j].y.to_double()
  if j == k {
    let abs_delta = self.group_delta.abs()
    self.path_out.push(
      point64(px - abs_delta * n[j].x, py - abs_delta * n[j].y),
    )
    self.path_out.push(
      point64(px + abs_delta * n[j].x, py + abs_delta * n[j].y),
    )
  } else {
    let d = self.group_delta
    self.path_out.push(point64(px + d * n[k].x, py + d * n[k].y))
    self.path_out.push(point64(px + d * n[j].x, py + d * n[j].y))
  }
}

///|
fn ClipperOffset::do_square(
  self : ClipperOffset,
  path : Array[Point64],
  j : Int32,
  k : Int32,
) -> Unit {
  let n = self.norms
  let vec : PointD = if j == k {
    { x: n[j].y, y: -n[j].x, }
  } else {
    normalize_vector({ x: -n[k].y + n[j].y, y: n[k].x + -n[j].x, })
  }
  let d = self.group_delta
  let abs_delta = d.abs()
  let pt_q : PointD = {
    x: path[j].x.to_double() + abs_delta * vec.x,
    y: path[j].y.to_double() + abs_delta * vec.y,
  }
  let pt1 : PointD = { x: pt_q.x + d * vec.y, y: pt_q.y + d * -vec.x, }
  let pt2 : PointD = { x: pt_q.x + d * -vec.y, y: pt_q.y + d * vec.x, }
  let pt3 = get_perpendic_d(path[k], n[k], d)
  let reflect = (p : PointD) => {
    point64(pt_q.x + (pt_q.x - p.x), pt_q.y + (pt_q.y - p.y))
  }
  if j == k {
    let pt4 : PointD = { x: pt3.x + vec.x * d, y: pt3.y + vec.y * d, }
    let pt = get_line_intersect_pt_d(pt1, pt2, pt3, pt4).unwrap_or(pt_q)
    self.path_out.push(reflect(pt))
    self.path_out.push(point64(pt.x, pt.y))
  } else {
    let pt4 = get_perpendic_d(path[j], n[k], d)
    let pt = get_line_intersect_pt_d(pt1, pt2, pt3, pt4).unwrap_or(pt_q)
    self.path_out.push(point64(pt.x, pt.y))
    self.path_out.push(reflect(pt))
  }
}

///|
fn ClipperOffset::do_miter(
  self : ClipperOffset,
  path : Array[Point64],
  j : Int32,
  k : Int32,
  cos_a : Double,
) -> Unit {
  let q = self.group_delta / (cos_a + 1.0)
  let n = self.norms
  self.path_out.push(
    point64(
      path[j].x.to_double() + (n[k].x + n[j].x) * q,
      path[j].y.to_double() + (n[k].y + n[j].y) * q,
    ),
  )
}

///|
fn ClipperOffset::do_round(
  self : ClipperOffset,
  path : Array[Point64],
  j : Int32,
  k : Int32,
  angle : Double,
) -> Unit {
  let pt = path[j]
  let n = self.norms
  let mut ox = n[k].x * self.group_delta
  let mut oy = n[k].y * self.group_delta
  if j == k {
    ox = -ox
    oy = -oy
  }
  let px = pt.x.to_double()
  let py = pt.y.to_double()
  self.path_out.push(point64(px + ox, py + oy))
  let steps = (self.steps_per_rad * angle.abs()).ceil().to_int()
  for _ in 1..<steps {
    let nx = ox * self.step_cos - self.step_sin * oy
    let ny = ox * self.step_sin + oy * self.step_cos
    ox = nx
    oy = ny
    self.path_out.push(point64(px + ox, py + oy))
  }
  self.path_out.push(get_perpendic(path[j], n[j], self.group_delta))
}

///|
fn ClipperOffset::offset_point(
  self : ClipperOffset,
  path : Array[Point64],
  j : Int32,
  k : Int32,
) -> Unit {
  if path[j] == path[k] {
    return
  }
  let n = self.norms
  // CrossProduct and DotProduct of the two normals.
  let mut sin_a = n[j].y * n[k].x - n[k].y * n[j].x
  let cos_a = n[j].x * n[k].x + n[j].y * n[k].y
  if sin_a > 1.0 {
    sin_a = 1.0
  } else if sin_a < -1.0 {
    sin_a = -1.0
  }
  if self.group_delta.abs() <= FLOATING_POINT_TOLERANCE {
    self.path_out.push(path[j])
    return
  }
  if cos_a > -0.999 && sin_a * self.group_delta < 0.0 {
    // Concave: three points making a negative region the final union removes.
    self.path_out.push(get_perpendic(path[j], n[k], self.group_delta))
    self.path_out.push(path[j])
    self.path_out.push(get_perpendic(path[j], n[j], self.group_delta))
  } else if cos_a > 0.999 && self.join_type != Round {
    self.do_miter(path, j, k, cos_a)
  } else if self.join_type == Miter {
    if cos_a > self.temp_lim - 1.0 {
      self.do_miter(path, j, k, cos_a)
    } else {
      self.do_square(path, j, k)
    }
  } else if self.join_type == Round {
    self.do_round(path, j, k, @math.atan2(sin_a, cos_a))
  } else if self.join_type == Bevel {
    self.do_bevel(path, j, k)
  } else {
    self.do_square(path, j, k)
  }
}

///|
fn ClipperOffset::offset_polygon(
  self : ClipperOffset,
  path : Array[Point64],
) -> Unit {
  self.path_out.clear()
  let mut k = path.length() - 1
  for j in 0..<path.length() {
    self.offset_point(path, j, k)
    k = j
  }
  self.solution.push(self.path_out.copy())
}

///|
fn ClipperOffset::offset_open_joined(
  self : ClipperOffset,
  path : Array[Point64],
) -> Unit {
  self.offset_polygon(path)
  let reverse_path = path.copy()
  reverse_path.rev_in_place()
  self.norms.rev_in_place()
  self.norms.push(self.norms[0])
  self.norms.remove(0) |> ignore
  for i in 0..<self.norms.length() {
    self.norms[i] = { x: -self.norms[i].x, y: -self.norms[i].y, }
  }
  self.offset_polygon(reverse_path)
}

///|
fn ClipperOffset::do_cap(
  self : ClipperOffset,
  path : Array[Point64],
  i : Int32,
) -> Unit {
  if self.group_delta.abs() <= FLOATING_POINT_TOLERANCE {
    self.path_out.push(path[i])
    return
  }
  match self.end_type {
    Butt => self.do_bevel(path, i, i)
    Round => self.do_round(path, i, i, PI)
    _ => self.do_square(path, i, i)
  }
}

///|
fn ClipperOffset::offset_open_path(
  self : ClipperOffset,
  path : Array[Point64],
) -> Unit {
  self.do_cap(path, 0)
  let high_i = path.length() - 1
  let mut k = 0
  for j in 1..<high_i {
    self.offset_point(path, j, k)
    k = j
  }
  let n = self.norms
  for i = high_i; i > 0; i = i - 1 {
    n[i] = { x: -n[i - 1].x, y: -n[i - 1].y, }
  }
  n[0] = n[high_i]
  self.do_cap(path, high_i)
  let mut k = high_i
  for j = high_i - 1; j > 0; j = j - 1 {
    self.offset_point(path, j, k)
    k = j
  }
  self.solution.push(self.path_out.copy())
}

///|
/// A circle of `steps` points around `center` (Clipper2's `Ellipse` with equal
/// radii; at least π√r steps).
fn ellipse(center : Point64, radius : Double, steps : Int32) -> Array[Point64] {
  if radius <= 0.0 {
    return []
  }
  let steps = if steps <= 2 { (PI * radius.sqrt()).to_int() } else { steps }
  let si = @math.sin(2.0 * PI / steps.to_double())
  let co = @math.cos(2.0 * PI / steps.to_double())
  let mut dx = co
  let mut dy = si
  let cx = center.x.to_double()
  let cy = center.y.to_double()
  let result = [point64(cx + radius, cy)]
  for _ in 1..<steps {
    result.push(point64(cx + radius * dx, cy + radius * dy))
    let x = dx * co - dy * si
    dy = dy * co + dx * si
    dx = x
  }
  result
}

///|
fn ClipperOffset::do_group_offset(
  self : ClipperOffset,
  group : OffsetGroup,
) -> Unit {
  if group.end_type == Polygon {
    if group.lowest_path_idx is None {
      self.delta = self.delta.abs()
    }
    self.group_delta = if group.is_reversed { -self.delta } else { self.delta }
  } else {
    self.group_delta = self.delta.abs()
  }
  let abs_delta = self.group_delta.abs()
  self.join_type = group.join_type
  self.end_type = group.end_type
  if group.join_type == Round || group.end_type == Round {
    let arc_tol = if self.arc_tolerance > FLOATING_POINT_TOLERANCE {
      @cmp.minimum(abs_delta, self.arc_tolerance)
    } else {
      abs_delta * ARC_CONST
    }
    let steps_per_360 = @cmp.minimum(
      PI / @math.acos(1.0 - arc_tol / abs_delta),
      abs_delta * PI,
    )
    self.step_sin = @math.sin(2.0 * PI / steps_per_360)
    self.step_cos = @math.cos(2.0 * PI / steps_per_360)
    if self.group_delta < 0.0 {
      self.step_sin = -self.step_sin
    }
    self.steps_per_rad = steps_per_360 / (2.0 * PI)
  }
  for path in group.paths_in {
    self.path_out.clear()
    let len = path.length()
    if len == 1 {
      if self.group_delta < 1.0 {
        continue
      }
      let pt = path[0]
      if group.join_type == Round {
        let steps = if self.steps_per_rad > 0.0 {
          (self.steps_per_rad * 2.0 * PI).ceil().to_int()
        } else {
          0
        }
        self.solution.push(ellipse(pt, abs_delta, steps))
      } else {
        let d = abs_delta.ceil().to_int64()
        self.solution.push([
          { x: pt.x - d, y: pt.y - d, },
          { x: pt.x + d, y: pt.y - d, },
          { x: pt.x + d, y: pt.y + d, },
          { x: pt.x - d, y: pt.y + d, },
        ])
      }
      continue
    }
    if len == 2 && group.end_type == Joined {
      self.end_type = if group.join_type == Round { Round } else { Square }
    }
    self.build_normals(path)
    match self.end_type {
      Polygon => self.offset_polygon(path)
      Joined => self.offset_open_joined(path)
      _ => self.offset_open_path(path)
    }
  }
}

///|
/// The added paths offset by `delta` (outwards for positive values on
/// polygons), with overlaps merged.
pub fn ClipperOffset::execute(
  self : ClipperOffset,
  delta : Double,
) -> Array[Array[Point64]] {
  self.solution.clear()
  if self.groups.is_empty() {
    return []
  }
  if delta.abs() < 0.5 {
    for g in self.groups {
      for p in g.paths_in {
        self.solution.push(p)
      }
    }
  } else {
    self.temp_lim = if self.miter_limit <= 1.0 {
      2.0
    } else {
      2.0 / (self.miter_limit * self.miter_limit)
    }
    self.delta = delta
    for g in self.groups {
      self.do_group_offset(g)
    }
  }
  if self.solution.is_empty() {
    return []
  }
  let mut paths_reversed = false
  for g in self.groups {
    if g.end_type == Polygon {
      paths_reversed = g.is_reversed
      break
    }
  }
  let c = Clipper64::new()
  c.set_preserve_collinear(self.preserve_collinear)
  c.set_reverse_solution(self.reverse_solution != paths_reversed)
  c.add_subject(self.solution)
  let fill : FillRule = if paths_reversed { Negative } else { Positive }
  match c.execute(Union, fill) {
    Some((closed, _)) => closed
    None => []
  }
}

///|
/// `paths` offset by `delta` with one join and end type (Clipper2's
/// `InflatePaths`; a positive `delta` grows polygons).
pub fn inflate_paths(
  paths : Array[Array[Point64]],
  delta : Double,
  join_type : JoinType,
  end_type : EndType,
  miter_limit~ : Double = 2.0,
  arc_tolerance~ : Double = 0.0,
) -> Array[Array[Point64]] {
  if delta == 0.0 {
    return paths
  }
  let o = ClipperOffset::new(miter_limit~, arc_tolerance~)
  o.add_paths(paths, join_type, end_type)
  o.execute(delta)
}
