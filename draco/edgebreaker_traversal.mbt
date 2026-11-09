// Ported from Draco 1.5.7 (compression/mesh/mesh_edgebreaker_traversal_decoder.h, and its valence
// and predictive variants): Apache License 2.0, Copyright 2016 The Draco Authors. See NOTICE.

///|
/// `MeshEdgebreakerConnectivityEncodingMethod`: the standard, predictive and valence traversals.
const TRAVERSAL_STANDARD : Int32 = 0

///|
const TRAVERSAL_PREDICTIVE : Int32 = 1

///|
const TRAVERSAL_VALENCE : Int32 = 2

///|
/// A traversal decoder of `kind` (`TRAVERSAL_*`).
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
  if self.kind == TRAVERSAL_VALENCE {
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
  if self.kind == TRAVERSAL_PREDICTIVE {
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
    TRAVERSAL_VALENCE => {
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
  guard self.kind != TRAVERSAL_STANDARD else { return }
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
  if self.kind == TRAVERSAL_PREDICTIVE {
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
  if self.kind != TRAVERSAL_STANDARD {
    self.valences[dest] += self.valences[source]
  }
}
