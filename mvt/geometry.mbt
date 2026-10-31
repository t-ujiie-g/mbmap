///|
/// Reusable decode buffer: `coords` holds x, y pairs in tile units and
/// `ring_ends[i]` is the point index one past ring `i`. After a failed decode
/// the contents are partial and `error` says why.
pub struct Geometry {
  coords : Array[Int32]
  ring_ends : Array[Int32]
  priv mut error : MvtError?
}

///|
pub fn Geometry::new() -> Geometry {
  { coords: [], ring_ends: [], error: None, }
}

///|
pub fn Geometry::num_points(self : Geometry) -> Int32 {
  self.coords.length() / 2
}

///|
pub fn Geometry::num_rings(self : Geometry) -> Int32 {
  self.ring_ends.length()
}

///|
/// First point index of ring `i`; the ring ends at `ring_ends[i]`.
pub fn Geometry::ring_start(self : Geometry, i : Int32) -> Int32 {
  if i == 0 {
    0
  } else {
    self.ring_ends[i - 1]
  }
}

///|
/// Why the last `decode_geometry` into this buffer failed, if it did.
pub fn Geometry::error(self : Geometry) -> MvtError? {
  self.error
}

///|
const CMD_MOVE_TO = 1

///|
const CMD_LINE_TO = 2

///|
const CMD_CLOSE_PATH = 7

///|
/// Decodes feature `i`'s command stream into `out`, replacing its contents,
/// and returns whether it succeeded (see `Geometry::error`). Each MoveTo starts
/// a ring and ClosePath repeats the ring's first point, matching
/// `@mapbox/vector-tile`'s `loadGeometry`.
pub fn Layer::decode_geometry(self : Layer, i : Int32, out : Geometry) -> Bool {
  out.coords.clear()
  out.ring_ends.clear()
  out.error = None
  let r = self.cursor
  r.reset(self.geoms[i * 2], self.geoms[i * 2 + 1])
  let mut x = 0
  let mut y = 0
  let mut ring_start = -1
  while !r.at_end() {
    let pos = r.pos()
    let header = r.read_varint32()
    let cmd = header & 7
    let count = (header.reinterpret_as_uint() >> 3).reinterpret_as_int()
    if cmd == CMD_MOVE_TO || cmd == CMD_LINE_TO {
      // Every parameter takes at least one byte, which bounds `count`.
      if count > r.remaining() / 2 || (cmd == CMD_LINE_TO && ring_start < 0) {
        out.error = Some(InvalidCommand(pos~, header))
        return false
      }
      for _ in 0..<count {
        x += r.read_svarint32()
        y += r.read_svarint32()
        if cmd == CMD_MOVE_TO {
          if ring_start >= 0 {
            out.ring_ends.push(out.coords.length() / 2)
          }
          ring_start = out.coords.length()
        }
        out.coords.push(x)
        out.coords.push(y)
      }
    } else if cmd == CMD_CLOSE_PATH && count <= 1 {
      if count == 1 && ring_start >= 0 {
        out.coords.push(out.coords[ring_start])
        out.coords.push(out.coords[ring_start + 1])
      }
    } else {
      out.error = Some(InvalidCommand(pos~, header))
      return false
    }
  }
  if r.error() is Some(e) {
    out.error = Some(Malformed(e))
    return false
  }
  if ring_start >= 0 {
    out.ring_ends.push(out.coords.length() / 2)
  }
  true
}

///|
/// Allocating convenience: one array of `(x, y)` per ring of feature `i`.
pub fn Layer::load_geometry(
  self : Layer,
  i : Int32,
) -> Array[Array[(Int32, Int32)]] raise MvtError {
  let g = Geometry::new()
  if !self.decode_geometry(i, g) {
    raise g.error.unwrap()
  }
  Array::makei(g.num_rings(), r => {
    let start = g.ring_start(r)
    Array::makei(g.ring_ends[r] - start, j => {
      (g.coords[(start + j) * 2], g.coords[(start + j) * 2 + 1])
    })
  })
}
