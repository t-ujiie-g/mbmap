// Ports the solution building of Clipper2 2.0.1 src/clipper.engine.cpp and the
// boolean helpers of include/clipper2/clipper.h (commit 642390d), Boost
// Software License 1.0, Copyright (c) Angus Johnson 2010-2026. See NOTICE.

///|
fn build_path64(
  op : OutPt?,
  reverse : Bool,
  is_open_path : Bool,
  path : Array[Point64],
) -> Bool {
  guard op is Some(op) else { return false }
  if physical_equal(op.n(), op) ||
    (!is_open_path && physical_equal(op.n(), op.p())) {
    return false
  }
  path.clear()
  let mut op = op
  let mut last_pt = op.pt
  let mut op2 = op
  if reverse {
    last_pt = op.pt
    op2 = op.p()
  } else {
    op = op.n()
    last_pt = op.pt
    op2 = op.n()
  }
  path.push(last_pt)
  while !physical_equal(op2, op) {
    if op2.pt != last_pt {
      last_pt = op2.pt
      path.push(last_pt)
    }
    op2 = if reverse { op2.p() } else { op2.n() }
  }
  !(!is_open_path && path.length() == 3 && is_very_small_triangle(op2))
}

///|
fn rect_is_empty(r : Rect64) -> Bool {
  r.bottom <= r.top || r.right <= r.left
}

///|
fn Clipper64::check_bounds(self : Clipper64, outrec : OutRec) -> Bool {
  if outrec.pts is None {
    return false
  }
  if !rect_is_empty(outrec.bounds) {
    return true
  }
  self.clean_collinear(Some(outrec))
  if outrec.pts is None ||
    !build_path64(outrec.pts, self.reverse_solution, false, outrec.path) {
    return false
  }
  outrec.bounds = bounds_of(outrec.path)
  true
}

///|
fn Clipper64::check_split_owner(
  self : Clipper64,
  outrec : OutRec,
  splits : Array[OutRec],
) -> Bool {
  let mut idx = 0
  while idx < splits.length() {
    let s = splits[idx]
    idx += 1
    if s.pts is None &&
      s.splits is Some(ss) &&
      self.check_split_owner(outrec, ss) {
      return true
    }
    guard get_real_outrec(Some(s)) is Some(split) else { continue }
    if physical_equal(split, outrec) ||
      same_outrec(split.recursive_split, Some(outrec)) {
      continue
    }
    split.recursive_split = Some(outrec)
    if split.splits is Some(ss) && self.check_split_owner(outrec, ss) {
      return true
    }
    if !self.check_bounds(split) ||
      !split.bounds.contains_rect(outrec.bounds) ||
      !path2_contains_path1_op(outrec.pts.unwrap(), split.pts.unwrap()) {
      continue
    }
    if !is_valid_owner(outrec, Some(split)) {
      split.owner = outrec.owner
    }
    outrec.owner = Some(split)
    return true
  }
  false
}

///|
fn Clipper64::recursive_check_owners(
  self : Clipper64,
  outrec : OutRec,
  polypath : PolyPath64,
) -> Unit {
  if outrec.polypath is Some(_) || rect_is_empty(outrec.bounds) {
    return
  }
  while outrec.owner is Some(owner) {
    if owner.splits is Some(ss) && self.check_split_owner(outrec, ss) {
      break
    }
    if owner.pts is Some(_) &&
      self.check_bounds(owner) &&
      owner.bounds.contains_rect(outrec.bounds) &&
      path2_contains_path1_op(outrec.pts.unwrap(), owner.pts.unwrap()) {
      break
    }
    outrec.owner = owner.owner
  }
  match outrec.owner {
    Some(owner) => {
      if owner.polypath is None {
        self.recursive_check_owners(owner, polypath)
      }
      outrec.polypath = Some(owner.polypath.unwrap().add_child(outrec.path))
    }
    None => outrec.polypath = Some(polypath.add_child(outrec.path))
  }
}

///|
fn Clipper64::build_paths64(
  self : Clipper64,
  closed : Array[Array[Point64]],
  open : Array[Array[Point64]],
) -> Unit {
  closed.clear()
  open.clear()
  // CleanCollinear may add outrecs while this runs.
  let mut i = 0
  while i < self.outrec_list.length() {
    let outrec = self.outrec_list[i]
    i += 1
    if outrec.pts is None {
      continue
    }
    let path = []
    if outrec.is_open {
      if build_path64(outrec.pts, self.reverse_solution, true, path) {
        open.push(path)
      }
    } else {
      self.clean_collinear(Some(outrec))
      if build_path64(outrec.pts, self.reverse_solution, false, path) {
        closed.push(path)
      }
    }
  }
}

///|
fn Clipper64::build_tree64(
  self : Clipper64,
  polytree : PolyPath64,
  open : Array[Array[Point64]],
) -> Unit {
  polytree.children.clear()
  open.clear()
  let mut i = 0
  while i < self.outrec_list.length() {
    let outrec = self.outrec_list[i]
    i += 1
    if outrec.pts is None {
      continue
    }
    if outrec.is_open {
      let path = []
      if build_path64(outrec.pts, self.reverse_solution, true, path) {
        open.push(path)
      }
      continue
    }
    if self.check_bounds(outrec) {
      self.recursive_check_owners(outrec, polytree)
    }
  }
}

///|
/// Runs `clip_type` with `fill_rule` over the added paths: closed solution
/// paths (outer ones counter-clockwise in a y-up frame unless reversed) and
/// open ones. None if the operation failed.
pub fn Clipper64::execute(
  self : Clipper64,
  clip_type : ClipType,
  fill_rule : FillRule,
) -> (Array[Array[Point64]], Array[Array[Point64]])? {
  let closed = []
  let open = []
  if self.execute_internal(clip_type, fill_rule, false) {
    self.build_paths64(closed, open)
  }
  self.clean_up()
  if self.succeeded {
    Some((closed, open))
  } else {
    None
  }
}

///|
/// Like `execute`, with the closed solution as a tree of nested polygons.
pub fn Clipper64::execute_tree(
  self : Clipper64,
  clip_type : ClipType,
  fill_rule : FillRule,
) -> (PolyPath64, Array[Array[Point64]])? {
  let tree = PolyPath64::new()
  let open = []
  if self.execute_internal(clip_type, fill_rule, true) {
    self.build_tree64(tree, open)
  }
  self.clean_up()
  if self.succeeded {
    Some((tree, open))
  } else {
    None
  }
}

///|
/// `subjects` combined with `clips` by `clip_type` (Clipper2's `BooleanOp`):
/// the closed solution, or empty if the operation failed.
pub fn boolean_op(
  clip_type : ClipType,
  fill_rule : FillRule,
  subjects : Array[Array[Point64]],
  clips : Array[Array[Point64]],
) -> Array[Array[Point64]] {
  let c = Clipper64::new()
  c.add_subject(subjects)
  c.add_clip(clips)
  match c.execute(clip_type, fill_rule) {
    Some((closed, _)) => closed
    None => []
  }
}

///|
/// The intersection of `subjects` and `clips`.
pub fn intersect(
  subjects : Array[Array[Point64]],
  clips : Array[Array[Point64]],
  fill_rule : FillRule,
) -> Array[Array[Point64]] {
  boolean_op(Intersection, fill_rule, subjects, clips)
}

///|
/// The union of `subjects` and `clips` (pass no clips to merge `subjects`).
pub fn union(
  subjects : Array[Array[Point64]],
  clips : Array[Array[Point64]],
  fill_rule : FillRule,
) -> Array[Array[Point64]] {
  boolean_op(Union, fill_rule, subjects, clips)
}

///|
/// `subjects` without `clips`.
pub fn difference(
  subjects : Array[Array[Point64]],
  clips : Array[Array[Point64]],
  fill_rule : FillRule,
) -> Array[Array[Point64]] {
  boolean_op(Difference, fill_rule, subjects, clips)
}

///|
/// What lies in exactly one of `subjects` and `clips`.
pub fn xor(
  subjects : Array[Array[Point64]],
  clips : Array[Array[Point64]],
  fill_rule : FillRule,
) -> Array[Array[Point64]] {
  boolean_op(Xor, fill_rule, subjects, clips)
}
