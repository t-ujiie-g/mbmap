///|
/// JTS's geomgraph `SegmentIntersector` (`bdy`: the boundary nodes of both
/// arguments, when intersecting one with the other).
priv struct SegmentIntersector {
  li : LineIntersector
  include_proper : Bool
  record_isolated : Bool
  mut has_proper : Bool
  mut has_proper_interior : Bool
  mut bdy : (Array[Node], Array[Node])?
}

///|
fn SegmentIntersector::new(
  li : LineIntersector,
  include_proper : Bool,
  record_isolated : Bool,
) -> SegmentIntersector {
  {
    li,
    include_proper,
    record_isolated,
    has_proper: false,
    has_proper_interior: false,
    bdy: None,
  }
}

///|
fn SegmentIntersector::is_trivial(
  self : SegmentIntersector,
  e0 : Edge,
  seg0 : Int32,
  e1 : Edge,
  seg1 : Int32,
) -> Bool {
  if physical_equal(e0, e1) && self.li.result == 1 {
    if (seg0 - seg1).abs() == 1 {
      return true
    }
    if e0.is_closed() {
      let max = e0.pts.length() - 1
      if (seg0 == 0 && seg1 == max) || (seg1 == 0 && seg0 == max) {
        return true
      }
    }
  }
  false
}

///|
fn SegmentIntersector::is_boundary_point(self : SegmentIntersector) -> Bool {
  guard self.bdy is Some((b0, b1)) else { return false }
  for n in b0 {
    if self.li.is_intersection(n.coord) {
      return true
    }
  }
  for n in b1 {
    if self.li.is_intersection(n.coord) {
      return true
    }
  }
  false
}

///|
fn SegmentIntersector::add_intersections(
  self : SegmentIntersector,
  e0 : Edge,
  seg0 : Int32,
  e1 : Edge,
  seg1 : Int32,
) -> Unit {
  if physical_equal(e0, e1) && seg0 == seg1 {
    return
  }
  let li = self.li
  li.compute(e0.pts[seg0], e0.pts[seg0 + 1], e1.pts[seg1], e1.pts[seg1 + 1])
  if !li.has_intersection() {
    return
  }
  if self.record_isolated {
    e0.isolated = false
    e1.isolated = false
  }
  if self.is_trivial(e0, seg0, e1, seg1) {
    return
  }
  if self.include_proper || !li.is_proper() {
    e0.add_intersections(li, seg0, 0)
    e1.add_intersections(li, seg1, 1)
  }
  if li.is_proper() {
    self.has_proper = true
    if !self.is_boundary_point() {
      self.has_proper_interior = true
    }
  }
}

///|
/// `MonotoneChainIndexer.getChainStartIndices`.
fn chain_starts(pts : Array[Coord]) -> Array[Int32] {
  let starts = [0]
  let mut start = 0
  let n = pts.length()
  while start < n - 1 {
    let quad = quadrant(pts[start], pts[start + 1])
    let mut last = start + 1
    while last < n && quadrant(pts[last - 1], pts[last]) == quad {
      last += 1
    }
    starts.push(last - 1)
    start = last - 1
  }
  starts
}

///|
/// `Quadrant.quadrant(p0, p1)` (identical points never reach it).
fn quadrant(p0 : Coord, p1 : Coord) -> Int32 {
  if p1.x >= p0.x {
    if p1.y >= p0.y {
      0
    } else {
      3
    }
  } else if p1.y >= p0.y {
    1
  } else {
    2
  }
}

///|
/// `Quadrant.quadrant(dx, dy)`: NE 0, NW 1, SW 2, SE 3.
fn quadrant_of(dx : Double, dy : Double) -> Int32 {
  if dx >= 0.0 {
    if dy >= 0.0 {
      0
    } else {
      3
    }
  } else if dy >= 0.0 {
    1
  } else {
    2
  }
}

///|
fn Edge::chains(self : Edge) -> Array[Int32] {
  match self.chains {
    Some(c) => c
    None => {
      let c = chain_starts(self.pts)
      self.chains = Some(c)
      c
    }
  }
}

///|
/// `MonotoneChainEdge.computeIntersectsForChain` over point ranges.
fn chain_intersections(
  e0 : Edge,
  start0 : Int32,
  end0 : Int32,
  e1 : Edge,
  start1 : Int32,
  end1 : Int32,
  si : SegmentIntersector,
) -> Unit {
  if end0 - start0 == 1 && end1 - start1 == 1 {
    si.add_intersections(e0, start0, e1, start1)
    return
  }
  if !seg_envs_meet(e0.pts[start0], e0.pts[end0], e1.pts[start1], e1.pts[end1]) {
    return
  }
  let mid0 = (start0 + end0) / 2
  let mid1 = (start1 + end1) / 2
  if start0 < mid0 {
    if start1 < mid1 {
      chain_intersections(e0, start0, mid0, e1, start1, mid1, si)
    }
    if mid1 < end1 {
      chain_intersections(e0, start0, mid0, e1, mid1, end1, si)
    }
  }
  if mid0 < end0 {
    if start1 < mid1 {
      chain_intersections(e0, mid0, end0, e1, start1, mid1, si)
    }
    if mid1 < end1 {
      chain_intersections(e0, mid0, end0, e1, mid1, end1, si)
    }
  }
}

///|
/// A `SweepLineEvent`: an insert carries its chain and the index of its
/// delete event; a delete points at its insert.
priv struct Event {
  label : Int32
  x : Double
  insert : Bool
  edge : Edge
  chain : Int32
  partner : Event?
  mut delete_index : Int32
}

///|
fn event_compare(a : Event, b : Event) -> Int32 {
  if a.x < b.x {
    -1
  } else if a.x > b.x {
    1
  } else {
    let ka = if a.insert { 1 } else { 2 }
    let kb = if b.insert { 1 } else { 2 }
    ka - kb
  }
}

///|
/// JTS's `SimpleMCSweepLineIntersector`. Labels: -1 never matches; events
/// of the same label are not intersected with each other.
priv struct Sweep {
  events : Array[Event]
}

///|
fn Sweep::new() -> Sweep {
  { events: [], }
}

///|
fn Sweep::add_edge(self : Sweep, e : Edge, label : Int32) -> Unit {
  let starts = e.chains()
  for i in 0..<(starts.length() - 1) {
    let x1 = e.pts[starts[i]].x
    let x2 = e.pts[starts[i + 1]].x
    let ins = {
      label,
      x: if x1 < x2 {
        x1
      } else {
        x2
      },
      insert: true,
      edge: e,
      chain: i,
      partner: None,
      delete_index: 0,
    }
    self.events.push(ins)
    self.events.push({
      label,
      x: if x1 > x2 {
        x1
      } else {
        x2
      },
      insert: false,
      edge: e,
      chain: i,
      partner: Some(ins),
      delete_index: 0,
    })
  }
}

///|
fn Sweep::run(self : Sweep, si : SegmentIntersector) -> Unit {
  let events = self.events
  @core.stable_sort(events, (a, b) => event_compare(a, b) < 0)
  for i, ev in events {
    if !ev.insert && ev.partner is Some(ins) {
      ins.delete_index = i
    }
  }
  for i, ev0 in events {
    if !ev0.insert {
      continue
    }
    let s0 = ev0.edge.chains()
    for k in i..<ev0.delete_index {
      let ev1 = events[k]
      if !ev1.insert || (ev0.label != -1 && ev0.label == ev1.label) {
        continue
      }
      let s1 = ev1.edge.chains()
      chain_intersections(
        ev0.edge,
        s0[ev0.chain],
        s0[ev0.chain + 1],
        ev1.edge,
        s1[ev1.chain],
        s1[ev1.chain + 1],
        si,
      )
    }
  }
}
