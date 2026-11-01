// Ports the sweep of ClipperBase in Clipper2 2.0.1 src/clipper.engine.cpp
// (commit 642390d), Boost Software License 1.0, Copyright (c) Angus Johnson
// 2010-2026. See NOTICE.

///|
fn Clipper64::start_open_path(
  self : Clipper64,
  e : Active,
  pt : Point64,
) -> OutPt {
  let outrec = self.new_outrec()
  outrec.is_open = true
  if e.wind_dx > 0 {
    outrec.front_edge = Some(e)
    outrec.back_edge = None
  } else {
    outrec.front_edge = None
    outrec.back_edge = Some(e)
  }
  e.outrec = Some(outrec)
  let op = OutPt::new(pt, outrec)
  outrec.pts = Some(op)
  op
}

///|
fn Clipper64::update_edge_into_ael(self : Clipper64, e : Active) -> Unit {
  e.bot = e.top
  e.vertex_top = next_vertex(e)
  e.top = e.vertex_top.pt
  e.curr_x = e.bot.x
  set_dx(e)
  if is_joined(e) {
    self.split(e, e.bot)
  }
  if is_horizontal(e) {
    if !is_open(e) {
      trim_horz(e, self.preserve_collinear)
    }
    return
  }
  self.insert_scanline(e.top.y)
  self.check_join_left(e, e.bot)
  self.check_join_right(e, e.bot, check_curr_x=true)
}

///|
fn find_edge_with_matching_loc_min(e : Active) -> Active? {
  let mut result = e.next_in_ael
  while result is Some(r) {
    if physical_equal(r.local_min, e.local_min) {
      return Some(r)
    } else if !is_horizontal(r) && e.bot != r.bot {
      result = None
    } else {
      result = r.next_in_ael
    }
  }
  result = e.prev_in_ael
  while result is Some(r) {
    if physical_equal(r.local_min, e.local_min) {
      return Some(r)
    } else if !is_horizontal(r) && e.bot != r.bot {
      return None
    } else {
      result = r.prev_in_ael
    }
  }
  result
}

///|
fn Clipper64::intersect_edges(
  self : Clipper64,
  e1 : Active,
  e2 : Active,
  pt : Point64,
) -> Unit {
  if self.has_open_paths && (is_open(e1) || is_open(e2)) {
    if is_open(e1) && is_open(e2) {
      return
    }
    let (edge_o, edge_c) = if is_open(e1) { (e1, e2) } else { (e2, e1) }
    if is_joined(edge_c) {
      self.split(edge_c, pt)
    }
    if edge_c.wind_cnt.abs() != 1 {
      return
    }
    match self.cliptype {
      Union => if !is_hot_edge(edge_c) { return }
      _ => if edge_c.local_min.polytype == Subject { return }
    }
    match self.fillrule {
      Positive => if edge_c.wind_cnt != 1 { return }
      Negative => if edge_c.wind_cnt != -1 { return }
      _ => if edge_c.wind_cnt.abs() != 1 { return }
    }
    if is_hot_edge(edge_o) {
      self.add_out_pt(edge_o, pt) |> ignore
      let o = edge_o.outrec.unwrap()
      if is_front(edge_o) {
        o.front_edge = None
      } else {
        o.back_edge = None
      }
      edge_o.outrec = None
    } else if pt == edge_o.local_min.vertex.pt &&
      !is_open_end_vertex(edge_o.local_min.vertex) {
      match find_edge_with_matching_loc_min(edge_o) {
        Some(e3) if is_hot_edge(e3) => {
          let o = e3.outrec.unwrap()
          edge_o.outrec = Some(o)
          if edge_o.wind_dx > 0 {
            set_sides(o, edge_o, e3)
          } else {
            set_sides(o, e3, edge_o)
          }
          return
        }
        _ => self.start_open_path(edge_o, pt) |> ignore
      }
    } else {
      self.start_open_path(edge_o, pt) |> ignore
    }
    return
  }
  if is_joined(e1) {
    self.split(e1, pt)
  }
  if is_joined(e2) {
    self.split(e2, pt)
  }
  if e1.local_min.polytype == e2.local_min.polytype {
    if self.fillrule == EvenOdd {
      let old = e1.wind_cnt
      e1.wind_cnt = e2.wind_cnt
      e2.wind_cnt = old
    } else {
      if e1.wind_cnt + e2.wind_dx == 0 {
        e1.wind_cnt = -e1.wind_cnt
      } else {
        e1.wind_cnt += e2.wind_dx
      }
      if e2.wind_cnt - e1.wind_dx == 0 {
        e2.wind_cnt = -e2.wind_cnt
      } else {
        e2.wind_cnt -= e1.wind_dx
      }
    }
  } else if self.fillrule != EvenOdd {
    e1.wind_cnt2 += e2.wind_dx
    e2.wind_cnt2 -= e1.wind_dx
  } else {
    e1.wind_cnt2 = if e1.wind_cnt2 == 0 { 1 } else { 0 }
    e2.wind_cnt2 = if e2.wind_cnt2 == 0 { 1 } else { 0 }
  }
  let (old_e1_windcnt, old_e2_windcnt) = match self.fillrule {
    EvenOdd | NonZero => (e1.wind_cnt.abs(), e2.wind_cnt.abs())
    Positive => (e1.wind_cnt, e2.wind_cnt)
    Negative => (-e1.wind_cnt, -e2.wind_cnt)
  }
  let e1_in_01 = old_e1_windcnt == 0 || old_e1_windcnt == 1
  let e2_in_01 = old_e2_windcnt == 0 || old_e2_windcnt == 1
  if (!is_hot_edge(e1) && !e1_in_01) || (!is_hot_edge(e2) && !e2_in_01) {
    return
  }
  if is_hot_edge(e1) && is_hot_edge(e2) {
    if (old_e1_windcnt != 0 && old_e1_windcnt != 1) ||
      (old_e2_windcnt != 0 && old_e2_windcnt != 1) ||
      (e1.local_min.polytype != e2.local_min.polytype && self.cliptype != Xor) {
      self.add_local_max_poly(e1, e2, pt) |> ignore
    } else if is_front(e1) || same_outrec(e1.outrec, e2.outrec) {
      self.add_local_max_poly(e1, e2, pt) |> ignore
      self.add_local_min_poly(e1, e2, pt) |> ignore
    } else {
      self.add_out_pt(e1, pt) |> ignore
      self.add_out_pt(e2, pt) |> ignore
      swap_outrecs(e1, e2)
    }
  } else if is_hot_edge(e1) {
    self.add_out_pt(e1, pt) |> ignore
    swap_outrecs(e1, e2)
  } else if is_hot_edge(e2) {
    self.add_out_pt(e2, pt) |> ignore
    swap_outrecs(e1, e2)
  } else {
    let (e1_wc2, e2_wc2) = match self.fillrule {
      EvenOdd | NonZero => (e1.wind_cnt2.abs(), e2.wind_cnt2.abs())
      Positive => (e1.wind_cnt2, e2.wind_cnt2)
      Negative => (-e1.wind_cnt2, -e2.wind_cnt2)
    }
    if !is_same_poly_type(e1, e2) {
      self.add_local_min_poly(e1, e2, pt) |> ignore
    } else if old_e1_windcnt == 1 && old_e2_windcnt == 1 {
      match self.cliptype {
        Union =>
          if e1_wc2 <= 0 && e2_wc2 <= 0 {
            self.add_local_min_poly(e1, e2, pt) |> ignore
          }
        Difference =>
          if (get_poly_type(e1) == Clip && e1_wc2 > 0 && e2_wc2 > 0) ||
            (get_poly_type(e1) == Subject && e1_wc2 <= 0 && e2_wc2 <= 0) {
            self.add_local_min_poly(e1, e2, pt) |> ignore
          }
        Xor => self.add_local_min_poly(e1, e2, pt) |> ignore
        _ =>
          if e1_wc2 > 0 && e2_wc2 > 0 {
            self.add_local_min_poly(e1, e2, pt) |> ignore
          }
      }
    }
  }
}

///|
fn Clipper64::delete_from_ael(self : Clipper64, e : Active) -> Unit {
  let prev = e.prev_in_ael
  let next = e.next_in_ael
  if prev is None && next is None && !same_active(self.actives, e) {
    return
  }
  match prev {
    Some(p) => p.next_in_ael = next
    None => self.actives = next
  }
  if next is Some(n) {
    n.prev_in_ael = prev
  }
  e.prev_in_ael = None
  e.next_in_ael = None
}

///|
fn Clipper64::adjust_curr_x_and_copy_to_sel(
  self : Clipper64,
  top_y : Int64,
) -> Unit {
  let mut e = self.actives
  self.sel = e
  while e is Some(a) {
    a.prev_in_sel = a.prev_in_ael
    a.next_in_sel = a.next_in_ael
    a.jump = a.next_in_sel
    a.curr_x = top_x(a, top_y)
    e = a.next_in_ael
  }
}

///|
fn Clipper64::execute_internal(
  self : Clipper64,
  ct : ClipType,
  fillrule : FillRule,
  use_polytrees : Bool,
) -> Bool {
  self.cliptype = ct
  self.fillrule = fillrule
  self.using_polytree = use_polytrees
  self.reset()
  guard ct != NoClip && self.pop_scanline() is Some(first) else { return true }
  let mut y = first
  while self.succeeded {
    self.insert_local_minima_into_ael(y)
    while self.pop_horz() is Some(e) {
      self.do_horizontal(e)
    }
    if self.horz_seg_list.length() > 0 {
      self.convert_horz_segs_to_joins()
      self.horz_seg_list.clear()
    }
    self.bot_y = y
    guard self.pop_scanline() is Some(next) else { break }
    y = next
    self.do_intersections(y)
    self.do_top_of_scanbeam(y)
    while self.pop_horz() is Some(e) {
      self.do_horizontal(e)
    }
  }
  if self.succeeded {
    self.process_horz_joins()
  }
  self.succeeded
}

///|
fn fix_outrec_pts(outrec : OutRec) -> Unit {
  update_outrec_owner(outrec)
}

///|
fn Clipper64::do_intersections(self : Clipper64, top_y : Int64) -> Unit {
  if self.build_intersect_list(top_y) {
    self.process_intersect_list()
    self.intersect_nodes.clear()
  }
}

///|
fn Clipper64::add_new_intersect_node(
  self : Clipper64,
  e1 : Active,
  e2 : Active,
  top_y : Int64,
) -> Unit {
  let mut ip = match get_line_intersect_pt(e1.bot, e1.top, e2.bot, e2.top) {
    Some(p) => p
    None => { x: e1.curr_x, y: top_y, }
  }
  if ip.y > self.bot_y || ip.y < top_y {
    let abs_dx1 = e1.dx.abs()
    let abs_dx2 = e2.dx.abs()
    if abs_dx1 > 100.0 && abs_dx2 > 100.0 {
      if abs_dx1 > abs_dx2 {
        ip = get_closest_point_on_segment(ip, e1.bot, e1.top)
      } else {
        ip = get_closest_point_on_segment(ip, e2.bot, e2.top)
      }
    } else if abs_dx1 > 100.0 {
      ip = get_closest_point_on_segment(ip, e1.bot, e1.top)
    } else if abs_dx2 > 100.0 {
      ip = get_closest_point_on_segment(ip, e2.bot, e2.top)
    } else {
      let y = if ip.y < top_y { top_y } else { self.bot_y }
      let x = if abs_dx1 < abs_dx2 { top_x(e1, y) } else { top_x(e2, y) }
      ip = { x, y, }
    }
  }
  self.intersect_nodes.push({ pt: ip, edge1: e1, edge2: e2, })
}

///|
/// Finds the intersections in the current scanbeam with a merge sort of the
/// SEL that only ever swaps adjacent edges.
fn Clipper64::build_intersect_list(self : Clipper64, top_y : Int64) -> Bool {
  guard self.actives is Some(a) && a.next_in_ael is Some(_) else {
    return false
  }
  self.adjust_curr_x_and_copy_to_sel(top_y)
  let mut left = self.sel
  while left is Some(l0) && l0.jump is Some(_) {
    let mut prev_base : Active? = None
    while left is Some(lft) && lft.jump is Some(_) {
      let mut curr_base = lft
      let mut l = lft
      let mut right = lft.jump
      let mut l_end = right
      let r_end = right.unwrap().jump
      l.jump = r_end
      while !same_opt(Some(l), l_end) && !same_opt(right, r_end) {
        let r = right.unwrap()
        if r.curr_x < l.curr_x {
          let mut tmp = r.prev_in_sel.unwrap()
          while true {
            self.add_new_intersect_node(tmp, r, top_y)
            if physical_equal(tmp, l) {
              break
            }
            tmp = tmp.prev_in_sel.unwrap()
          }
          tmp = r
          right = extract_from_sel(tmp)
          l_end = right
          insert1_before2_in_sel(tmp, l)
          if physical_equal(l, curr_base) {
            curr_base = tmp
            curr_base.jump = r_end
            match prev_base {
              None => self.sel = Some(curr_base)
              Some(p) => p.jump = Some(curr_base)
            }
          }
        } else {
          l = l.next_in_sel.unwrap()
        }
      }
      prev_base = Some(curr_base)
      left = r_end
    }
    left = self.sel
  }
  self.intersect_nodes.length() > 0
}

///|
fn same_opt(a : Active?, b : Active?) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(x), Some(y)) => physical_equal(x, y)
    _ => false
  }
}

///|
fn Clipper64::process_intersect_list(self : Clipper64) -> Unit {
  let nodes = self.intersect_nodes
  libcxx_sort(nodes, intersect_list_less)
  for i in 0..<nodes.length() {
    if !edges_adjacent_in_ael(nodes[i]) {
      let mut k = i + 1
      while !edges_adjacent_in_ael(nodes[k]) {
        k += 1
      }
      let t = nodes[i]
      nodes[i] = nodes[k]
      nodes[k] = t
    }
    let node = nodes[i]
    self.intersect_edges(node.edge1, node.edge2, node.pt)
    self.swap_positions_in_ael(node.edge1, node.edge2)
    node.edge1.curr_x = node.pt.x
    node.edge2.curr_x = node.pt.x
    self.check_join_left(node.edge2, node.pt, check_curr_x=true)
    self.check_join_right(node.edge1, node.pt, check_curr_x=true)
  }
}

///|
/// Swaps `e1` and `e2`, `e1` being immediately left of `e2` in the AEL.
fn Clipper64::swap_positions_in_ael(
  self : Clipper64,
  e1 : Active,
  e2 : Active,
) -> Unit {
  let next = e2.next_in_ael
  if next is Some(n) {
    n.prev_in_ael = Some(e1)
  }
  let prev = e1.prev_in_ael
  if prev is Some(p) {
    p.next_in_ael = Some(e2)
  }
  e2.prev_in_ael = prev
  e2.next_in_ael = Some(e1)
  e1.prev_in_ael = Some(e2)
  e1.next_in_ael = next
  if e2.prev_in_ael is None {
    self.actives = Some(e2)
  }
}

///|
fn Clipper64::do_top_of_scanbeam(self : Clipper64, y : Int64) -> Unit {
  self.sel = None
  let mut e = self.actives
  while e is Some(a) {
    if a.top.y == y {
      a.curr_x = a.top.x
      if is_maxima(a) {
        e = self.do_maxima(a)
        continue
      } else {
        if is_hot_edge(a) {
          self.add_out_pt(a, a.top) |> ignore
        }
        self.update_edge_into_ael(a)
        if is_horizontal(a) {
          self.push_horz(a)
        }
      }
    } else {
      a.curr_x = top_x(a, y)
    }
    e = a.next_in_ael
  }
}

///|
fn Clipper64::do_maxima(self : Clipper64, e : Active) -> Active? {
  let prev_e = e.prev_in_ael
  let mut next_e = e.next_in_ael
  if is_open_end(e) {
    if is_hot_edge(e) {
      self.add_out_pt(e, e.top) |> ignore
    }
    if !is_horizontal(e) {
      if is_hot_edge(e) {
        let o = e.outrec.unwrap()
        if is_front(e) {
          o.front_edge = None
        } else {
          o.back_edge = None
        }
        e.outrec = None
      }
      self.delete_from_ael(e)
    }
    return next_e
  }
  guard get_maxima_pair(e) is Some(max_pair) else { return next_e }
  if is_joined(e) {
    self.split(e, e.top)
  }
  if is_joined(max_pair) {
    self.split(max_pair, max_pair.top)
  }
  while !same_opt(next_e, Some(max_pair)) {
    let n = next_e.unwrap()
    self.intersect_edges(e, n, e.top)
    self.swap_positions_in_ael(e, n)
    next_e = e.next_in_ael
  }
  if is_open(e) {
    if is_hot_edge(e) {
      self.add_local_max_poly(e, max_pair, e.top) |> ignore
    }
    self.delete_from_ael(max_pair)
    self.delete_from_ael(e)
    return match prev_e {
      Some(p) => p.next_in_ael
      None => self.actives
    }
  }
  if is_hot_edge(e) {
    self.add_local_max_poly(e, max_pair, e.top) |> ignore
  }
  self.delete_from_ael(e)
  self.delete_from_ael(max_pair)
  match prev_e {
    Some(p) => p.next_in_ael
    None => self.actives
  }
}

///|
fn Clipper64::split(self : Clipper64, e : Active, pt : Point64) -> Unit {
  if e.join_with == Right {
    e.join_with = NoJoin
    let n = e.next_in_ael.unwrap()
    n.join_with = NoJoin
    self.add_local_min_poly(e, n, pt, is_new=true) |> ignore
  } else {
    e.join_with = NoJoin
    let p = e.prev_in_ael.unwrap()
    p.join_with = NoJoin
    self.add_local_min_poly(p, e, pt, is_new=true) |> ignore
  }
}

///|
fn Clipper64::check_join_left(
  self : Clipper64,
  e : Active,
  pt : Point64,
  check_curr_x~ : Bool = false,
) -> Unit {
  guard e.prev_in_ael is Some(prev) else { return }
  if !is_hot_edge(e) ||
    !is_hot_edge(prev) ||
    is_horizontal(e) ||
    is_horizontal(prev) ||
    is_open(e) ||
    is_open(prev) {
    return
  }
  if (pt.y < e.top.y + 2L || pt.y < prev.top.y + 2L) &&
    (e.bot.y > pt.y || prev.bot.y > pt.y) {
    return
  }
  if check_curr_x {
    if perpendic_dist_from_line_sqrd(pt, prev.bot, prev.top) > 0.25 {
      return
    }
  } else if e.curr_x != prev.curr_x {
    return
  }
  if !is_collinear(e.top, pt, prev.top) {
    return
  }
  let ei = e.outrec.unwrap().idx
  let pi = prev.outrec.unwrap().idx
  if ei == pi {
    self.add_local_max_poly(prev, e, pt) |> ignore
  } else if ei < pi {
    self.join_outrec_paths(e, prev)
  } else {
    self.join_outrec_paths(prev, e)
  }
  prev.join_with = Right
  e.join_with = Left
}

///|
fn Clipper64::check_join_right(
  self : Clipper64,
  e : Active,
  pt : Point64,
  check_curr_x~ : Bool = false,
) -> Unit {
  guard e.next_in_ael is Some(next) else { return }
  if !is_hot_edge(e) ||
    !is_hot_edge(next) ||
    is_horizontal(e) ||
    is_horizontal(next) ||
    is_open(e) ||
    is_open(next) {
    return
  }
  if (pt.y < e.top.y + 2L || pt.y < next.top.y + 2L) &&
    (e.bot.y > pt.y || next.bot.y > pt.y) {
    return
  }
  if check_curr_x {
    if perpendic_dist_from_line_sqrd(pt, next.bot, next.top) > 0.35 {
      return
    }
  } else if e.curr_x != next.curr_x {
    return
  }
  if !is_collinear(e.top, pt, next.top) {
    return
  }
  let ei = e.outrec.unwrap().idx
  let ni = next.outrec.unwrap().idx
  if ei == ni {
    self.add_local_max_poly(e, next, pt) |> ignore
  } else if ei < ni {
    self.join_outrec_paths(e, next)
  } else {
    self.join_outrec_paths(next, e)
  }
  e.join_with = Right
  next.join_with = Left
}
