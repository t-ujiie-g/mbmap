// Ports geojson-path-finder 2.1.0 (ISC License, Copyright (c) 2015 Per
// Liedman) and the parts of @turf/distance and @turf/explode 7.4.0 it uses
// (MIT License, Copyright (c) 2017 TurfJS). See NOTICE.

///|
/// The most line coordinates `Network::new` takes.
pub const MAX_ROUTE_VERTICES : Int32 = 2_000_000

///|
const PI : Double = 3.141592653589793

///|
/// Turf's kilometers per radian (`earthRadius / 1e3`).
const KM_FACTOR : Double = 6371.0088

///|
/// `@turf/distance` in kilometers (haversine), as `lineops` computes it.
fn distance(
  trig : @core.Trig,
  lng1 : Double,
  lat1 : Double,
  lng2 : Double,
  lat2 : Double,
) -> Double {
  let d_lat = radians(lat2 - lat1)
  let d_lng = radians(lng2 - lng1)
  let s_lat = trig.sin(d_lat / 2.0)
  let s_lng = trig.sin(d_lng / 2.0)
  let a = s_lat * s_lat +
    s_lng * s_lng * trig.cos(radians(lat1)) * trig.cos(radians(lat2))
  2.0 * trig.atan2(a.sqrt(), (1.0 - a).sqrt()) * KM_FACTOR
}

///|
/// Turf's `degreesToRadians`, which first takes the degrees modulo 360.
fn radians(degrees : Double) -> Double {
  degrees % 360.0 * PI / 180.0
}

///|
/// JavaScript's `Math.round`: halves go up. `x - floor(x)` is exact.
fn js_round(x : Double) -> Double {
  let f = x.floor()
  if x - f >= 0.5 {
    f + 1.0
  } else {
    f
  }
}

///|
/// The key `defaultKey(roundCoord(c))` gives a coordinate, as bits: `String`
/// is one-to-one on doubles but for 0 and -0 ("0") and NaNs ("NaN"), which are
/// merged here too.
fn key_bits(c : Double, tolerance : Double) -> Int64 {
  let r = js_round(c / tolerance) * tolerance
  if r.is_nan() {
    0x7FF8000000000000L
  } else if r == 0.0 {
    0L
  } else {
    r.reinterpret_as_int64()
  }
}

///|
/// Vertices along a compacted edge: one, two sequences joined, or a run.
priv enum Seq {
  Leaf(Int32)
  Cat(Seq, Seq)
  Run(Array[Int32])
}

///|
fn Seq::flatten(self : Seq, out : Array[Int32]) -> Unit {
  let stack = [self]
  while stack.pop() is Some(s) {
    match s {
      Leaf(v) => out.push(v)
      Cat(a, b) => {
        stack.push(b)
        stack.push(a)
      }
      Run(vs) => out.append(vs)
    }
  }
}

///|
/// A `PathFinder`: vertices numbered as `explode` meets their keys, each at the
/// last coordinate given for it; `vertices` as rows (`starts`), the compacted
/// graph as edge slots listed per vertex in JavaScript's key order (`edges`).
pub struct Network {
  priv tolerance : Double
  priv xs : FixedArray[Double]
  priv ys : FixedArray[Double]
  priv keys : PairIndex
  priv graph_order : Array[Int32]
  priv starts : FixedArray[Int32]
  priv nbrs : FixedArray[Int32]
  priv weights : FixedArray[Double]
  priv in_compacted : FixedArray[Bool]
  priv head : FixedArray[Int32]
  priv tail : FixedArray[Int32]
  priv slot_nbr : Array[Int32]
  priv slot_weight : Array[Double]
  priv slot_seq : Array[Seq]
  priv slot_next : Array[Int32]
  priv slot_prev : Array[Int32]
  priv edges : PairIndex
  priv mut base_slots : Int32
  priv mut compacted : Int32
  priv costs : FixedArray[Double]
}

///|
/// `PathFinder(network, {tolerance})` with each line of the LineString and
/// MultiLineString rows as a LineString feature; None where it throws (a NaN in
/// a line) or past `MAX_ROUTE_VERTICES` line coordinates.
pub fn Network::new(
  t : @geom.Table,
  tolerance~ : Double = 1.0e-5,
  trig~ : @core.Trig = @core.Trig::moonbit(),
) -> Network? {
  let lines : Array[(Int32, Int32)] = []
  let mut total = 0
  for f in 0..<t.length() {
    guard t.kinds[f] is (LineString | MultiLineString) else { continue }
    let (p0, p1) = t.parts(f)
    for p in p0..<p1 {
      let (r0, r1) = t.rings(p)
      for r in r0..<r1 {
        let (i0, i1) = t.points(r)
        total += i1 - i0
        if total > MAX_ROUTE_VERTICES {
          return None
        }
        for i in (i0 * 2)..<(i1 * 2) {
          if t.coords[i].is_nan() {
            return None
          }
        }
        lines.push((i0, i1))
      }
    }
  }
  let keys = PairIndex::new(total)
  let ids : Array[Int32] = Array(capacity=total)
  let xs : Array[Double] = []
  let ys : Array[Double] = []
  for line in lines {
    for i in line.0..<line.1 {
      let x = t.coords[i * 2]
      let y = t.coords[i * 2 + 1]
      let kx = key_bits(x, tolerance)
      let ky = key_bits(y, tolerance)
      let id = keys.get(kx, ky)
      if id >= 0 {
        xs[id] = x
        ys[id] = y
        ids.push(id)
      } else {
        keys.set(kx, ky, xs.length())
        ids.push(xs.length())
        xs.push(x)
        ys.push(y)
      }
    }
  }
  let n = xs.length()
  let net : Network = {
    tolerance,
    xs: FixedArray::from_array(xs),
    ys: FixedArray::from_array(ys),
    keys,
    graph_order: [],
    starts: FixedArray::make(n + 1, 0),
    nbrs: [],
    weights: [],
    in_compacted: FixedArray::make(n, false),
    head: FixedArray::make(n, -1),
    tail: FixedArray::make(n, -1),
    slot_nbr: [],
    slot_weight: [],
    slot_seq: [],
    slot_next: [],
    slot_prev: [],
    edges: PairIndex::new(total * 2),
    base_slots: 0,
    compacted: 0,
    costs: FixedArray::make(n, @double.infinity),
  }
  let mut k = 0
  for line in lines {
    for i in (line.0 + 1)..<line.1 {
      let a = ids[k + i - line.0 - 1]
      let b = ids[k + i - line.0]
      let w = distance(trig, net.xs[a], net.ys[a], net.xs[b], net.ys[b])
      if w != 0.0 && !w.is_nan() {
        net.add_to_graph(a)
        net.add_to_graph(b)
        net.put(a, b, w, Leaf(a))
        net.put(b, a, w, Leaf(b))
      }
    }
    k += line.1 - line.0
  }
  Some(net.freeze_graph().compact_graph())
}

///|
/// `makeEdgeList`: the graph's key order is the order vertices first get an
/// edge (`in_compacted` doubles as the graph's membership while building).
fn Network::add_to_graph(self : Network, v : Int32) -> Unit {
  if !self.in_compacted[v] {
    self.in_compacted[v] = true
    self.graph_order.push(v)
  }
}

///|
/// `vertices[v][n] = w` with its coordinates: a new key goes last, a known one
/// keeps its place.
fn Network::put(
  self : Network,
  v : Int32,
  n : Int32,
  w : Double,
  seq : Seq,
) -> Unit {
  let found = self.edges.get(v.to_int64(), n.to_int64())
  if found >= 0 {
    self.slot_weight[found] = w
    self.slot_seq[found] = seq
    return
  }
  let slot = self.slot_nbr.length()
  self.slot_nbr.push(n)
  self.slot_weight.push(w)
  self.slot_seq.push(seq)
  self.slot_next.push(-1)
  self.slot_prev.push(self.tail[v])
  if self.tail[v] >= 0 {
    self.slot_next[self.tail[v]] = slot
  } else {
    self.head[v] = slot
  }
  self.tail[v] = slot
  self.edges.set(v.to_int64(), n.to_int64(), slot)
}

///|
/// The slot of `v`'s edge to `n` in the compacted graph, or -1.
fn Network::slot(self : Network, v : Int32, n : Int32) -> Int32 {
  self.edges.get(v.to_int64(), n.to_int64())
}

///|
/// `delete vertices[v][n]`.
fn Network::unlink(self : Network, v : Int32, n : Int32) -> Unit {
  let slot = self.slot(v, n)
  guard slot >= 0 else { return }
  let p = self.slot_prev[slot]
  let x = self.slot_next[slot]
  if p >= 0 {
    self.slot_next[p] = x
  } else {
    self.head[v] = x
  }
  if x >= 0 {
    self.slot_prev[x] = p
  } else {
    self.tail[v] = p
  }
  self.edges.remove(v.to_int64(), n.to_int64())
}

///|
/// `delete vertices[v]`.
fn Network::drop_vertex(self : Network, v : Int32) -> Unit {
  let mut s = self.head[v]
  while s >= 0 {
    self.edges.remove(v.to_int64(), self.slot_nbr[s].to_int64())
    s = self.slot_next[s]
  }
  self.head[v] = -1
  self.tail[v] = -1
  self.in_compacted[v] = false
}

///|
/// `Object.keys(vertices[v])` of the compacted graph.
fn Network::compacted_neighbors(self : Network, v : Int32) -> Array[Int32] {
  let out = []
  let mut s = self.head[v]
  while s >= 0 {
    out.push(self.slot_nbr[s])
    s = self.slot_next[s]
  }
  out
}

///|
/// Copies the built graph into compressed rows, which compaction leaves as
/// they are.
fn Network::freeze_graph(self : Network) -> Network {
  let n = self.xs.length()
  let nbrs = FixedArray::make(self.slot_nbr.length(), 0)
  let weights = FixedArray::make(self.slot_nbr.length(), 0.0)
  let mut k = 0
  for v in 0..<n {
    self.starts[v] = k
    let mut s = self.head[v]
    while s >= 0 {
      nbrs[k] = self.slot_nbr[s]
      weights[k] = self.slot_weight[s]
      k += 1
      s = self.slot_next[s]
    }
  }
  self.starts[n] = k
  { ..self, nbrs, weights, }
}

///|
/// `shouldCompact` on the built graph.
fn Network::should_compact(self : Network, v : Int32) -> Bool {
  let s = self.starts[v]
  match self.starts[v + 1] - s {
    1 => self.slot(self.nbrs[s], v) < 0
    2 => self.slot(self.nbrs[s], v) >= 0 && self.slot(self.nbrs[s + 1], v) >= 0
    _ => false
  }
}

///|
/// `compactGraph`: vertices joining two others are removed, their edges
/// joined, in the graph's key order.
fn Network::compact_graph(self : Network) -> Network {
  let order = self.graph_order.filter(v => self.should_compact(v))
  for v in order {
    let around = self.compacted_neighbors(v)
    if around.is_empty() {
      continue
    }
    for n in around {
      for o in around {
        if n != o {
          self.join(v, n, o)
          self.join(v, o, n)
        }
      }
    }
    for n in around {
      self.unlink(n, v)
    }
    self.drop_vertex(v)
  }
  self.base_slots = self.slot_nbr.length()
  self.compacted = self.graph_order.length() - order.length()
  for v in order {
    if self.in_compacted[v] {
      self.compacted += 1
    }
  }
  self
}

///|
/// `compact(v, n, o)`: `n` gets an edge to `o` through `v` unless it has one.
/// Weights are positive, so JavaScript's truthiness is presence.
fn Network::join(self : Network, v : Int32, n : Int32, o : Int32) -> Unit {
  let from_n = self.slot(n, v)
  guard from_n >= 0 && self.slot(n, o) < 0 else { return }
  let to_o = self.slot(v, o)
  self.put(
    n,
    o,
    self.slot_weight[from_n] + self.slot_weight[to_o],
    Cat(self.slot_seq[from_n], self.slot_seq[to_o]),
  )
}

///|
/// The vertices of the network: those with an edge (`graph.vertices`).
pub fn Network::vertices(self : Network) -> Int32 {
  self.graph_order.length()
}

///|
/// The vertices left after compaction (`graph.compactedVertices`).
pub fn Network::compacted_vertices(self : Network) -> Int32 {
  self.compacted
}
