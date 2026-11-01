// Ports ClipperBase of Clipper2 2.0.1 src/clipper.engine.cpp (commit 642390d),
// Boost Software License 1.0, Copyright (c) Angus Johnson 2010-2026. See NOTICE.

///|
/// Clipper2's sweep-line engine (`ClipperBase` and `Clipper64`): add subject
/// and clip paths, then `execute` a boolean operation.
pub struct Clipper64 {
  priv mut cliptype : ClipType
  priv mut fillrule : FillRule
  priv mut bot_y : Int64
  priv mut minima_list_sorted : Bool
  priv mut using_polytree : Bool
  priv mut actives : Active?
  priv mut sel : Active?
  priv minima_list : Array[LocalMinima]
  priv mut current_locmin : Int32
  priv scanlines : Array[Int64]
  priv intersect_nodes : Array[IntersectNode]
  priv horz_seg_list : Array[HorzSegment]
  priv horz_join_list : Array[HorzJoin]
  priv mut preserve_collinear : Bool
  priv mut reverse_solution : Bool
  priv mut has_open_paths : Bool
  priv mut succeeded : Bool
  priv outrec_list : Array[OutRec]
}

///|
pub fn Clipper64::new() -> Clipper64 {
  {
    cliptype: NoClip,
    fillrule: EvenOdd,
    bot_y: 0L,
    minima_list_sorted: false,
    using_polytree: false,
    actives: None,
    sel: None,
    minima_list: [],
    current_locmin: 0,
    scanlines: [],
    intersect_nodes: [],
    horz_seg_list: [],
    horz_join_list: [],
    preserve_collinear: true,
    reverse_solution: false,
    has_open_paths: false,
    succeeded: true,
    outrec_list: [],
  }
}

///|
/// Whether collinear edges are kept in solutions (default true; 180° spikes
/// are always removed).
pub fn Clipper64::set_preserve_collinear(self : Clipper64, v : Bool) -> Unit {
  self.preserve_collinear = v
}

///|
/// Whether solutions are wound the other way round.
pub fn Clipper64::set_reverse_solution(self : Clipper64, v : Bool) -> Unit {
  self.reverse_solution = v
}

///|
fn Clipper64::clean_up(self : Clipper64) -> Unit {
  self.actives = None
  self.scanlines.clear()
  self.intersect_nodes.clear()
  self.outrec_list.clear()
  self.horz_seg_list.clear()
  self.horz_join_list.clear()
}

///|
/// Forgets every added path.
pub fn Clipper64::clear(self : Clipper64) -> Unit {
  self.clean_up()
  self.minima_list.clear()
  self.current_locmin = 0
  self.minima_list_sorted = false
  self.has_open_paths = false
}

///|
fn Clipper64::reset(self : Clipper64) -> Unit {
  if !self.minima_list_sorted {
    stable_sort(self.minima_list, (a, b) => {
      if b.vertex.pt.y != a.vertex.pt.y {
        b.vertex.pt.y < a.vertex.pt.y
      } else {
        b.vertex.pt.x > a.vertex.pt.x
      }
    })
    self.minima_list_sorted = true
  }
  for i = self.minima_list.length() - 1; i >= 0; i = i - 1 {
    self.insert_scanline(self.minima_list[i].vertex.pt.y)
  }
  self.current_locmin = 0
  self.actives = None
  self.sel = None
  self.succeeded = true
}

///|
/// Adds `v` to the scanline max-heap (`std::priority_queue<int64_t>`).
fn Clipper64::insert_scanline(self : Clipper64, y : Int64) -> Unit {
  let h = self.scanlines
  h.push(y)
  let mut i = h.length() - 1
  while i > 0 {
    let parent = (i - 1) / 2
    if h[parent] >= h[i] {
      break
    }
    let t = h[parent]
    h[parent] = h[i]
    h[i] = t
    i = parent
  }
}

///|
fn Clipper64::pop_heap(self : Clipper64) -> Int64 {
  let h = self.scanlines
  let top = h[0]
  let last = h.pop().unwrap()
  if h.length() > 0 {
    h[0] = last
    let n = h.length()
    let mut i = 0
    while true {
      let l = i * 2 + 1
      let r = l + 1
      let mut m = i
      if l < n && h[l] > h[m] {
        m = l
      }
      if r < n && h[r] > h[m] {
        m = r
      }
      if m == i {
        break
      }
      let t = h[m]
      h[m] = h[i]
      h[i] = t
      i = m
    }
  }
  top
}

///|
fn Clipper64::pop_scanline(self : Clipper64) -> Int64? {
  if self.scanlines.is_empty() {
    return None
  }
  let y = self.pop_heap()
  while !self.scanlines.is_empty() && self.scanlines[0] == y {
    self.pop_heap() |> ignore
  }
  Some(y)
}

///|
fn Clipper64::pop_local_minima(self : Clipper64, y : Int64) -> LocalMinima? {
  if self.current_locmin == self.minima_list.length() ||
    self.minima_list[self.current_locmin].vertex.pt.y != y {
    return None
  }
  let m = self.minima_list[self.current_locmin]
  self.current_locmin += 1
  Some(m)
}

///|
fn add_loc_min(
  list : Array[LocalMinima],
  vert : Vertex,
  polytype : PathType,
  is_open : Bool,
) -> Unit {
  if (vert.flags & VERTEX_LOCAL_MIN) != 0 {
    return
  }
  vert.flags = vert.flags | VERTEX_LOCAL_MIN
  list.push({ vertex: vert, polytype, is_open, })
}

///|
/// Links each path's points into a ring of vertices (duplicates dropped) and
/// records its local minima (`AddPaths_`).
fn add_paths_(
  paths : Array[Array[Point64]],
  polytype : PathType,
  is_open : Bool,
  loc_min_list : Array[LocalMinima],
) -> Unit {
  for path in paths {
    if path.is_empty() {
      continue
    }
    let mut v0 : Vertex? = None
    let mut prev_v : Vertex? = None
    let mut cnt = 0
    for pt in path {
      if prev_v is Some(p) && p.pt == pt {
        continue
      }
      let curr_v = { pt, next: None, prev: prev_v, flags: 0, }
      if prev_v is Some(p) {
        p.next = Some(curr_v)
      }
      if v0 is None {
        v0 = Some(curr_v)
      }
      prev_v = Some(curr_v)
      cnt += 1
    }
    guard prev_v is Some(last) && last.prev is Some(_) else { continue }
    let v0 = v0.unwrap()
    let mut last = last
    if !is_open && last.pt == v0.pt {
      last = last.p()
    }
    last.next = Some(v0)
    v0.prev = Some(last)
    if cnt < 2 || (cnt == 2 && !is_open) {
      continue
    }
    let mut going_up = false
    if is_open {
      let mut curr_v = v0.n()
      while !physical_equal(curr_v, v0) && curr_v.pt.y == v0.pt.y {
        curr_v = curr_v.n()
      }
      going_up = curr_v.pt.y <= v0.pt.y
      if going_up {
        v0.flags = VERTEX_OPEN_START
        add_loc_min(loc_min_list, v0, polytype, true)
      } else {
        v0.flags = VERTEX_OPEN_START | VERTEX_LOCAL_MAX
      }
    } else {
      let mut p = v0.p()
      while !physical_equal(p, v0) && p.pt.y == v0.pt.y {
        p = p.p()
      }
      if physical_equal(p, v0) {
        continue
      }
      going_up = p.pt.y > v0.pt.y
    }
    let going_up0 = going_up
    let mut prev = v0
    let mut curr = v0.n()
    while !physical_equal(curr, v0) {
      if curr.pt.y > prev.pt.y && going_up {
        prev.flags = prev.flags | VERTEX_LOCAL_MAX
        going_up = false
      } else if curr.pt.y < prev.pt.y && !going_up {
        going_up = true
        add_loc_min(loc_min_list, prev, polytype, is_open)
      }
      prev = curr
      curr = curr.n()
    }
    if is_open {
      prev.flags = prev.flags | VERTEX_OPEN_END
      if going_up {
        prev.flags = prev.flags | VERTEX_LOCAL_MAX
      } else {
        add_loc_min(loc_min_list, prev, polytype, is_open)
      }
    } else if going_up != going_up0 {
      if going_up0 {
        add_loc_min(loc_min_list, prev, polytype, false)
      } else {
        prev.flags = prev.flags | VERTEX_LOCAL_MAX
      }
    }
  }
}

///|
fn Clipper64::add_paths_of(
  self : Clipper64,
  paths : Array[Array[Point64]],
  polytype : PathType,
  is_open : Bool,
) -> Unit {
  if is_open {
    self.has_open_paths = true
  }
  self.minima_list_sorted = false
  add_paths_(paths, polytype, is_open, self.minima_list)
}

///|
/// Adds closed subject paths.
pub fn Clipper64::add_subject(
  self : Clipper64,
  paths : Array[Array[Point64]],
) -> Unit {
  self.add_paths_of(paths, Subject, false)
}

///|
/// Adds open subject paths (polylines).
pub fn Clipper64::add_open_subject(
  self : Clipper64,
  paths : Array[Array[Point64]],
) -> Unit {
  self.add_paths_of(paths, Subject, true)
}

///|
/// Adds clip paths (always closed).
pub fn Clipper64::add_clip(
  self : Clipper64,
  paths : Array[Array[Point64]],
) -> Unit {
  self.add_paths_of(paths, Clip, false)
}

///|
fn Clipper64::is_contributing_closed(self : Clipper64, e : Active) -> Bool {
  match self.fillrule {
    EvenOdd => ()
    NonZero => if e.wind_cnt.abs() != 1 { return false }
    Positive => if e.wind_cnt != 1 { return false }
    Negative => if e.wind_cnt != -1 { return false }
  }
  match self.cliptype {
    NoClip => false
    Intersection =>
      match self.fillrule {
        Positive => e.wind_cnt2 > 0
        Negative => e.wind_cnt2 < 0
        _ => e.wind_cnt2 != 0
      }
    Union =>
      match self.fillrule {
        Positive => e.wind_cnt2 <= 0
        Negative => e.wind_cnt2 >= 0
        _ => e.wind_cnt2 == 0
      }
    Difference => {
      let result = match self.fillrule {
        Positive => e.wind_cnt2 <= 0
        Negative => e.wind_cnt2 >= 0
        _ => e.wind_cnt2 == 0
      }
      if get_poly_type(e) == Subject {
        result
      } else {
        !result
      }
    }
    Xor => true
  }
}

///|
fn Clipper64::is_contributing_open(self : Clipper64, e : Active) -> Bool {
  let (is_in_clip, is_in_subj) = match self.fillrule {
    Positive => (e.wind_cnt2 > 0, e.wind_cnt > 0)
    Negative => (e.wind_cnt2 < 0, e.wind_cnt < 0)
    _ => (e.wind_cnt2 != 0, e.wind_cnt != 0)
  }
  match self.cliptype {
    Intersection => is_in_clip
    Union => !is_in_subj && !is_in_clip
    _ => !is_in_clip
  }
}

///|
/// Sets `e`'s winding counts: its own polytype's (the higher of the two
/// regions it borders) and the other polytype's.
fn Clipper64::set_wind_count_for_closed_path_edge(
  self : Clipper64,
  e : Active,
) -> Unit {
  let mut e2 = e.prev_in_ael
  let pt = get_poly_type(e)
  while e2 is Some(a) && (get_poly_type(a) != pt || is_open(a)) {
    e2 = a.prev_in_ael
  }
  match e2 {
    None => {
      e.wind_cnt = e.wind_dx
      e2 = self.actives
    }
    Some(a) if self.fillrule == EvenOdd => {
      e.wind_cnt = e.wind_dx
      e.wind_cnt2 = a.wind_cnt2
      e2 = a.next_in_ael
    }
    Some(a) => {
      if a.wind_cnt * a.wind_dx < 0 {
        if a.wind_cnt.abs() > 1 {
          if a.wind_dx * e.wind_dx < 0 {
            e.wind_cnt = a.wind_cnt
          } else {
            e.wind_cnt = a.wind_cnt + e.wind_dx
          }
        } else {
          e.wind_cnt = if is_open(e) { 1 } else { e.wind_dx }
        }
      } else if a.wind_dx * e.wind_dx < 0 {
        e.wind_cnt = a.wind_cnt
      } else {
        e.wind_cnt = a.wind_cnt + e.wind_dx
      }
      e.wind_cnt2 = a.wind_cnt2
      e2 = a.next_in_ael
    }
  }
  if self.fillrule == EvenOdd {
    while e2 is Some(a) && !physical_equal(a, e) {
      if get_poly_type(a) != pt && !is_open(a) {
        e.wind_cnt2 = if e.wind_cnt2 == 0 { 1 } else { 0 }
      }
      e2 = a.next_in_ael
    }
  } else {
    while e2 is Some(a) && !physical_equal(a, e) {
      if get_poly_type(a) != pt && !is_open(a) {
        e.wind_cnt2 += a.wind_dx
      }
      e2 = a.next_in_ael
    }
  }
}

///|
fn Clipper64::set_wind_count_for_open_path_edge(
  self : Clipper64,
  e : Active,
) -> Unit {
  let mut e2 = self.actives
  if self.fillrule == EvenOdd {
    let mut cnt1 = 0
    let mut cnt2 = 0
    while e2 is Some(a) && !physical_equal(a, e) {
      if get_poly_type(a) == Clip {
        cnt2 += 1
      } else if !is_open(a) {
        cnt1 += 1
      }
      e2 = a.next_in_ael
    }
    e.wind_cnt = if cnt1 % 2 != 0 { 1 } else { 0 }
    e.wind_cnt2 = if cnt2 % 2 != 0 { 1 } else { 0 }
  } else {
    while e2 is Some(a) && !physical_equal(a, e) {
      if get_poly_type(a) == Clip {
        e.wind_cnt2 += a.wind_dx
      } else if !is_open(a) {
        e.wind_cnt += a.wind_dx
      }
      e2 = a.next_in_ael
    }
  }
}

///|
/// Whether `newcomer` belongs to the right of `resident` in the AEL.
fn is_valid_ael_order(resident : Active, newcomer : Active) -> Bool {
  if newcomer.curr_x != resident.curr_x {
    return newcomer.curr_x > resident.curr_x
  }
  let i = cross_product_sign(resident.top, newcomer.bot, newcomer.top)
  if i != 0 {
    return i < 0
  }
  if !is_maxima(resident) && resident.top.y > newcomer.top.y {
    return cross_product_sign(
        newcomer.bot,
        resident.top,
        next_vertex(resident).pt,
      ) <=
      0
  } else if !is_maxima(newcomer) && newcomer.top.y > resident.top.y {
    return cross_product_sign(
        newcomer.bot,
        newcomer.top,
        next_vertex(newcomer).pt,
      ) >=
      0
  }
  let y = newcomer.bot.y
  let newcomer_is_left = newcomer.is_left_bound
  if resident.bot.y != y || resident.local_min.vertex.pt.y != y {
    newcomer.is_left_bound
  } else if resident.is_left_bound != newcomer_is_left {
    newcomer_is_left
  } else if is_collinear(
      prev_prev_vertex(resident).pt,
      resident.bot,
      resident.top,
    ) {
    true
  } else {
    (
      cross_product_sign(
        prev_prev_vertex(resident).pt,
        newcomer.bot,
        prev_prev_vertex(newcomer).pt,
      ) >
      0
    ) ==
    newcomer_is_left
  }
}

///|
fn Clipper64::insert_left_edge(self : Clipper64, e : Active) -> Unit {
  match self.actives {
    None => {
      e.prev_in_ael = None
      e.next_in_ael = None
      self.actives = Some(e)
    }
    Some(first) if !is_valid_ael_order(first, e) => {
      e.prev_in_ael = None
      e.next_in_ael = Some(first)
      first.prev_in_ael = Some(e)
      self.actives = Some(e)
    }
    Some(first) => {
      let mut e2 = first
      while e2.next_in_ael is Some(n) && is_valid_ael_order(n, e) {
        e2 = n
      }
      if e2.join_with == Right {
        guard e2.next_in_ael is Some(n) else { return }
        e2 = n
      }
      e.next_in_ael = e2.next_in_ael
      if e2.next_in_ael is Some(n) {
        n.prev_in_ael = Some(e)
      }
      e.prev_in_ael = Some(e2)
      e2.next_in_ael = Some(e)
    }
  }
}

///|
fn insert_right_edge(e : Active, e2 : Active) -> Unit {
  e2.next_in_ael = e.next_in_ael
  if e.next_in_ael is Some(n) {
    n.prev_in_ael = Some(e2)
  }
  e2.prev_in_ael = Some(e)
  e.next_in_ael = Some(e2)
}

///|
fn new_bound(
  local_minima : LocalMinima,
  wind_dx : Int32,
  vertex_top : Vertex,
) -> Active {
  let a : Active = {
    bot: local_minima.vertex.pt,
    top: vertex_top.pt,
    curr_x: local_minima.vertex.pt.x,
    dx: 0.0,
    wind_dx,
    wind_cnt: 0,
    wind_cnt2: 0,
    outrec: None,
    prev_in_ael: None,
    next_in_ael: None,
    prev_in_sel: None,
    next_in_sel: None,
    jump: None,
    vertex_top,
    local_min: local_minima,
    is_left_bound: false,
    join_with: NoJoin,
  }
  set_dx(a)
  a
}

///|
fn Clipper64::insert_local_minima_into_ael(
  self : Clipper64,
  bot_y : Int64,
) -> Unit {
  while self.pop_local_minima(bot_y) is Some(local_minima) {
    let mut left_bound = if (local_minima.vertex.flags & VERTEX_OPEN_START) != 0 {
      None
    } else {
      Some(new_bound(local_minima, -1, local_minima.vertex.p()))
    }
    let mut right_bound = if (local_minima.vertex.flags & VERTEX_OPEN_END) != 0 {
      None
    } else {
      Some(new_bound(local_minima, 1, local_minima.vertex.n()))
    }
    match (left_bound, right_bound) {
      (Some(l), Some(r)) =>
        if is_horizontal(l) {
          if is_heading_right_horz(l) {
            left_bound = Some(r)
            right_bound = Some(l)
          }
        } else if is_horizontal(r) {
          if is_heading_left_horz(r) {
            left_bound = Some(r)
            right_bound = Some(l)
          }
        } else if l.dx < r.dx {
          left_bound = Some(r)
          right_bound = Some(l)
        }
      (None, _) => {
        left_bound = right_bound
        right_bound = None
      }
      _ => ()
    }
    let left = left_bound.unwrap()
    left.is_left_bound = true
    self.insert_left_edge(left)
    let contributing = if is_open(left) {
      self.set_wind_count_for_open_path_edge(left)
      self.is_contributing_open(left)
    } else {
      self.set_wind_count_for_closed_path_edge(left)
      self.is_contributing_closed(left)
    }
    match right_bound {
      Some(right) => {
        right.is_left_bound = false
        right.wind_cnt = left.wind_cnt
        right.wind_cnt2 = left.wind_cnt2
        insert_right_edge(left, right)
        if contributing {
          self.add_local_min_poly(left, right, left.bot, is_new=true) |> ignore
          if !is_horizontal(left) {
            self.check_join_left(left, left.bot)
          }
        }
        while right.next_in_ael is Some(n) && is_valid_ael_order(n, right) {
          self.intersect_edges(right, n, right.bot)
          self.swap_positions_in_ael(right, n)
        }
        if is_horizontal(right) {
          self.push_horz(right)
        } else {
          self.check_join_right(right, right.bot)
          self.insert_scanline(right.top.y)
        }
      }
      None => if contributing { self.start_open_path(left, left.bot) |> ignore }
    }
    if is_horizontal(left) {
      self.push_horz(left)
    } else {
      self.insert_scanline(left.top.y)
    }
  }
}

///|
fn Clipper64::push_horz(self : Clipper64, e : Active) -> Unit {
  e.next_in_sel = self.sel
  self.sel = Some(e)
}

///|
fn Clipper64::pop_horz(self : Clipper64) -> Active? {
  let e = self.sel
  if e is Some(a) {
    self.sel = a.next_in_sel
  }
  e
}
