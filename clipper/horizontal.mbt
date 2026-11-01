// Ports the horizontal-edge handling of ClipperBase in Clipper2 2.0.1
// src/clipper.engine.cpp (commit 642390d), Boost Software License 1.0,
// Copyright (c) Angus Johnson 2010-2026. See NOTICE.

///|
fn trim_horz(horz : Active, preserve_collinear : Bool) -> Unit {
  let mut was_trimmed = false
  let mut pt = next_vertex(horz).pt
  while pt.y == horz.top.y {
    if preserve_collinear && (pt.x < horz.top.x) != (horz.bot.x < horz.top.x) {
      break
    }
    horz.vertex_top = next_vertex(horz)
    horz.top = pt
    was_trimmed = true
    if is_maxima(horz) {
      break
    }
    pt = next_vertex(horz).pt
  }
  if was_trimmed {
    set_dx(horz)
  }
}

///|
fn set_horz_seg_heading_forward(
  hs : HorzSegment,
  op_p : OutPt,
  op_n : OutPt,
) -> Bool {
  if op_p.pt.x == op_n.pt.x {
    return false
  }
  if op_p.pt.x < op_n.pt.x {
    hs.left_op = Some(op_p)
    hs.right_op = Some(op_n)
    hs.left_to_right = true
  } else {
    hs.left_op = Some(op_n)
    hs.right_op = Some(op_p)
    hs.left_to_right = false
  }
  true
}

///|
fn update_horz_segment(hs : HorzSegment) -> Bool {
  let op = hs.left_op.unwrap()
  let outrec = get_real_outrec(Some(op.outrec)).unwrap()
  let outrec_has_edges = outrec.front_edge is Some(_)
  let curr_y = op.pt.y
  let mut op_p = op
  let mut op_n = op
  if outrec_has_edges {
    let op_a = outrec.pts.unwrap()
    let op_z = op_a.n()
    while !physical_equal(op_p, op_z) && op_p.p().pt.y == curr_y {
      op_p = op_p.p()
    }
    while !physical_equal(op_n, op_a) && op_n.n().pt.y == curr_y {
      op_n = op_n.n()
    }
  } else {
    while !physical_equal(op_p.p(), op_n) && op_p.p().pt.y == curr_y {
      op_p = op_p.p()
    }
    while !physical_equal(op_n.n(), op_p) && op_n.n().pt.y == curr_y {
      op_n = op_n.n()
    }
  }
  let result = set_horz_seg_heading_forward(hs, op_p, op_n) &&
    hs.left_op.unwrap().horz is None
  if result {
    hs.left_op.unwrap().horz = Some(hs)
  } else {
    hs.right_op = None
  }
  result
}

///|
fn Clipper64::convert_horz_segs_to_joins(self : Clipper64) -> Unit {
  let mut j = 0
  for hs in self.horz_seg_list {
    if update_horz_segment(hs) {
      j += 1
    }
  }
  if j < 2 {
    return
  }
  stable_sort(self.horz_seg_list, (hs1, hs2) => {
    match (hs1.right_op, hs2.right_op) {
      (Some(_), Some(_)) =>
        hs2.left_op.unwrap().pt.x > hs1.left_op.unwrap().pt.x
      (r1, _) => r1 is Some(_)
    }
  })
  let list = self.horz_seg_list
  for i in 0..<(j - 1) {
    let hs1 = list[i]
    for k in (i + 1)..<j {
      let hs2 = list[k]
      if hs2.left_op.unwrap().pt.x >= hs1.right_op.unwrap().pt.x ||
        hs2.left_to_right == hs1.left_to_right ||
        hs2.right_op.unwrap().pt.x <= hs1.left_op.unwrap().pt.x {
        continue
      }
      let curr_y = hs1.left_op.unwrap().pt.y
      if hs1.left_to_right {
        while hs1.left_op.unwrap().n().pt.y == curr_y &&
              hs1.left_op.unwrap().n().pt.x <= hs2.left_op.unwrap().pt.x {
          hs1.left_op = Some(hs1.left_op.unwrap().n())
        }
        while hs2.left_op.unwrap().p().pt.y == curr_y &&
              hs2.left_op.unwrap().p().pt.x <= hs1.left_op.unwrap().pt.x {
          hs2.left_op = Some(hs2.left_op.unwrap().p())
        }
        self.horz_join_list.push({
          op1: duplicate_op(hs1.left_op.unwrap(), true),
          op2: duplicate_op(hs2.left_op.unwrap(), false),
        })
      } else {
        while hs1.left_op.unwrap().p().pt.y == curr_y &&
              hs1.left_op.unwrap().p().pt.x <= hs2.left_op.unwrap().pt.x {
          hs1.left_op = Some(hs1.left_op.unwrap().p())
        }
        while hs2.left_op.unwrap().n().pt.y == curr_y &&
              hs2.left_op.unwrap().n().pt.x <= hs1.left_op.unwrap().pt.x {
          hs2.left_op = Some(hs2.left_op.unwrap().n())
        }
        self.horz_join_list.push({
          op1: duplicate_op(hs2.left_op.unwrap(), true),
          op2: duplicate_op(hs1.left_op.unwrap(), false),
        })
      }
    }
  }
}

///|
fn move_splits(from_or : OutRec, to_or : OutRec) -> Unit {
  let to = match to_or.splits {
    Some(s) => s
    None => {
      let s = []
      to_or.splits = Some(s)
      s
    }
  }
  let from = from_or.splits.unwrap()
  for o in from {
    if !physical_equal(to_or, o) {
      to.push(o)
    }
  }
  from.clear()
}

///|
fn Clipper64::process_horz_joins(self : Clipper64) -> Unit {
  for j in self.horz_join_list {
    let or1 = get_real_outrec(Some(j.op1.outrec)).unwrap()
    let mut or2 = get_real_outrec(Some(j.op2.outrec)).unwrap()
    let op1b = j.op1.n()
    let op2b = j.op2.p()
    j.op1.next = Some(j.op2)
    j.op2.prev = Some(j.op1)
    op1b.prev = Some(op2b)
    op2b.next = Some(op1b)
    if physical_equal(or1, or2) {
      or2 = self.new_outrec()
      or2.pts = Some(op1b)
      fix_outrec_pts(or2)
      if physical_equal(or1.pts.unwrap().outrec, or2) {
        or1.pts = Some(j.op1)
        j.op1.outrec = or1
      }
      if self.using_polytree {
        if path2_contains_path1_op(or1.pts.unwrap(), or2.pts.unwrap()) {
          let tmp = or1.pts
          or1.pts = or2.pts
          or2.pts = tmp
          fix_outrec_pts(or1)
          fix_outrec_pts(or2)
          or2.owner = Some(or1)
        } else if path2_contains_path1_op(or2.pts.unwrap(), or1.pts.unwrap()) {
          or2.owner = Some(or1)
        } else {
          or2.owner = or1.owner
        }
        match or1.splits {
          Some(s) => s.push(or2)
          None => or1.splits = Some([or2])
        }
      } else {
        or2.owner = Some(or1)
      }
    } else {
      or2.pts = None
      if self.using_polytree {
        set_owner(or2, or1)
        if or2.splits is Some(_) {
          move_splits(or2, or1)
        }
      } else {
        or2.owner = Some(or1)
      }
    }
  }
}

///|
fn get_last_op(hot_edge : Active) -> OutPt {
  let outrec = hot_edge.outrec.unwrap()
  let result = outrec.pts.unwrap()
  if same_active(outrec.front_edge, hot_edge) {
    result
  } else {
    result.n()
  }
}

///|
fn Clipper64::add_trial_horz_join(self : Clipper64, op : OutPt) -> Unit {
  if op.outrec.is_open {
    return
  }
  self.horz_seg_list.push({
    left_op: Some(op),
    right_op: None,
    left_to_right: true,
  })
}

///|
/// The horizontal's x range and whether it heads right.
fn reset_horz_direction(
  horz : Active,
  max_vertex : Vertex?,
) -> (Bool, Int64, Int64) {
  if horz.bot.x == horz.top.x {
    let mut e = horz.next_in_ael
    while e is Some(a) && !same_vertex(Some(a.vertex_top), max_vertex) {
      e = a.next_in_ael
    }
    (e is Some(_), horz.curr_x, horz.curr_x)
  } else if horz.curr_x < horz.top.x {
    (true, horz.curr_x, horz.top.x)
  } else {
    (false, horz.top.x, horz.curr_x)
  }
}

///|
fn same_vertex(a : Vertex?, b : Vertex?) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(x), Some(y)) => physical_equal(x, y)
    _ => false
  }
}

///|
/// Processes a horizontal edge and those consecutive to it in its bound,
/// intersecting the edges it passes over (Clipper2's `DoHorizontal`).
fn Clipper64::do_horizontal(self : Clipper64, horz : Active) -> Unit {
  let horz_is_open = is_open(horz)
  let y = horz.bot.y
  let vertex_max = if horz_is_open {
    get_curr_y_maxima_vertex_open(horz)
  } else {
    get_curr_y_maxima_vertex(horz)
  }
  let (ltr0, l0, r0) = reset_horz_direction(horz, vertex_max)
  let mut is_left_to_right = ltr0
  let mut horz_left = l0
  let mut horz_right = r0
  if is_hot_edge(horz) {
    let op = self.add_out_pt(horz, { x: horz.curr_x, y, })
    self.add_trial_horz_join(op)
  }
  while true {
    let mut e = if is_left_to_right {
      horz.next_in_ael
    } else {
      horz.prev_in_ael
    }
    while e is Some(ae) {
      if same_vertex(Some(ae.vertex_top), vertex_max) {
        if is_hot_edge(horz) && is_joined(ae) {
          self.split(ae, ae.top)
        }
        if is_hot_edge(horz) {
          while !same_vertex(Some(horz.vertex_top), vertex_max) {
            self.add_out_pt(horz, horz.top) |> ignore
            self.update_edge_into_ael(horz)
          }
          if is_left_to_right {
            self.add_local_max_poly(horz, ae, horz.top) |> ignore
          } else {
            self.add_local_max_poly(ae, horz, horz.top) |> ignore
          }
        }
        self.delete_from_ael(ae)
        self.delete_from_ael(horz)
        return
      }
      if !same_vertex(vertex_max, Some(horz.vertex_top)) || is_open_end(horz) {
        if (is_left_to_right && ae.curr_x > horz_right) ||
          (!is_left_to_right && ae.curr_x < horz_left) {
          break
        }
        if ae.curr_x == horz.top.x && !is_horizontal(ae) {
          let pt = next_vertex(horz).pt
          if is_left_to_right {
            if is_open(ae) && !is_same_poly_type(ae, horz) && !is_hot_edge(ae) {
              if top_x(ae, pt.y) > pt.x {
                break
              }
            } else if top_x(ae, pt.y) >= pt.x {
              break
            }
          } else if is_open(ae) &&
            !is_same_poly_type(ae, horz) &&
            !is_hot_edge(ae) {
            if top_x(ae, pt.y) < pt.x {
              break
            }
          } else if top_x(ae, pt.y) <= pt.x {
            break
          }
        }
      }
      let pt : Point64 = { x: ae.curr_x, y: horz.bot.y, }
      if is_left_to_right {
        self.intersect_edges(horz, ae, pt)
        self.swap_positions_in_ael(horz, ae)
        self.check_join_left(ae, pt)
        horz.curr_x = ae.curr_x
        e = horz.next_in_ael
      } else {
        self.intersect_edges(ae, horz, pt)
        self.swap_positions_in_ael(ae, horz)
        self.check_join_right(ae, pt)
        horz.curr_x = ae.curr_x
        e = horz.prev_in_ael
      }
      if horz.outrec is Some(_) {
        self.add_trial_horz_join(get_last_op(horz))
      }
    }
    if horz_is_open && is_open_end(horz) {
      if is_hot_edge(horz) {
        self.add_out_pt(horz, horz.top) |> ignore
        let o = horz.outrec.unwrap()
        if is_front(horz) {
          o.front_edge = None
        } else {
          o.back_edge = None
        }
        horz.outrec = None
      }
      self.delete_from_ael(horz)
      return
    } else if next_vertex(horz).pt.y != horz.top.y {
      break
    }
    if is_hot_edge(horz) {
      self.add_out_pt(horz, horz.top) |> ignore
    }
    self.update_edge_into_ael(horz)
    let (ltr, l, r) = reset_horz_direction(horz, vertex_max)
    is_left_to_right = ltr
    horz_left = l
    horz_right = r
  }
  if is_hot_edge(horz) {
    let op = self.add_out_pt(horz, horz.top)
    self.add_trial_horz_join(op)
  }
  self.update_edge_into_ael(horz)
}
