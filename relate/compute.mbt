///|
/// Set where JTS would throw (an assertion or a topology exception), which
/// only invalid input reaches; the computation then goes on as best it can.
priv struct Status {
  mut failed : Bool
}

///|
/// JTS's geomgraph `EdgeEnd`.
priv struct EdgeEnd {
  p0 : Coord
  p1 : Coord
  dx : Double
  dy : Double
  quadrant : Int32
  label : Label
}

///|
/// None where JTS's `Quadrant.quadrant` throws on identical points.
fn EdgeEnd::new(p0 : Coord, p1 : Coord, label : Label) -> EdgeEnd? {
  let dx = p1.x - p0.x
  let dy = p1.y - p0.y
  if dx == 0.0 && dy == 0.0 {
    return None
  }
  Some({ p0, p1, dx, dy, quadrant: quadrant_of(dx, dy), label, })
}

///|
/// `EdgeEnd.compareDirection`.
fn ee_compare(a : EdgeEnd, e : EdgeEnd) -> Int32 {
  if a.dx == e.dx && a.dy == e.dy {
    0
  } else if a.quadrant > e.quadrant {
    1
  } else if a.quadrant < e.quadrant {
    -1
  } else {
    orientation_index(e.p0, e.p1, a.p1)
  }
}

///|
/// JTS's `EdgeEndBundle`: the edge ends of a node leaving in one direction.
priv struct Bundle {
  ee : EdgeEnd
  mut label : Label
  ends : Array[EdgeEnd]
}

///|
fn Bundle::compute_label(self : Bundle) -> Unit {
  let is_area = self.ends.iter().any(e => e.label.is_area())
  self.label = if is_area {
    Label::area(NONE, NONE, NONE)
  } else {
    Label::line(NONE)
  }
  for i in 0..<2 {
    let mut boundaries = 0
    let mut interior = false
    for e in self.ends {
      let loc = e.label.loc(i)
      if loc == BOUNDARY {
        boundaries += 1
      }
      if loc == INTERIOR {
        interior = true
      }
    }
    let mut loc = if interior { INTERIOR } else { NONE }
    if boundaries > 0 {
      loc = if boundaries % 2 == 1 { BOUNDARY } else { INTERIOR }
    }
    self.label.set_loc(i, loc)
    if is_area {
      self.compute_label_side(i, LEFT)
      self.compute_label_side(i, RIGHT)
    }
  }
}

///|
fn Bundle::compute_label_side(
  self : Bundle,
  geom : Int32,
  side : Int32,
) -> Unit {
  for e in self.ends {
    if e.label.is_area() {
      let loc = e.label.loc_at(geom, side)
      if loc == INTERIOR {
        self.label.set_loc_at(geom, side, INTERIOR)
        return
      } else if loc == EXTERIOR {
        self.label.set_loc_at(geom, side, EXTERIOR)
      }
    }
  }
}

///|
/// JTS's `EdgeEndBundleStar`, with the area location cache of `EdgeEndStar`.
priv struct Star {
  map : TreeMap[EdgeEnd, Bundle]
  pt_loc : FixedArray[Int32]
}

///|
fn Star::new() -> Star {
  { map: TreeMap::new(ee_compare), pt_loc: FixedArray::make(2, NONE), }
}

///|
fn Star::insert(self : Star, e : EdgeEnd) -> Unit {
  match self.map.get(e) {
    Some(b) => b.ends.push(e)
    None => self.map.put(e, { ee: e, label: e.label.copy(), ends: [e], })
  }
}

///|
fn Star::propagate_side_labels(
  bundles : Array[Bundle],
  geom : Int32,
  status : Status,
) -> Unit {
  let mut start = NONE
  for b in bundles {
    let label = b.label
    if label.is_area_of(geom) && label.loc_at(geom, LEFT) != NONE {
      start = label.loc_at(geom, LEFT)
    }
  }
  if start == NONE {
    return
  }
  let mut curr = start
  for b in bundles {
    let label = b.label
    if label.loc_at(geom, ON) == NONE {
      label.set_loc_at(geom, ON, curr)
    }
    if label.is_area_of(geom) {
      let left = label.loc_at(geom, LEFT)
      let right = label.loc_at(geom, RIGHT)
      if right != NONE {
        if right != curr || left == NONE {
          status.failed = true
          return
        }
        curr = left
      } else {
        if left != NONE {
          status.failed = true
          return
        }
        label.set_loc_at(geom, RIGHT, curr)
        label.set_loc_at(geom, LEFT, curr)
      }
    }
  }
}

///|
/// `EdgeEndStar.computeLabelling`.
fn Star::compute_labelling(
  self : Star,
  args : FixedArray[GeomGraph],
  status : Status,
) -> Unit {
  let bundles = self.map.values()
  for b in bundles {
    b.compute_label()
  }
  Star::propagate_side_labels(bundles, 0, status)
  Star::propagate_side_labels(bundles, 1, status)
  let collapsed = FixedArray::make(2, false)
  for b in bundles {
    for g in 0..<2 {
      if !b.label.is_area_of(g) && b.label.loc(g) == BOUNDARY {
        collapsed[g] = true
      }
    }
  }
  for b in bundles {
    for g in 0..<2 {
      if b.label.is_any_null(g) {
        let loc = if collapsed[g] {
          EXTERIOR
        } else {
          if self.pt_loc[g] == NONE {
            self.pt_loc[g] = locate_in_area(b.ee.p0, args[g].geom)
          }
          self.pt_loc[g]
        }
        b.label.set_all_if_null(g, loc)
      }
    }
  }
}

///|
/// `EdgeEndBuilder.computeEdgeEnds` for one edge.
fn edge_ends(edge : Edge, out : Array[EdgeEnd], status : Status) -> Unit {
  edge.add_endpoints()
  let eis = edge.eis.values()
  let n = edge.pts.length()
  let push = fn(p1 : Coord?, curr : EdgeIntersection, flip : Bool) {
    guard p1 is Some(p1) else {
      status.failed = true
      return
    }
    let label = edge.label.copy()
    if flip {
      label.flip()
    }
    match EdgeEnd::new(curr.coord, p1, label) {
      Some(e) => out.push(e)
      None => status.failed = true
    }
  }
  for k in 0..<eis.length() {
    let curr = eis[k]
    let mut i_prev = curr.seg
    if !(curr.dist == 0.0 && i_prev == 0) {
      if curr.dist == 0.0 {
        i_prev -= 1
      }
      let mut p_prev = if i_prev >= 0 && i_prev < n {
        Some(edge.pts[i_prev])
      } else {
        None
      }
      if k > 0 && eis[k - 1].seg >= i_prev {
        p_prev = Some(eis[k - 1].coord)
      }
      push(p_prev, curr, true)
    }
    let i_next = curr.seg + 1
    let has_next = k + 1 < eis.length()
    if !(i_next >= n && !has_next) {
      let mut p_next = if i_next >= 0 && i_next < n {
        Some(edge.pts[i_next])
      } else {
        None
      }
      if has_next && eis[k + 1].seg == curr.seg {
        p_next = Some(eis[k + 1].coord)
      }
      push(p_next, curr, false)
    }
  }
}

///|
/// JTS's `RelateComputer.computeIM`.
fn compute_im(g0 : Geometry, g1 : Geometry, status : Status) -> Matrix {
  let im = Matrix::new()
  im.set(EXTERIOR, EXTERIOR, 2)
  if !g0.env().intersects(g1.env()) {
    if g0.kind != Empty {
      im.set(INTERIOR, EXTERIOR, g0.dimension())
      im.set(BOUNDARY, EXTERIOR, g0.boundary_dimension())
    }
    if g1.kind != Empty {
      im.set(EXTERIOR, INTERIOR, g1.dimension())
      im.set(EXTERIOR, BOUNDARY, g1.boundary_dimension())
    }
    return im
  }
  let args : FixedArray[GeomGraph] = [
    GeomGraph::new(0, g0),
    GeomGraph::new(1, g1),
  ]
  let li = LineIntersector::new()
  args[0].compute_self_nodes(li)
  args[1].compute_self_nodes(li)
  let si = args[0].compute_edge_intersections(args[1], li)
  let nodes = NodeMap::new(true)
  for a in 0..<2 {
    for e in args[a].edges {
      let loc = e.label.loc(a)
      for ei in e.eis.values() {
        let n = nodes.add_node(ei.coord)
        if loc == BOUNDARY {
          n.set_label_boundary(a)
        } else if n.label.is_null(a) {
          n.label.set_loc(a, INTERIOR)
        }
      }
    }
  }
  for a in 0..<2 {
    for gn in args[a].nodes.map.values() {
      nodes.add_node(gn.coord).label.set_loc(a, gn.label.loc(a))
    }
  }
  for n in nodes.map.values() {
    let count = n.label.geometry_count()
    if count == 0 {
      status.failed = true
    } else if count == 1 {
      let target = if n.label.is_null(0) { 0 } else { 1 }
      n.label.set_all(target, locate(n.coord, args[target].geom))
    }
  }
  proper_intersection_im(si, im, g0.dimension(), g1.dimension())
  for a in 0..<2 {
    let ends = []
    for e in args[a].edges {
      edge_ends(e, ends, status)
    }
    for e in ends {
      match nodes.add_node(e.p0).star {
        Some(star) => star.insert(e)
        None => ()
      }
    }
  }
  let all_nodes = nodes.map.values()
  for n in all_nodes {
    if n.star is Some(star) {
      star.compute_labelling(args, status)
    }
  }
  let isolated = []
  for pair in [(0, 1), (1, 0)] {
    let (src, target) = pair
    let tg = args[target].geom
    for e in args[src].edges {
      if e.isolated {
        let loc = if tg.dimension() > 0 {
          locate(e.pts[0], tg)
        } else {
          EXTERIOR
        }
        e.label.set_all(target, loc)
        isolated.push(e)
      }
    }
  }
  for e in isolated {
    if e.label.geometry_count() < 2 {
      status.failed = true
    } else {
      update_im_from_label(e.label, im)
    }
  }
  for n in all_nodes {
    if n.label.geometry_count() < 2 {
      status.failed = true
    } else {
      im.set_at_least_if_valid(n.label.loc(0), n.label.loc(1), 0)
    }
    if n.star is Some(star) {
      for b in star.map.values() {
        update_im_from_label(b.label, im)
      }
    }
  }
  im
}

///|
/// `RelateComputer.computeProperIntersectionIM`.
fn proper_intersection_im(
  si : SegmentIntersector,
  im : Matrix,
  dim_a : Int32,
  dim_b : Int32,
) -> Unit {
  let proper = si.has_proper
  let interior = si.has_proper_interior
  if dim_a == 2 && dim_b == 2 {
    if proper {
      im.set_at_least_pattern("212101212")
    }
  } else if dim_a == 2 && dim_b == 1 {
    if proper {
      im.set_at_least_pattern("FFF0FFFF2")
    }
    if interior {
      im.set_at_least_pattern("1FFFFF1FF")
    }
  } else if dim_a == 1 && dim_b == 2 {
    if proper {
      im.set_at_least_pattern("F0FFFFFF2")
    }
    if interior {
      im.set_at_least_pattern("1F1FFFFFF")
    }
  } else if dim_a == 1 && dim_b == 1 {
    if interior {
      im.set_at_least_pattern("0FFFFFFFF")
    }
  }
}
