///|
/// JTS's `TopologyLocation`: one location for a line, on/left/right for an area.
priv struct TopoLoc {
  loc : FixedArray[Int32]
}

///|
fn TopoLoc::line(on : Int32) -> TopoLoc {
  { loc: FixedArray::make(1, on), }
}

///|
fn TopoLoc::area(on : Int32, left : Int32, right : Int32) -> TopoLoc {
  { loc: [on, left, right], }
}

///|
fn TopoLoc::copy(self : TopoLoc) -> TopoLoc {
  { loc: self.loc.copy(), }
}

///|
fn TopoLoc::get(self : TopoLoc, pos : Int32) -> Int32 {
  if pos < self.loc.length() {
    self.loc[pos]
  } else {
    NONE
  }
}

///|
fn TopoLoc::set(self : TopoLoc, pos : Int32, value : Int32) -> Unit {
  if pos < self.loc.length() {
    self.loc[pos] = value
  }
}

///|
fn TopoLoc::is_null(self : TopoLoc) -> Bool {
  for v in self.loc {
    if v != NONE {
      return false
    }
  }
  true
}

///|
fn TopoLoc::is_any_null(self : TopoLoc) -> Bool {
  for v in self.loc {
    if v == NONE {
      return true
    }
  }
  false
}

///|
fn TopoLoc::is_area(self : TopoLoc) -> Bool {
  self.loc.length() > 1
}

///|
/// JTS's `Label`: a topology location per argument geometry.
priv struct Label {
  elt : FixedArray[TopoLoc]
}

///|
fn Label::line(on : Int32) -> Label {
  { elt: [TopoLoc::line(on), TopoLoc::line(on)], }
}

///|
fn Label::line_of(geom : Int32, on : Int32) -> Label {
  let l = Label::line(NONE)
  l.elt[geom].set(ON, on)
  l
}

///|
fn Label::area(on : Int32, left : Int32, right : Int32) -> Label {
  { elt: [TopoLoc::area(on, left, right), TopoLoc::area(on, left, right)], }
}

///|
fn Label::area_of(
  geom : Int32,
  on : Int32,
  left : Int32,
  right : Int32,
) -> Label {
  let l = Label::area(NONE, NONE, NONE)
  l.elt[geom].set(ON, on)
  l.elt[geom].set(LEFT, left)
  l.elt[geom].set(RIGHT, right)
  l
}

///|
fn Label::copy(self : Label) -> Label {
  { elt: [self.elt[0].copy(), self.elt[1].copy()], }
}

///|
fn Label::geometry_count(self : Label) -> Int32 {
  (if self.elt[0].is_null() { 0 } else { 1 }) +
  (if self.elt[1].is_null() { 0 } else { 1 })
}

///|
fn Label::loc(self : Label, geom : Int32) -> Int32 {
  self.elt[geom].get(ON)
}

///|
fn Label::loc_at(self : Label, geom : Int32, pos : Int32) -> Int32 {
  self.elt[geom].get(pos)
}

///|
fn Label::set_loc(self : Label, geom : Int32, value : Int32) -> Unit {
  self.elt[geom].set(ON, value)
}

///|
fn Label::set_loc_at(
  self : Label,
  geom : Int32,
  pos : Int32,
  value : Int32,
) -> Unit {
  self.elt[geom].set(pos, value)
}

///|
fn Label::set_all(self : Label, geom : Int32, value : Int32) -> Unit {
  self.elt[geom].loc.fill(value)
}

///|
fn Label::set_all_if_null(self : Label, geom : Int32, value : Int32) -> Unit {
  let l = self.elt[geom].loc
  for i in 0..<l.length() {
    if l[i] == NONE {
      l[i] = value
    }
  }
}

///|
fn Label::is_null(self : Label, geom : Int32) -> Bool {
  self.elt[geom].is_null()
}

///|
fn Label::is_any_null(self : Label, geom : Int32) -> Bool {
  self.elt[geom].is_any_null()
}

///|
fn Label::is_area(self : Label) -> Bool {
  self.elt[0].is_area() || self.elt[1].is_area()
}

///|
fn Label::is_area_of(self : Label, geom : Int32) -> Bool {
  self.elt[geom].is_area()
}

///|
fn Label::flip(self : Label) -> Unit {
  for t in self.elt {
    if t.loc.length() > 1 {
      let tmp = t.loc[LEFT]
      t.loc[LEFT] = t.loc[RIGHT]
      t.loc[RIGHT] = tmp
    }
  }
}

///|
priv struct EdgeIntersection {
  coord : Coord
  seg : Int32
  dist : Double
}

///|
fn ei_compare(a : EdgeIntersection, b : EdgeIntersection) -> Int32 {
  if a.seg < b.seg {
    -1
  } else if a.seg > b.seg {
    1
  } else if a.dist < b.dist {
    -1
  } else if a.dist > b.dist {
    1
  } else {
    0
  }
}

///|
/// JTS's geomgraph `Edge` with its `EdgeIntersectionList` (`eis`) and its
/// monotone chains once computed.
priv struct Edge {
  pts : Array[Coord]
  label : Label
  eis : TreeMap[EdgeIntersection, EdgeIntersection]
  mut isolated : Bool
  mut chains : Array[Int32]?
}

///|
fn Edge::new(pts : Array[Coord], label : Label) -> Edge {
  { pts, label, eis: TreeMap::new(ei_compare), isolated: true, chains: None, }
}

///|
fn Edge::is_closed(self : Edge) -> Bool {
  self.pts[0].eq2d(self.pts[self.pts.length() - 1])
}

///|
fn Edge::add_ei(self : Edge, pt : Coord, seg : Int32, dist : Double) -> Unit {
  let ei = { coord: pt, seg, dist, }
  if self.eis.get(ei) is None {
    self.eis.put(ei, ei)
  }
}

///|
fn Edge::add_endpoints(self : Edge) -> Unit {
  let last = self.pts.length() - 1
  self.add_ei(self.pts[0], 0, 0.0)
  self.add_ei(self.pts[last], last, 0.0)
}

///|
/// `Edge.addIntersections`: the intersections found on input segment `geom`.
fn Edge::add_intersections(
  self : Edge,
  li : LineIntersector,
  seg : Int32,
  geom : Int32,
) -> Unit {
  for i in 0..<li.result {
    let pt = li.int_pt[i]
    let mut index = seg
    let mut dist = li.edge_distance(geom, i)
    let next = index + 1
    if next < self.pts.length() && pt.eq2d(self.pts[next]) {
      index = next
      dist = 0.0
    }
    self.add_ei(pt, index, dist)
  }
}

///|
/// `Edge.updateIM` over a label.
fn update_im_from_label(label : Label, im : Matrix) -> Unit {
  im.set_at_least_if_valid(label.loc_at(0, ON), label.loc_at(1, ON), 1)
  if label.is_area() {
    im.set_at_least_if_valid(label.loc_at(0, LEFT), label.loc_at(1, LEFT), 2)
    im.set_at_least_if_valid(label.loc_at(0, RIGHT), label.loc_at(1, RIGHT), 2)
  }
}

///|
/// JTS's `Node`; relate nodes carry their star of edge ends.
priv struct Node {
  coord : Coord
  label : Label
  star : Star?
}

///|
fn Node::set_label_boundary(self : Node, geom : Int32) -> Unit {
  let loc = self.label.loc(geom)
  self.label.set_loc(geom, if loc == BOUNDARY { INTERIOR } else { BOUNDARY })
}

///|
priv struct NodeMap {
  map : TreeMap[Coord, Node]
  with_stars : Bool
}

///|
fn NodeMap::new(with_stars : Bool) -> NodeMap {
  { map: TreeMap::new(Coord::compare), with_stars, }
}

///|
fn NodeMap::add_node(self : NodeMap, coord : Coord) -> Node {
  match self.map.get(coord) {
    Some(n) => n
    None => {
      let n = {
        coord,
        label: Label::line_of(0, NONE),
        star: if self.with_stars {
          Some(Star::new())
        } else {
          None
        },
      }
      self.map.put(coord, n)
      n
    }
  }
}

///|
fn NodeMap::find(self : NodeMap, coord : Coord) -> Node? {
  self.map.get(coord)
}

///|
/// JTS's `GeometryGraph` for argument `index`.
priv struct GeomGraph {
  index : Int32
  geom : Geometry
  edges : Array[Edge]
  nodes : NodeMap
  mut use_boundary_rule : Bool
  mut boundary_nodes : Array[Node]?
}

///|
/// `CoordinateArrays.removeRepeatedPoints`.
fn remove_repeated(pts : Array[Coord]) -> Array[Coord] {
  let out : Array[Coord] = Array(capacity=pts.length())
  for p in pts {
    if out.length() == 0 || !out[out.length() - 1].eq2d(p) {
      out.push(p)
    }
  }
  out
}

///|
fn GeomGraph::new(index : Int32, geom : Geometry) -> GeomGraph {
  let g = {
    index,
    geom,
    edges: [],
    nodes: NodeMap::new(false),
    use_boundary_rule: true,
    boundary_nodes: None,
  }
  match geom.kind {
    Empty => ()
    MultiPoly => {
      g.use_boundary_rule = false
      for p in geom.polys {
        g.add_polygon(p)
      }
    }
    Poly => g.add_polygon(geom.polys[0])
    Line | MultiLine =>
      for l in geom.lines {
        g.add_line(l)
      }
    Point | MultiPoint =>
      for p in geom.points {
        g.insert_point(p, INTERIOR)
      }
  }
  g
}

///|
fn GeomGraph::insert_point(self : GeomGraph, coord : Coord, on : Int32) -> Unit {
  self.nodes.add_node(coord).label.set_loc(self.index, on)
}

///|
fn GeomGraph::insert_boundary_point(self : GeomGraph, coord : Coord) -> Unit {
  let lbl = self.nodes.add_node(coord).label
  let count = if lbl.loc_at(self.index, ON) == BOUNDARY { 2 } else { 1 }
  lbl.set_loc(self.index, if count % 2 == 1 { BOUNDARY } else { INTERIOR })
}

///|
fn GeomGraph::add_polygon(
  self : GeomGraph,
  rings : Array[Array[Coord]],
) -> Unit {
  for i in 0..<rings.length() {
    if i == 0 {
      self.add_ring(rings[i], EXTERIOR, INTERIOR)
    } else {
      self.add_ring(rings[i], INTERIOR, EXTERIOR)
    }
  }
}

///|
fn GeomGraph::add_ring(
  self : GeomGraph,
  ring : Array[Coord],
  cw_left : Int32,
  cw_right : Int32,
) -> Unit {
  let coord = remove_repeated(ring)
  if coord.length() < 4 {
    return
  }
  let (left, right) = if is_ccw(coord) {
    (cw_right, cw_left)
  } else {
    (cw_left, cw_right)
  }
  self.edges.push(
    Edge::new(coord, Label::area_of(self.index, BOUNDARY, left, right)),
  )
  self.insert_point(coord[0], BOUNDARY)
}

///|
fn GeomGraph::add_line(self : GeomGraph, line : Array[Coord]) -> Unit {
  let coord = remove_repeated(line)
  if coord.length() < 2 {
    return
  }
  self.edges.push(Edge::new(coord, Label::line_of(self.index, INTERIOR)))
  self.insert_boundary_point(coord[0])
  self.insert_boundary_point(coord[coord.length() - 1])
}

///|
fn GeomGraph::boundary_nodes(self : GeomGraph) -> Array[Node] {
  match self.boundary_nodes {
    Some(b) => b
    None => {
      let b = self.nodes.map
        .values()
        .filter(n => n.label.loc(self.index) == BOUNDARY)
      self.boundary_nodes = Some(b)
      b
    }
  }
}

///|
/// `computeSelfNodes(li, false)`: rings of areas are not tested against
/// themselves.
fn GeomGraph::compute_self_nodes(
  self : GeomGraph,
  li : LineIntersector,
) -> Unit {
  let si = SegmentIntersector::new(li, true, false)
  let rings = self.geom.kind is (Poly | MultiPoly)
  let sweep = Sweep::new()
  for i, e in self.edges {
    sweep.add_edge(e, if rings { i } else { -1 })
  }
  sweep.run(si)
  for e in self.edges {
    let loc = e.label.loc(self.index)
    for ei in e.eis.values() {
      self.add_self_intersection_node(ei.coord, loc)
    }
  }
}

///|
fn GeomGraph::add_self_intersection_node(
  self : GeomGraph,
  coord : Coord,
  loc : Int32,
) -> Unit {
  if self.nodes.find(coord) is Some(n) && n.label.loc(self.index) == BOUNDARY {
    return
  }
  if loc == BOUNDARY && self.use_boundary_rule {
    self.insert_boundary_point(coord)
  } else {
    self.insert_point(coord, loc)
  }
}

///|
fn GeomGraph::compute_edge_intersections(
  self : GeomGraph,
  other : GeomGraph,
  li : LineIntersector,
) -> SegmentIntersector {
  let si = SegmentIntersector::new(li, false, true)
  si.bdy = Some((self.boundary_nodes(), other.boundary_nodes()))
  let sweep = Sweep::new()
  for e in self.edges {
    sweep.add_edge(e, 0)
  }
  for e in other.edges {
    sweep.add_edge(e, 1)
  }
  sweep.run(si)
  si
}
