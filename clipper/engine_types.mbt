// Port of Clipper2 2.0.1 (clipper.engine.h and .cpp, commit 642390d), Boost
// Software License 1.0, Copyright (c) Angus Johnson 2010-2026; see NOTICE.
// Up and down assume a y-down frame, as in Clipper2.

///|
priv enum PathType {
  Subject
  Clip
} derive(Eq)

///|
priv enum JoinWith {
  NoJoin
  Left
  Right
} derive(Eq)

///|
const VERTEX_OPEN_START : Int32 = 1

///|
const VERTEX_OPEN_END : Int32 = 2

///|
const VERTEX_LOCAL_MAX : Int32 = 4

///|
const VERTEX_LOCAL_MIN : Int32 = 8

///|
priv struct Vertex {
  pt : Point64
  mut next : Vertex?
  mut prev : Vertex?
  mut flags : Int32
}

///|
fn Vertex::n(self : Vertex) -> Vertex {
  self.next.unwrap()
}

///|
fn Vertex::p(self : Vertex) -> Vertex {
  self.prev.unwrap()
}

///|
priv struct OutPt {
  pt : Point64
  mut next : OutPt?
  mut prev : OutPt?
  mut outrec : OutRec
  mut horz : HorzSegment?
}

///|
fn OutPt::new(pt : Point64, outrec : OutRec) -> OutPt {
  let op = { pt, next: None, prev: None, outrec, horz: None, }
  op.next = Some(op)
  op.prev = Some(op)
  op
}

///|
fn OutPt::n(self : OutPt) -> OutPt {
  self.next.unwrap()
}

///|
fn OutPt::p(self : OutPt) -> OutPt {
  self.prev.unwrap()
}

///|
/// A path of the solution being built; edges of the AEL that contribute to it
/// point at it.
priv struct OutRec {
  idx : Int32
  mut owner : OutRec?
  mut front_edge : Active?
  mut back_edge : Active?
  mut pts : OutPt?
  mut polypath : PolyPath64?
  mut splits : Array[OutRec]?
  mut recursive_split : OutRec?
  mut bounds : Rect64
  path : Array[Point64]
  mut is_open : Bool
}

///|
/// An edge in the active edge list (AEL) of the sweep, also chained in the
/// sorted edge list (SEL).
priv struct Active {
  mut bot : Point64
  mut top : Point64
  mut curr_x : Int64
  mut dx : Double
  wind_dx : Int32
  mut wind_cnt : Int32
  mut wind_cnt2 : Int32
  mut outrec : OutRec?
  mut prev_in_ael : Active?
  mut next_in_ael : Active?
  mut prev_in_sel : Active?
  mut next_in_sel : Active?
  mut jump : Active?
  mut vertex_top : Vertex
  local_min : LocalMinima
  mut is_left_bound : Bool
  mut join_with : JoinWith
}

///|
priv struct LocalMinima {
  vertex : Vertex
  polytype : PathType
  is_open : Bool
}

///|
priv struct IntersectNode {
  pt : Point64
  edge1 : Active
  edge2 : Active
}

///|
priv struct HorzSegment {
  mut left_op : OutPt?
  mut right_op : OutPt?
  mut left_to_right : Bool
}

///|
priv struct HorzJoin {
  op1 : OutPt
  op2 : OutPt
}

///|
/// An axis-aligned rectangle (`Rect64`); `invalid_rect()` has left > right.
priv struct Rect64 {
  left : Int64
  top : Int64
  right : Int64
  bottom : Int64
}

///|
fn Rect64::contains_rect(self : Rect64, r : Rect64) -> Bool {
  r.left >= self.left &&
  r.right <= self.right &&
  r.top >= self.top &&
  r.bottom <= self.bottom
}

///|
/// The bounding rectangle of `path` (`GetBounds`).
fn bounds_of(path : Array[Point64]) -> Rect64 {
  let mut l = @int64.MAX_VALUE
  let mut t = @int64.MAX_VALUE
  let mut r = @int64.MIN_VALUE
  let mut b = @int64.MIN_VALUE
  for p in path {
    if p.x < l {
      l = p.x
    }
    if p.x > r {
      r = p.x
    }
    if p.y < t {
      t = p.y
    }
    if p.y > b {
      b = p.y
    }
  }
  { left: l, top: t, right: r, bottom: b, }
}

///|
/// A node of a solution's tree of nested polygons (`PolyPath64`): the root has
/// no polygon; children of an outer polygon are its holes, and so on.
pub struct PolyPath64 {
  priv parent : PolyPath64?
  polygon : Array[Point64]
  children : Array[PolyPath64]
}

///|
pub fn PolyPath64::new() -> PolyPath64 {
  { parent: None, polygon: [], children: [], }
}

///|
fn PolyPath64::add_child(
  self : PolyPath64,
  path : Array[Point64],
) -> PolyPath64 {
  let child = { parent: Some(self), polygon: path, children: [], }
  self.children.push(child)
  child
}

///|
/// The node's depth below the root (0 for the root).
pub fn PolyPath64::level(self : PolyPath64) -> Int32 {
  let mut n = 0
  let mut p = self.parent
  while p is Some(q) {
    n += 1
    p = q.parent
  }
  n
}

///|
/// Whether the node's polygon is a hole (an even level other than 0).
pub fn PolyPath64::is_hole(self : PolyPath64) -> Bool {
  let l = self.level()
  l != 0 && l % 2 == 0
}
