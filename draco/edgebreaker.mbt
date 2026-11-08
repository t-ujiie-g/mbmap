// Ported from Draco 1.5.7 (compression/mesh/mesh_edgebreaker_decoder_impl.cc,
// mesh_edgebreaker_traversal_decoder.h, mesh_edgebreaker_traversal_valence_decoder.h,
// mesh_edgebreaker_traversal_predictive_decoder.h): Apache License 2.0, Copyright 2016 The Draco
// Authors. See NOTICE.

///|
/// The edgebreaker symbols as Draco's `EdgebreakerTopologyBitPattern` numbers them.
const TOPOLOGY_C = 0

///|
const TOPOLOGY_S = 1

///|
const TOPOLOGY_L = 3

///|
const TOPOLOGY_R = 5

///|
const TOPOLOGY_E = 7

///|
const TOPOLOGY_INVALID = 9

///|
let symbol_to_topology : FixedArray[Int32] = [
  TOPOLOGY_C,
  TOPOLOGY_S,
  TOPOLOGY_L,
  TOPOLOGY_R,
  TOPOLOGY_E,
]

///|
/// An attribute's seams (`AttributeData` of the edgebreaker decoder).
priv struct AttributeData {
  mut decoder_id : Int32
  mut table : AttrTable?
  mut connectivity_used : Bool
  enc : EncodingData
  seams : Array[Int32]
}

///|
/// A traversal decoder: `kind` 0 standard, 1 predictive, 2 valence.
priv struct Traversal {
  kind : Int32
  buffer : Buffer
  symbols : Buffer
  start_faces : BitDecoder
  start_face_buffer : Buffer
  mut seams : FixedArray[BitDecoder]
  mut num_attribute_data : Int32
  mut num_vertices : Int32
  mut valences : FixedArray[Int32]
  mut last_symbol : Int32
  mut active_context : Int32
  context_symbols : FixedArray[FixedArray[Int32]]
  context_counters : FixedArray[Int32]
  prediction : BitDecoder
  mut predicted_symbol : Int32
}

///|
/// The edgebreaker decoder's state (`MeshEdgebreakerDecoderImpl`).
priv struct Edgebreaker {
  ct : CornerTable
  version : Int32
  traversal : Traversal
  split_source : Array[Int32]
  split_target : Array[Int32]
  split_edge : Array[Int32]
  hole : FixedArray[Bool]
  attribute_data : Array[AttributeData]
  pos : EncodingData
  mut pos_decoder_id : Int32
}

///|
fn Traversal::new(kind : Int32, b : Buffer) -> Traversal {
  {
    kind,
    buffer: b.copy(),
    symbols: b.copy(),
    start_faces: BitDecoder::new(b.data),
    start_face_buffer: b.copy(),
    seams: [],
    num_attribute_data: 0,
    num_vertices: 0,
    valences: [],
    last_symbol: -1,
    active_context: -1,
    context_symbols: FixedArray::make(6, []),
    context_counters: FixedArray::make(6, 0),
    prediction: BitDecoder::new(b.data),
    predicted_symbol: -1,
  }
}

///|
fn Traversal::decode_traversal_symbols(self : Traversal) -> Bool {
  self.symbols.assign(self.buffer)
  let size = self.symbols.start_bits(true)
  guard !self.symbols.failed else { return false }
  self.buffer.assign(self.symbols)
  guard self.buffer.fits(size) else { return false }
  self.buffer.pos += size.to_int()
  true
}

///|
fn Traversal::decode_start_faces(self : Traversal) -> Bool {
  if self.buffer.version < bitstream(2, 2) {
    self.start_face_buffer.assign(self.buffer)
    let size = self.start_face_buffer.start_bits(true)
    guard !self.start_face_buffer.failed else { return false }
    self.buffer.assign(self.start_face_buffer)
    guard self.buffer.fits(size) else { return false }
    self.buffer.pos += size.to_int()
    return true
  }
  self.start_faces.start(self.buffer)
}

///|
fn Traversal::decode_attribute_seams(self : Traversal) -> Bool {
  if self.num_attribute_data > 0 {
    self.seams = FixedArray::makei(self.num_attribute_data, fn(_) {
      BitDecoder::new(self.buffer.data)
    })
    for d in self.seams {
      guard d.start(self.buffer) else { return false }
    }
  }
  true
}

///|
/// `Start`: the traversal's streams; `out` gets the buffer where the attributes begin.
fn Traversal::start(self : Traversal, out : Buffer, num_faces : Int32) -> Bool {
  let version = self.buffer.version
  if self.kind == 2 {
    if version < bitstream(2, 2) {
      guard self.decode_traversal_symbols() else { return false }
    }
    guard self.decode_start_faces() && self.decode_attribute_seams() else {
      return false
    }
    out.assign(self.buffer)
    if version < bitstream(2, 2) {
      let num_split = out.varint()
      guard !out.failed else { return false }
      guard ult(num_split, self.num_vertices) else { return false }
      let mode = out.i8()
      guard !out.failed && mode == 0 else { return false }
    }
    guard self.num_vertices >= 0 else { return false }
    self.valences = FixedArray::make(self.num_vertices, 0)
    for i in 0..<6 {
      let n = out.varint()
      guard !out.failed else { return false }
      guard !ult(num_faces, n) else { return false }
      if n > 0 {
        let symbols = FixedArray::make(n, 0)
        self.context_symbols[i] = symbols
        let _ = decode_symbols(n, 1, out, symbols)
        out.failed = false
        self.context_counters[i] = n
      }
    }
    return true
  }
  guard self.decode_traversal_symbols() &&
    self.decode_start_faces() &&
    self.decode_attribute_seams() else {
    return false
  }
  out.assign(self.buffer)
  if self.kind == 1 {
    let num_split = out.u32()
    guard !out.failed && num_split >= 0 else { return false }
    guard num_split < self.num_vertices else { return false }
    self.valences = FixedArray::make(self.num_vertices, 0)
    guard self.prediction.start(out) else { return false }
  }
  true
}

///|
fn Traversal::standard_symbol(self : Traversal) -> Int32 {
  let symbol = self.symbols.bits(1)
  if symbol == TOPOLOGY_C {
    return symbol
  }
  symbol | (self.symbols.bits(2) << 1)
}

///|
fn Traversal::decode_symbol(self : Traversal) -> Int32 {
  match self.kind {
    2 => {
      if self.active_context != -1 {
        let counter = self.context_counters[self.active_context] - 1
        self.context_counters[self.active_context] = counter
        if counter < 0 {
          return TOPOLOGY_INVALID
        }
        let symbol = self.context_symbols[self.active_context][counter]
        if ult(4, symbol) {
          return TOPOLOGY_INVALID
        }
        self.last_symbol = symbol_to_topology[symbol]
      } else if self.buffer.version < bitstream(2, 2) {
        self.last_symbol = self.standard_symbol()
      } else {
        self.last_symbol = TOPOLOGY_E
      }
      self.last_symbol
    }
    1 => {
      if self.predicted_symbol != -1 && self.prediction.bit() {
        self.last_symbol = self.predicted_symbol
        return self.predicted_symbol
      }
      self.last_symbol = self.standard_symbol()
      self.last_symbol
    }
    _ => self.standard_symbol()
  }
}

///|
fn Traversal::start_face_configuration(self : Traversal) -> Bool {
  if self.buffer.version < bitstream(2, 2) {
    self.start_face_buffer.bits(1) != 0
  } else {
    self.start_faces.bit()
  }
}

///|
fn Traversal::new_active_corner(
  self : Traversal,
  ct : CornerTable,
  corner : Int32,
) -> Unit {
  guard self.kind != 0 else { return }
  let nv = ct.vertex(next(corner))
  let pv = ct.vertex(previous(corner))
  let cv = ct.vertex(corner)
  let v = self.valences
  match self.last_symbol {
    TOPOLOGY_C | TOPOLOGY_S => {
      v[nv] += 1
      v[pv] += 1
    }
    TOPOLOGY_R => {
      v[cv] += 1
      v[nv] += 1
      v[pv] += 2
    }
    TOPOLOGY_L => {
      v[cv] += 1
      v[nv] += 2
      v[pv] += 1
    }
    TOPOLOGY_E => {
      v[cv] += 2
      v[nv] += 2
      v[pv] += 2
    }
    _ => ()
  }
  if self.kind == 1 {
    if self.last_symbol == TOPOLOGY_C || self.last_symbol == TOPOLOGY_R {
      self.predicted_symbol = if v[nv] < 6 { TOPOLOGY_R } else { TOPOLOGY_C }
    } else {
      self.predicted_symbol = -1
    }
    return
  }
  let valence = v[nv]
  let clamped = if valence < 2 { 2 } else if valence > 7 { 7 } else { valence }
  self.active_context = clamped - 2
}

///|
fn Traversal::merge_vertices(
  self : Traversal,
  dest : Int32,
  source : Int32,
) -> Unit {
  if self.kind != 0 {
    self.valences[dest] += self.valences[source]
  }
}

///|
fn Edgebreaker::set_opposites(self : Edgebreaker, a : Int32, b : Int32) -> Bool {
  guard a >= 0 && b >= 0 else { return false }
  self.ct.opp[a] = b
  self.ct.opp[b] = a
  true
}

///|
/// `IsTopologySplit`: 0 no split, 1 a split (its edge and symbol in `out`), -1 a bad one.
fn Edgebreaker::topology_split(
  self : Edgebreaker,
  encoder_symbol_id : Int32,
  out : FixedArray[Int32],
) -> Int32 {
  let n = self.split_source.length()
  if n == 0 {
    return 0
  }
  let source = self.split_source[n - 1]
  if ult(encoder_symbol_id, source) {
    return -1
  }
  if source != encoder_symbol_id {
    return 0
  }
  out[0] = self.split_edge[n - 1]
  out[1] = self.split_target[n - 1]
  self.split_source.truncate(n - 1)
  self.split_target.truncate(n - 1)
  self.split_edge.truncate(n - 1)
  1
}

///|
/// `DecodeHoleAndTopologySplitEvents`: the bytes read, or -1.
fn Edgebreaker::decode_events(self : Edgebreaker, b : Buffer) -> Int32 {
  let version = self.version
  let num_splits = b.varint()
  guard !b.failed else { return -1 }
  if num_splits != 0 {
    guard !ult(self.ct.face_count(), num_splits) else { return -1 }
    let mut last_source = 0
    for _ in 0..<num_splits {
      let delta = b.varint()
      guard !b.failed else { return -1 }
      let source = delta + last_source
      let delta2 = b.varint()
      guard !b.failed else { return -1 }
      guard !ult(source, delta2) else { return -1 }
      self.split_source.push(source)
      self.split_target.push(source - delta2)
      last_source = source
    }
    let _ = b.start_bits(false)
    let width = if version < bitstream(2, 2) { 2 } else { 1 }
    for _ in 0..<num_splits {
      self.split_edge.push(b.bits(width) & 1)
    }
    b.end_bits()
  }
  if version < bitstream(2, 1) {
    let num_holes = b.varint()
    guard !b.failed else { return -1 }
    for _ in 0..<num_holes {
      let _ = b.varint()
      guard !b.failed else { return -1 }
    }
  }
  b.pos
}

///|
/// `DecodeConnectivity(num_symbols)`: the number of vertices, or -1.
fn Edgebreaker::decode_connectivity(
  self : Edgebreaker,
  num_symbols : Int32,
) -> Int32 {
  let ct = self.ct
  let tr = self.traversal
  let stack : Array[Int32] = []
  let split_corners = FixedArray::make(num_symbols, -1)
  let invalid_vertices : Array[Int32] = []
  let remove_invalid = self.attribute_data.length() == 0
  let max_vertices = self.hole.length()
  let split = FixedArray::make(2, 0)
  let limit = ct.c2v.length() + 1
  let mut num_faces = 0
  for symbol_id in 0..<num_symbols {
    let face = num_faces
    num_faces += 1
    let mut check_split = false
    let symbol = tr.decode_symbol()
    if symbol == TOPOLOGY_C {
      guard stack.length() > 0 else { return -1 }
      let corner_a = stack[stack.length() - 1]
      let vertex_x = ct.vertex(next(corner_a))
      let corner_b = next(ct.left_most(vertex_x))
      guard corner_a != corner_b else { return -1 }
      guard ct.opposite(corner_a) < 0 && ct.opposite(corner_b) < 0 else {
        return -1
      }
      let corner = 3 * face
      guard self.set_opposites(corner_a, corner + 1) else { return -1 }
      guard self.set_opposites(corner_b, corner + 2) else { return -1 }
      let vert_a_prev = ct.vertex(previous(corner_a))
      let vert_b_next = ct.vertex(next(corner_b))
      guard vertex_x != vert_a_prev && vertex_x != vert_b_next else {
        return -1
      }
      ct.c2v[corner] = vertex_x
      ct.c2v[corner + 1] = vert_b_next
      ct.c2v[corner + 2] = vert_a_prev
      ct.set_left_most(vert_a_prev, corner + 2)
      self.hole[vertex_x] = false
      stack[stack.length() - 1] = corner
    } else if symbol == TOPOLOGY_R || symbol == TOPOLOGY_L {
      guard stack.length() > 0 else { return -1 }
      let corner_a = stack[stack.length() - 1]
      guard ct.opposite(corner_a) < 0 else { return -1 }
      let corner = 3 * face
      let (opp_corner, corner_l, corner_r) = if symbol == TOPOLOGY_R {
        (corner + 2, corner + 1, corner)
      } else {
        (corner + 1, corner, corner + 2)
      }
      guard self.set_opposites(opp_corner, corner_a) else { return -1 }
      let new_vert = ct.add_vertex()
      guard ct.vertex_count() <= max_vertices else { return -1 }
      ct.c2v[opp_corner] = new_vert
      ct.set_left_most(new_vert, opp_corner)
      let vertex_r = ct.vertex(previous(corner_a))
      ct.c2v[corner_r] = vertex_r
      ct.set_left_most(vertex_r, corner_r)
      ct.c2v[corner_l] = ct.vertex(next(corner_a))
      stack[stack.length() - 1] = corner
      check_split = true
    } else if symbol == TOPOLOGY_S {
      guard stack.length() > 0 else { return -1 }
      let corner_b = stack.unsafe_pop()
      if split_corners[symbol_id] >= 0 {
        stack.push(split_corners[symbol_id])
      }
      guard stack.length() > 0 else { return -1 }
      let corner_a = stack[stack.length() - 1]
      guard corner_a != corner_b else { return -1 }
      guard ct.opposite(corner_a) < 0 && ct.opposite(corner_b) < 0 else {
        return -1
      }
      let corner = 3 * face
      guard self.set_opposites(corner_a, corner + 2) else { return -1 }
      guard self.set_opposites(corner_b, corner + 1) else { return -1 }
      let vertex_p = ct.vertex(previous(corner_a))
      ct.c2v[corner] = vertex_p
      ct.c2v[corner + 1] = ct.vertex(next(corner_a))
      let vert_b_prev = ct.vertex(previous(corner_b))
      ct.c2v[corner + 2] = vert_b_prev
      ct.set_left_most(vert_b_prev, corner + 2)
      let mut corner_n = next(corner_b)
      let vertex_n = ct.vertex(corner_n)
      guard vertex_p >= 0 && vertex_n >= 0 else { return -1 }
      tr.merge_vertices(vertex_p, vertex_n)
      ct.set_left_most(vertex_p, ct.left_most(vertex_n))
      let first_corner = corner_n
      while corner_n >= 0 {
        ct.c2v[corner_n] = vertex_p
        corner_n = ct.swing_left(corner_n)
        guard corner_n != first_corner else { return -1 }
      }
      ct.vcorners[vertex_n] = -1
      if remove_invalid {
        invalid_vertices.push(vertex_n)
      }
      stack[stack.length() - 1] = corner
    } else if symbol == TOPOLOGY_E {
      let corner = 3 * face
      let first_vert = ct.add_vertex()
      ct.c2v[corner] = first_vert
      ct.c2v[corner + 1] = ct.add_vertex()
      ct.c2v[corner + 2] = ct.add_vertex()
      guard ct.vertex_count() <= max_vertices else { return -1 }
      ct.set_left_most(first_vert, corner)
      ct.set_left_most(first_vert + 1, corner + 1)
      ct.set_left_most(first_vert + 2, corner + 2)
      stack.push(corner)
      check_split = true
    } else {
      return -1
    }
    tr.new_active_corner(ct, stack[stack.length() - 1])
    if check_split {
      let encoder_symbol_id = num_symbols - symbol_id - 1
      while true {
        let r = self.topology_split(encoder_symbol_id, split)
        if r == 0 {
          break
        }
        guard r > 0 && split[1] >= 0 else { return -1 }
        let top = stack[stack.length() - 1]
        let new_active = if split[0] == 1 { next(top) } else { previous(top) }
        let decoder_split = num_symbols - split[1] - 1
        split_corners[decoder_split] = new_active
      }
    }
  }
  guard ct.vertex_count() <= max_vertices else { return -1 }
  while stack.length() > 0 {
    let corner = stack.unsafe_pop()
    if tr.start_face_configuration() {
      guard num_faces < ct.face_count() else { return -1 }
      let vert_n = ct.vertex(next(corner))
      let corner_b = next(ct.left_most(vert_n))
      let vert_x = ct.vertex(next(corner_b))
      let corner_c = next(ct.left_most(vert_x))
      guard corner != corner_b && corner != corner_c && corner_b != corner_c else {
        return -1
      }
      guard ct.opposite(corner) < 0 &&
        ct.opposite(corner_b) < 0 &&
        ct.opposite(corner_c) < 0 else {
        return -1
      }
      let vert_p = ct.vertex(next(corner_c))
      let new_corner = 3 * num_faces
      num_faces += 1
      guard self.set_opposites(new_corner, corner) else { return -1 }
      guard self.set_opposites(new_corner + 1, corner_b) else { return -1 }
      guard self.set_opposites(new_corner + 2, corner_c) else { return -1 }
      ct.c2v[new_corner] = vert_x
      ct.c2v[new_corner + 1] = vert_p
      ct.c2v[new_corner + 2] = vert_n
      for k in 0..<3 {
        let v = ct.c2v[new_corner + k]
        guard v >= 0 else { return -1 }
        self.hole[v] = false
      }
    }
  }
  guard num_faces == ct.face_count() else { return -1 }
  let mut num_vertices = ct.vertex_count()
  for invalid_vert in invalid_vertices {
    let mut src_vert = num_vertices - 1
    while src_vert >= 0 && ct.vcorners[src_vert] < 0 {
      num_vertices -= 1
      src_vert = num_vertices - 1
    }
    guard src_vert >= 0 else { return -1 }
    if src_vert < invalid_vert {
      continue
    }
    let start = ct.vcorners[src_vert]
    let mut c = start
    let mut left = true
    let mut steps = 0
    while c >= 0 {
      guard ct.c2v[c] == src_vert else { return -1 }
      ct.c2v[c] = invalid_vert
      if left {
        c = ct.swing_left(c)
        if c < 0 {
          c = ct.swing_right(start)
          left = false
        } else if c == start {
          c = -1
        }
      } else {
        c = ct.swing_right(c)
      }
      steps += 1
      guard steps <= limit else { return -1 }
    }
    ct.vcorners[invalid_vert] = ct.vcorners[src_vert]
    ct.vcorners[src_vert] = -1
    self.hole[invalid_vert] = self.hole[src_vert]
    self.hole[src_vert] = false
    num_vertices -= 1
  }
  num_vertices
}

///|
fn Edgebreaker::attribute_connectivity(
  self : Edgebreaker,
  corner : Int32,
) -> Unit {
  let ct = self.ct
  let corners = [corner, next(corner), previous(corner)]
  let src_face = corner / 3
  for c in corners {
    let opp = ct.opposite(c)
    if opp < 0 {
      for d in self.attribute_data {
        d.seams.push(c)
      }
      continue
    }
    if self.version >= bitstream(2, 1) && opp / 3 < src_face {
      continue
    }
    for i, d in self.attribute_data {
      if self.traversal.seams[i].bit() {
        d.seams.push(c)
      }
    }
  }
}

///|
/// `AssignPointsToCorners`: the mesh's faces as point ids and the number of points, or None.
fn Edgebreaker::assign_points(
  self : Edgebreaker,
  num_connectivity_verts : Int32,
) -> (FixedArray[Int32], Int32)? {
  let ct = self.ct
  let num_corners = ct.c2v.length()
  if self.attribute_data.length() == 0 {
    return Some(
      (
        FixedArray::makei(num_corners, fn(c) { ct.c2v[c] }),
        num_connectivity_verts,
      ),
    )
  }
  let tables = self.attribute_data.map(fn(d) { d.table.unwrap() })
  let corner_to_point = FixedArray::make(num_corners, 0)
  let limit = num_corners + 1
  let mut num_points = 0
  for v in 0..<ct.vertex_count() {
    let mut c = ct.vcorners[v]
    if c < 0 {
      continue
    }
    let mut first = c
    if !self.hole[v] {
      for t in tables {
        if !t.on_seam(c) {
          continue
        }
        let vert = t.c2v[c]
        let mut act = ct.swing_right(c)
        let mut found = false
        let mut steps = 0
        while act != c {
          guard act >= 0 else { return None }
          if t.c2v[act] != vert {
            first = act
            found = true
            break
          }
          act = ct.swing_right(act)
          steps += 1
          guard steps <= limit else { return None }
        }
        if found {
          break
        }
      }
    }
    c = first
    corner_to_point[c] = num_points
    num_points += 1
    let mut prev = c
    c = ct.swing_right(c)
    let mut steps = 0
    while c >= 0 && c != first {
      let mut seam = false
      for t in tables {
        if t.c2v[c] != t.c2v[prev] {
          seam = true
          break
        }
      }
      if seam {
        corner_to_point[c] = num_points
        num_points += 1
      } else {
        corner_to_point[c] = corner_to_point[prev]
      }
      prev = c
      c = ct.swing_right(c)
      steps += 1
      guard steps <= limit else { return None }
    }
  }
  Some((corner_to_point, num_points))
}

///|
/// `MeshEdgebreakerDecoderImpl::DecodeConnectivity`: the faces as point ids and the number of
/// points, or None.
fn decode_edgebreaker(
  b : Buffer,
  kind : Int32,
) -> (Edgebreaker, FixedArray[Int32], Int32)? {
  let version = b.version
  if version < bitstream(2, 2) {
    let _ = b.varint()
    guard !b.failed else { return None }
  }
  let num_encoded_vertices = b.varint()
  guard !b.failed else { return None }
  let num_faces = b.varint()
  guard !b.failed else { return None }
  guard !ult(0x55555555, num_faces) else { return None }
  guard !ult(num_faces * 3, num_encoded_vertices) else { return None }
  let min_face_edges = (3 * num_faces).reinterpret_as_uint() / 2
  let nv = num_encoded_vertices.reinterpret_as_uint().to_uint64()
  guard nv * (nv - 1) / 2 >= min_face_edges.to_uint64() else { return None }
  let num_attribute_data = b.u8()
  guard !b.failed else { return None }
  let num_symbols = b.varint()
  guard !b.failed else { return None }
  guard !ult(num_faces, num_symbols) else { return None }
  guard !ult(
    (num_symbols.reinterpret_as_uint() + num_symbols.reinterpret_as_uint() / 3).reinterpret_as_int(),
    num_faces,
  ) else {
    return None
  }
  let num_split_symbols = b.varint()
  guard !b.failed else { return None }
  guard !ult(num_symbols, num_split_symbols) else { return None }
  guard num_faces <= MAX_FACES else { return None }
  let num_vertices = num_encoded_vertices + num_split_symbols
  guard num_vertices >= 0 && num_vertices <= 3 * MAX_FACES else { return None }
  let ct = CornerTable::new(num_faces)
  let eb : Edgebreaker = {
    ct,
    version,
    traversal: Traversal::new(kind, b),
    split_source: [],
    split_target: [],
    split_edge: [],
    hole: FixedArray::make(num_vertices, true),
    attribute_data: Array::makei(num_attribute_data, fn(_) {
      {
        decoder_id: -1,
        table: None,
        connectivity_used: true,
        enc: EncodingData::new(),
        seams: [],
      }
    }),
    pos: EncodingData::new(),
    pos_decoder_id: -1,
  }
  let mut split_bytes = -1
  if version < bitstream(2, 2) {
    let size = b.varint()
    guard !b.failed else { return None }
    guard size != 0 && b.fits(size.reinterpret_as_uint().to_uint64()) else {
      return None
    }
    let events = b.copy()
    events.init(b.head() + size, b.remaining() - size, version)
    split_bytes = eb.decode_events(events)
    guard split_bytes != -1 else { return None }
  } else {
    guard eb.decode_events(b) != -1 else { return None }
  }
  let tr = eb.traversal
  tr.buffer.init(b.head(), b.remaining(), version)
  tr.num_vertices = num_vertices
  tr.num_attribute_data = num_attribute_data
  let end = b.copy()
  guard tr.start(end, num_faces) else { return None }
  let num_connectivity_verts = eb.decode_connectivity(num_symbols)
  guard num_connectivity_verts != -1 else { return None }
  b.init(end.head(), end.remaining(), version)
  if version < bitstream(2, 2) {
    b.pos += split_bytes
  }
  if eb.attribute_data.length() > 0 {
    let mut c = 0
    while c < ct.c2v.length() {
      eb.attribute_connectivity(c)
      c += 3
    }
  }
  for d in eb.attribute_data {
    let t = AttrTable::new(ct)
    for c in d.seams {
      t.add_seam_edge(c)
    }
    guard t.recompute_vertices() else { return None }
    d.table = Some(t)
  }
  eb.pos.vertex_values = FixedArray::make(ct.vertex_count(), 0)
  for d in eb.attribute_data {
    let n = d.table.unwrap().entries.length()
    d.enc.vertex_values = FixedArray::make(
      if n < ct.vertex_count() {
        ct.vertex_count()
      } else {
        n
      },
      0,
    )
  }
  guard eb.assign_points(num_connectivity_verts) is Some((faces, num_points)) else {
    return None
  }
  Some((eb, faces, num_points))
}
