///|
/// Most points a reader takes from one input (AGENTS.md §8.2).
pub const MAX_POINTS : Int32 = 20_000_000

///|
/// Deepest nesting of geometry collections in WKT and WKB input.
pub const MAX_GEOMETRY_DEPTH : Int32 = 32

///|
pub(all) suberror ReadError {
  Invalid(format~ : String, pos~ : Int32, String)
} derive(Debug)

///|
/// A one-line description, e.g. `malformed CSV at 12: unterminated quoted field`.
pub fn ReadError::message(self : ReadError) -> String {
  match self {
    Invalid(format~, pos~, m) => "malformed \{format} at \{pos}: \{m}"
  }
}

///|
/// One geometry's members (collections flattened) held until it is known to be valid,
/// in `@geom.Table`'s offsets with a member per feature; empty rings, parts and members
/// are dropped as they end. `srid`: the SRID it was given (0 for none).
priv struct Shapes {
  mut srid : Int32
  kinds : Array[@geom.GeomKind]
  part_ends : Array[Int32]
  ring_ends : Array[Int32]
  point_ends : Array[Int32]
  coords : Array[Double]
}

///|
fn Shapes::new() -> Shapes {
  {
    srid: 0,
    kinds: [],
    part_ends: [],
    ring_ends: [],
    point_ends: [],
    coords: [],
  }
}

///|
fn Shapes::clear(self : Shapes) -> Unit {
  self.srid = 0
  self.kinds.clear()
  self.part_ends.clear()
  self.ring_ends.clear()
  self.point_ends.clear()
  self.coords.clear()
}

///|
fn Shapes::points(self : Shapes) -> Int32 {
  self.coords.length() / 2
}

///|
fn Shapes::point(self : Shapes, x : Double, y : Double) -> Unit {
  self.coords.push(x)
  self.coords.push(y)
}

///|
fn Shapes::end_ring(self : Shapes) -> Unit {
  if self.points() > @geom.start_of_last(self.point_ends) {
    self.point_ends.push(self.points())
  }
}

///|
fn Shapes::end_part(self : Shapes) -> Unit {
  if self.point_ends.length() > @geom.start_of_last(self.ring_ends) {
    self.ring_ends.push(self.point_ends.length())
  }
}

///|
/// Takes `srid` (as read, 0 for none) as the geometry's; false (and `fail`
/// called) if it is invalid or another one was given before.
fn Shapes::take_srid(
  self : Shapes,
  srid : Int32,
  fail : (String) -> Unit,
) -> Bool {
  if srid < 0 {
    fail("invalid SRID")
    false
  } else if srid != 0 && self.srid != 0 && srid != self.srid {
    fail("mixed SRIDs in one geometry")
    false
  } else {
    if srid != 0 {
      self.srid = srid
    }
    true
  }
}

///|
fn Shapes::end_member(self : Shapes, kind : @geom.GeomKind) -> Unit {
  if self.ring_ends.length() > @geom.start_of_last(self.part_ends) {
    self.part_ends.push(self.ring_ends.length())
    self.kinds.push(kind)
  }
}

///|
/// Adds a row per member to `out`, each with `props` and `id`, and its SRID to
/// `srids`; one row without geometry if there is no member (an EMPTY geometry or
/// no geometry at all).
fn Shapes::emit(
  self : Shapes,
  out : @geom.TableBuilder,
  props : Array[(String, @geom.Prop)],
  srids : Array[Int32]?,
  id~ : @geom.Prop? = None,
) -> Unit {
  let members = self.kinds.length()
  for m in 0..<(if members == 0 { 1 } else { members }) {
    let kind = if members == 0 {
      @geom.GeomKind::NoGeometry
    } else {
      for p in @geom.start_of(self.part_ends, m)..<self.part_ends[m] {
        for r in @geom.start_of(self.ring_ends, p)..<self.ring_ends[p] {
          for i in @geom.start_of(self.point_ends, r)..<self.point_ends[r] {
            out.point(self.coords[i * 2], self.coords[i * 2 + 1])
          }
          out.end_ring()
        }
        out.end_part()
      }
      self.kinds[m]
    }
    for p in props {
      out.prop(p.0, p.1)
    }
    out.end_feature(kind, id~)
    if srids is Some(s) {
      s.push(self.srid)
    }
  }
}
