// Ports the output-record handling of ClipperBase in Clipper2 2.0.1
// src/clipper.engine.cpp (commit 642390d), Boost Software License 1.0,
// Copyright (c) Angus Johnson 2010-2026. See NOTICE.

///|
fn Clipper64::add_local_min_poly(
  self : Clipper64,
  e1 : Active,
  e2 : Active,
  pt : Point64,
  is_new~ : Bool = false,
) -> OutPt {
  let outrec = self.new_outrec()
  e1.outrec = Some(outrec)
  e2.outrec = Some(outrec)
  if is_open(e1) {
    outrec.owner = None
    outrec.is_open = true
    if e1.wind_dx > 0 {
      set_sides(outrec, e1, e2)
    } else {
      set_sides(outrec, e2, e1)
    }
  } else {
    match get_prev_hot_edge(e1) {
      Some(prev_hot_edge) => {
        if self.using_polytree {
          set_owner(outrec, prev_hot_edge.outrec.unwrap())
        }
        if outrec_is_ascending(prev_hot_edge) == is_new {
          set_sides(outrec, e2, e1)
        } else {
          set_sides(outrec, e1, e2)
        }
      }
      None => {
        outrec.owner = None
        if is_new {
          set_sides(outrec, e1, e2)
        } else {
          set_sides(outrec, e2, e1)
        }
      }
    }
  }
  let op = OutPt::new(pt, outrec)
  outrec.pts = Some(op)
  op
}

///|
fn Clipper64::add_local_max_poly(
  self : Clipper64,
  e1 : Active,
  e2 : Active,
  pt : Point64,
) -> OutPt? {
  if is_joined(e1) {
    self.split(e1, pt)
  }
  if is_joined(e2) {
    self.split(e2, pt)
  }
  if is_front(e1) == is_front(e2) {
    if is_open_end(e1) {
      swap_sides(e1.outrec.unwrap())
    } else if is_open_end(e2) {
      swap_sides(e2.outrec.unwrap())
    } else {
      self.succeeded = false
      return None
    }
  }
  let mut result = self.add_out_pt(e1, pt)
  let or1 = e1.outrec.unwrap()
  let or2 = e2.outrec.unwrap()
  if physical_equal(or1, or2) {
    let outrec = or1
    outrec.pts = Some(result)
    if self.using_polytree {
      match get_prev_hot_edge(e1) {
        None => outrec.owner = None
        Some(e) => set_owner(outrec, e.outrec.unwrap())
      }
    }
    uncouple_outrec(e1)
    result = outrec.pts.unwrap()
    if outrec.owner is Some(o) && o.front_edge is None {
      outrec.owner = get_real_outrec(outrec.owner)
    }
  } else if is_open(e1) {
    if e1.wind_dx < 0 {
      self.join_outrec_paths(e1, e2)
    } else {
      self.join_outrec_paths(e2, e1)
    }
  } else if or1.idx < or2.idx {
    self.join_outrec_paths(e1, e2)
  } else {
    self.join_outrec_paths(e2, e1)
  }
  Some(result)
}

///|
/// Joins `e2`'s outrec path onto `e1`'s and empties `e2`'s.
fn Clipper64::join_outrec_paths(
  self : Clipper64,
  e1 : Active,
  e2 : Active,
) -> Unit {
  ignore(self)
  let or1 = e1.outrec.unwrap()
  let or2 = e2.outrec.unwrap()
  let p1_st = or1.pts.unwrap()
  let p2_st = or2.pts.unwrap()
  let p1_end = p1_st.n()
  let p2_end = p2_st.n()
  if is_front(e1) {
    p2_end.prev = Some(p1_st)
    p1_st.next = Some(p2_end)
    p2_st.next = Some(p1_end)
    p1_end.prev = Some(p2_st)
    or1.pts = Some(p2_st)
    or1.front_edge = or2.front_edge
    if or1.front_edge is Some(f) {
      f.outrec = Some(or1)
    }
  } else {
    p1_end.prev = Some(p2_st)
    p2_st.next = Some(p1_end)
    p1_st.next = Some(p2_end)
    p2_end.prev = Some(p1_st)
    or1.back_edge = or2.back_edge
    if or1.back_edge is Some(b) {
      b.outrec = Some(or1)
    }
  }
  or2.front_edge = None
  or2.back_edge = None
  or2.pts = None
  if is_open_end(e1) {
    or2.pts = or1.pts
    or1.pts = None
  } else {
    set_owner(or2, or1)
  }
  e1.outrec = None
  e2.outrec = None
}

///|
fn Clipper64::new_outrec(self : Clipper64) -> OutRec {
  let result : OutRec = {
    idx: self.outrec_list.length(),
    owner: None,
    front_edge: None,
    back_edge: None,
    pts: None,
    polypath: None,
    splits: None,
    recursive_split: None,
    bounds: { left: 0L, top: 0L, right: 0L, bottom: 0L, },
    path: [],
    is_open: false,
  }
  self.outrec_list.push(result)
  result
}

///|
fn Clipper64::add_out_pt(self : Clipper64, e : Active, pt : Point64) -> OutPt {
  ignore(self)
  let outrec = e.outrec.unwrap()
  let to_front = is_front(e)
  let op_front = outrec.pts.unwrap()
  let op_back = op_front.n()
  if to_front {
    if pt == op_front.pt {
      return op_front
    }
  } else if pt == op_back.pt {
    return op_back
  }
  let new_op = OutPt::new(pt, outrec)
  op_back.prev = Some(new_op)
  new_op.prev = Some(op_front)
  new_op.next = Some(op_back)
  op_front.next = Some(new_op)
  if to_front {
    outrec.pts = Some(new_op)
  }
  new_op
}

///|
fn Clipper64::clean_collinear(self : Clipper64, outrec : OutRec?) -> Unit {
  guard get_real_outrec(outrec) is Some(outrec) && !outrec.is_open else {
    return
  }
  if !is_valid_closed_path(outrec.pts) {
    outrec.pts = None
    return
  }
  let mut start_op = outrec.pts.unwrap()
  let mut op2 = start_op
  while true {
    if is_collinear(op2.p().pt, op2.pt, op2.n().pt) &&
      (
        op2.pt == op2.p().pt ||
        op2.pt == op2.n().pt ||
        !self.preserve_collinear ||
        dot_product(op2.p().pt, op2.pt, op2.n().pt) < 0.0
      ) {
      if outrec.pts is Some(p) && physical_equal(op2, p) {
        outrec.pts = op2.prev
      }
      op2 = dispose_out_pt(op2)
      if !is_valid_closed_path(Some(op2)) {
        outrec.pts = None
        return
      }
      start_op = op2
      continue
    }
    op2 = op2.n()
    if physical_equal(op2, start_op) {
      break
    }
  }
  self.fix_self_intersects(outrec)
}

///|
fn Clipper64::do_split_op(
  self : Clipper64,
  outrec : OutRec,
  split_op : OutPt,
) -> Unit {
  let prev_op = split_op.p()
  let next_next_op = split_op.n().n()
  outrec.pts = Some(prev_op)
  let ip = get_line_intersect_pt(
    prev_op.pt,
    split_op.pt,
    split_op.n().pt,
    next_next_op.pt,
  ).unwrap_or({ x: 0L, y: 0L, })
  let area1 = area_op(prev_op)
  let abs_area1 = area1.abs()
  if abs_area1 < 2.0 {
    outrec.pts = None
    return
  }
  let area2 = area_triangle(ip, split_op.pt, split_op.n().pt)
  let abs_area2 = area2.abs()
  if ip == prev_op.pt || ip == next_next_op.pt {
    next_next_op.prev = Some(prev_op)
    prev_op.next = Some(next_next_op)
  } else {
    let new_op2 = OutPt::new(ip, prev_op.outrec)
    new_op2.prev = Some(prev_op)
    new_op2.next = Some(next_next_op)
    next_next_op.prev = Some(new_op2)
    prev_op.next = Some(new_op2)
  }
  if abs_area2 >= 1.0 &&
    (abs_area2 > abs_area1 || (area2 > 0.0) == (area1 > 0.0)) {
    let new_or = self.new_outrec()
    new_or.owner = outrec.owner
    split_op.outrec = new_or
    split_op.n().outrec = new_or
    let new_op = OutPt::new(ip, new_or)
    new_op.prev = split_op.next
    new_op.next = Some(split_op)
    new_or.pts = Some(new_op)
    split_op.prev = Some(new_op)
    split_op.n().next = Some(new_op)
    if self.using_polytree {
      if path2_contains_path1_op(prev_op, new_op) {
        new_or.splits = Some([outrec])
      } else {
        match outrec.splits {
          Some(s) => s.push(new_or)
          None => outrec.splits = Some([new_or])
        }
      }
    }
  }
}

///|
fn Clipper64::fix_self_intersects(self : Clipper64, outrec : OutRec) -> Unit {
  let mut op2 = outrec.pts.unwrap()
  if physical_equal(op2.p(), op2.n().n()) {
    return
  }
  while true {
    if segments_intersect(op2.p().pt, op2.pt, op2.n().pt, op2.n().n().pt) {
      let pts = outrec.pts.unwrap()
      if physical_equal(op2, pts) || physical_equal(op2.n(), pts) {
        outrec.pts = pts.prev
      }
      self.do_split_op(outrec, op2)
      guard outrec.pts is Some(p) else { break }
      op2 = p
      if physical_equal(op2.p(), op2.n().n()) {
        break
      }
      continue
    } else {
      op2 = op2.n()
    }
    if physical_equal(op2, outrec.pts.unwrap()) {
      break
    }
  }
}

///|
fn update_outrec_owner(outrec : OutRec) -> Unit {
  let start = outrec.pts.unwrap()
  let mut op_curr = start
  while true {
    op_curr.outrec = outrec
    op_curr = op_curr.n()
    if physical_equal(op_curr, start) {
      return
    }
  }
}
