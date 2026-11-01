// Ports the free helper functions of Clipper2 2.0.1 src/clipper.engine.cpp
// (commit 642390d), Boost Software License 1.0, Copyright (c) Angus Johnson
// 2010-2026. See NOTICE.

///|
fn is_hot_edge(e : Active) -> Bool {
  e.outrec is Some(_)
}

///|
fn is_open(e : Active) -> Bool {
  e.local_min.is_open
}

///|
fn is_open_end_vertex(v : Vertex) -> Bool {
  (v.flags & (VERTEX_OPEN_START | VERTEX_OPEN_END)) != 0
}

///|
fn is_open_end(ae : Active) -> Bool {
  is_open_end_vertex(ae.vertex_top)
}

///|
fn get_prev_hot_edge(e : Active) -> Active? {
  let mut prev = e.prev_in_ael
  while prev is Some(p) && (is_open(p) || !is_hot_edge(p)) {
    prev = p.prev_in_ael
  }
  prev
}

///|
fn is_front(e : Active) -> Bool {
  match e.outrec.unwrap().front_edge {
    Some(f) => physical_equal(f, e)
    None => false
  }
}

///|
/// The edge's inverse slope (dx per dy); horizontals heading right are
/// -DBL_MAX, heading left +DBL_MAX (`GetDx`).
fn get_dx(pt1 : Point64, pt2 : Point64) -> Double {
  let dy = (pt2.y - pt1.y).to_double()
  if dy != 0.0 {
    (pt2.x - pt1.x).to_double() / dy
  } else if pt2.x > pt1.x {
    -@double.max_value
  } else {
    @double.max_value
  }
}

///|
fn top_x(ae : Active, current_y : Int64) -> Int64 {
  if current_y == ae.top.y || ae.top.x == ae.bot.x {
    ae.top.x
  } else if current_y == ae.bot.y {
    ae.bot.x
  } else {
    ae.bot.x + nearbyint(ae.dx * (current_y - ae.bot.y).to_double())
  }
}

///|
fn is_horizontal(e : Active) -> Bool {
  e.top.y == e.bot.y
}

///|
fn is_heading_right_horz(e : Active) -> Bool {
  e.dx == -@double.max_value
}

///|
fn is_heading_left_horz(e : Active) -> Bool {
  e.dx == @double.max_value
}

///|
fn get_poly_type(e : Active) -> PathType {
  e.local_min.polytype
}

///|
fn is_same_poly_type(e1 : Active, e2 : Active) -> Bool {
  e1.local_min.polytype == e2.local_min.polytype
}

///|
fn set_dx(e : Active) -> Unit {
  e.dx = get_dx(e.bot, e.top)
}

///|
fn next_vertex(e : Active) -> Vertex {
  if e.wind_dx > 0 {
    e.vertex_top.n()
  } else {
    e.vertex_top.p()
  }
}

///|
/// The (y-down) top of the alternate bound, for edge insertion.
fn prev_prev_vertex(ae : Active) -> Vertex {
  if ae.wind_dx > 0 {
    ae.vertex_top.p().p()
  } else {
    ae.vertex_top.n().n()
  }
}

///|
fn extract_from_sel(ae : Active) -> Active? {
  let res = ae.next_in_sel
  if res is Some(r) {
    r.prev_in_sel = ae.prev_in_sel
  }
  ae.prev_in_sel.unwrap().next_in_sel = res
  res
}

///|
fn insert1_before2_in_sel(ae1 : Active, ae2 : Active) -> Unit {
  ae1.prev_in_sel = ae2.prev_in_sel
  if ae1.prev_in_sel is Some(p) {
    p.next_in_sel = Some(ae1)
  }
  ae1.next_in_sel = Some(ae2)
  ae2.prev_in_sel = Some(ae1)
}

///|
fn is_maxima_vertex(v : Vertex) -> Bool {
  (v.flags & VERTEX_LOCAL_MAX) != 0
}

///|
fn is_maxima(e : Active) -> Bool {
  is_maxima_vertex(e.vertex_top)
}

///|
fn get_curr_y_maxima_vertex_open(e : Active) -> Vertex? {
  let mut result = e.vertex_top
  if e.wind_dx > 0 {
    while result.n().pt.y == result.pt.y &&
          (result.flags & (VERTEX_OPEN_END | VERTEX_LOCAL_MAX)) == 0 {
      result = result.n()
    }
  } else {
    while result.p().pt.y == result.pt.y &&
          (result.flags & (VERTEX_OPEN_END | VERTEX_LOCAL_MAX)) == 0 {
      result = result.p()
    }
  }
  if is_maxima_vertex(result) {
    Some(result)
  } else {
    None
  }
}

///|
fn get_curr_y_maxima_vertex(e : Active) -> Vertex? {
  let mut result = e.vertex_top
  if e.wind_dx > 0 {
    while result.n().pt.y == result.pt.y {
      result = result.n()
    }
  } else {
    while result.p().pt.y == result.pt.y {
      result = result.p()
    }
  }
  if is_maxima_vertex(result) {
    Some(result)
  } else {
    None
  }
}

///|
fn get_maxima_pair(e : Active) -> Active? {
  let mut e2 = e.next_in_ael
  while e2 is Some(a) {
    if physical_equal(a.vertex_top, e.vertex_top) {
      return Some(a)
    }
    e2 = a.next_in_ael
  }
  None
}

///|
fn duplicate_op(op : OutPt, insert_after : Bool) -> OutPt {
  let result = OutPt::new(op.pt, op.outrec)
  if insert_after {
    result.next = op.next
    result.n().prev = Some(result)
    result.prev = Some(op)
    op.next = Some(result)
  } else {
    result.prev = op.prev
    result.p().next = Some(result)
    result.next = Some(op)
    op.prev = Some(result)
  }
  result
}

///|
fn dispose_out_pt(op : OutPt) -> OutPt {
  let result = op.n()
  op.p().next = op.next
  op.n().prev = op.prev
  result
}

///|
fn intersect_list_less(a : IntersectNode, b : IntersectNode) -> Bool {
  if a.pt.y == b.pt.y {
    a.pt.x < b.pt.x
  } else {
    a.pt.y > b.pt.y
  }
}

///|
fn set_sides(outrec : OutRec, start_edge : Active, end_edge : Active) -> Unit {
  outrec.front_edge = Some(start_edge)
  outrec.back_edge = Some(end_edge)
}

///|
fn same_outrec(a : OutRec?, b : OutRec?) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(x), Some(y)) => physical_equal(x, y)
    _ => false
  }
}

///|
fn same_active(a : Active?, b : Active) -> Bool {
  match a {
    Some(x) => physical_equal(x, b)
    None => false
  }
}

///|
fn swap_outrecs(e1 : Active, e2 : Active) -> Unit {
  let or1 = e1.outrec
  let or2 = e2.outrec
  if same_outrec(or1, or2) {
    let o = or1.unwrap()
    let e = o.front_edge
    o.front_edge = o.back_edge
    o.back_edge = e
    return
  }
  if or1 is Some(o) {
    if same_active(o.front_edge, e1) {
      o.front_edge = Some(e2)
    } else {
      o.back_edge = Some(e2)
    }
  }
  if or2 is Some(o) {
    if same_active(o.front_edge, e2) {
      o.front_edge = Some(e1)
    } else {
      o.back_edge = Some(e1)
    }
  }
  e1.outrec = or2
  e2.outrec = or1
}

///|
fn area_op(op : OutPt) -> Double {
  let mut result = 0.0
  let mut op2 = op
  while true {
    result += (op2.p().pt.y + op2.pt.y).to_double() *
      (op2.p().pt.x - op2.pt.x).to_double()
    op2 = op2.n()
    if physical_equal(op2, op) {
      break
    }
  }
  result * 0.5
}

///|
fn area_triangle(pt1 : Point64, pt2 : Point64, pt3 : Point64) -> Double {
  (pt3.y + pt1.y).to_double() * (pt3.x - pt1.x).to_double() +
  (pt1.y + pt2.y).to_double() * (pt1.x - pt2.x).to_double() +
  (pt2.y + pt3.y).to_double() * (pt2.x - pt3.x).to_double()
}

///|
fn swap_sides(outrec : OutRec) -> Unit {
  let e2 = outrec.front_edge
  outrec.front_edge = outrec.back_edge
  outrec.back_edge = e2
  outrec.pts = Some(outrec.pts.unwrap().n())
}

///|
fn get_real_outrec(outrec : OutRec?) -> OutRec? {
  let mut o = outrec
  while o is Some(r) && r.pts is None {
    o = r.owner
  }
  o
}

///|
/// Whether `test_owner` can own `outrec` without owning itself.
fn is_valid_owner(outrec : OutRec, test_owner : OutRec?) -> Bool {
  let mut t = test_owner
  while t is Some(o) && !physical_equal(o, outrec) {
    t = o.owner
  }
  t is None
}

///|
fn uncouple_outrec(ae : Active) -> Unit {
  guard ae.outrec is Some(outrec) else { return }
  outrec.front_edge.unwrap().outrec = None
  outrec.back_edge.unwrap().outrec = None
  outrec.front_edge = None
  outrec.back_edge = None
}

///|
fn pts_really_close(pt1 : Point64, pt2 : Point64) -> Bool {
  (pt1.x - pt2.x).abs() < 2L && (pt1.y - pt2.y).abs() < 2L
}

///|
fn is_very_small_triangle(op : OutPt) -> Bool {
  physical_equal(op.n().n(), op.p()) &&
  (
    pts_really_close(op.p().pt, op.n().pt) ||
    pts_really_close(op.pt, op.n().pt) ||
    pts_really_close(op.pt, op.p().pt)
  )
}

///|
fn is_valid_closed_path(op : OutPt?) -> Bool {
  match op {
    None => false
    Some(o) =>
      !physical_equal(o.n(), o) &&
      !physical_equal(o.n(), o.p()) &&
      !is_very_small_triangle(o)
  }
}

///|
fn outrec_is_ascending(hot_edge : Active) -> Bool {
  same_active(hot_edge.outrec.unwrap().front_edge, hot_edge)
}

///|
fn edges_adjacent_in_ael(inode : IntersectNode) -> Bool {
  same_active(inode.edge1.next_in_ael, inode.edge2) ||
  same_active(inode.edge1.prev_in_ael, inode.edge2)
}

///|
fn is_joined(e : Active) -> Bool {
  e.join_with != NoJoin
}

///|
fn set_owner(outrec : OutRec, new_owner : OutRec) -> Unit {
  new_owner.owner = get_real_outrec(new_owner.owner)
  let mut tmp : OutRec? = Some(new_owner)
  while tmp is Some(t) && !physical_equal(t, outrec) {
    tmp = t.owner
  }
  if tmp is Some(_) {
    new_owner.owner = outrec.owner
  }
  outrec.owner = Some(new_owner)
}

///|
fn point_in_op_polygon(pt : Point64, op : OutPt) -> PointInPolygonResult {
  if physical_equal(op, op.n()) || physical_equal(op.p(), op.n()) {
    return IsOutside
  }
  let mut op = op
  let mut op2 = op
  while true {
    if op.pt.y != pt.y {
      break
    }
    op = op.n()
    if physical_equal(op, op2) {
      break
    }
  }
  if op.pt.y == pt.y {
    return IsOutside
  }
  let mut is_above = op.pt.y < pt.y
  let starting_above = is_above
  let mut val = 0
  op2 = op.n()
  while !physical_equal(op2, op) {
    if is_above {
      while !physical_equal(op2, op) && op2.pt.y < pt.y {
        op2 = op2.n()
      }
    } else {
      while !physical_equal(op2, op) && op2.pt.y > pt.y {
        op2 = op2.n()
      }
    }
    if physical_equal(op2, op) {
      break
    }
    if op2.pt.y == pt.y {
      if op2.pt.x == pt.x ||
        (op2.pt.y == op2.p().pt.y && (pt.x < op2.p().pt.x) != (pt.x < op2.pt.x)) {
        return IsOn
      }
      op2 = op2.n()
      if physical_equal(op2, op) {
        break
      }
      continue
    }
    if pt.x < op2.pt.x && pt.x < op2.p().pt.x {
      ()
    } else if pt.x > op2.p().pt.x && pt.x > op2.pt.x {
      val = 1 - val
    } else {
      let i = cross_product_sign(op2.p().pt, op2.pt, pt)
      if i == 0 {
        return IsOn
      }
      if (i < 0) == is_above {
        val = 1 - val
      }
    }
    is_above = !is_above
    op2 = op2.n()
  }
  if is_above != starting_above {
    let i = cross_product_sign(op2.p().pt, op2.pt, pt)
    if i == 0 {
      return IsOn
    }
    if (i < 0) == is_above {
      val = 1 - val
    }
  }
  if val == 0 {
    IsOutside
  } else {
    IsInside
  }
}

///|
fn get_clean_path(op : OutPt) -> Array[Point64] {
  let result = []
  let mut op2 = op
  while !physical_equal(op2.n(), op) &&
        (
          (op2.pt.x == op2.n().pt.x && op2.pt.x == op2.p().pt.x) ||
          (op2.pt.y == op2.n().pt.y && op2.pt.y == op2.p().pt.y)
        ) {
    op2 = op2.n()
  }
  result.push(op2.pt)
  let mut prev_op = op2
  op2 = op2.n()
  while !physical_equal(op2, op) {
    if (op2.pt.x != op2.n().pt.x || op2.pt.x != prev_op.pt.x) &&
      (op2.pt.y != op2.n().pt.y || op2.pt.y != prev_op.pt.y) {
      result.push(op2.pt)
      prev_op = op2
    }
    op2 = op2.n()
  }
  result
}

///|
fn path2_contains_path1_op(op1 : OutPt, op2 : OutPt) -> Bool {
  let mut pip = IsOn
  let mut op = op1
  while true {
    match point_in_op_polygon(op.pt, op2) {
      IsOutside => {
        if pip == IsOutside {
          return false
        }
        pip = IsOutside
      }
      IsInside => {
        if pip == IsInside {
          return true
        }
        pip = IsInside
      }
      IsOn => ()
    }
    op = op.n()
    if physical_equal(op, op1) {
      break
    }
  }
  path2_contains_path1(get_clean_path(op1), get_clean_path(op2))
}
