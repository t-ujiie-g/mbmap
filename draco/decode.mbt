// Ported from Draco 1.5.7 (compression/decode.cc, the point cloud, sequential mesh and metadata
// decoders, and the emscripten decoder's output arrays): Apache License 2.0, Copyright 2016 The
// Draco Authors. See NOTICE.

///|
/// The most faces a mesh may have (Draco takes up to 2^32 / 3).
pub const MAX_FACES : Int32 = 0x400000

///|
/// The most points a mesh or point cloud may have.
pub const MAX_POINTS : Int32 = 0x400000

///|
/// The most attributes a mesh or point cloud may have.
pub const MAX_ATTRIBUTES : Int32 = 256

///|
/// The most bytes one attribute's values may take.
pub const MAX_ATTRIBUTE_BYTES : Int32 = 0x10000000

///|
/// Draco's `DataType` numbers, `DT_INT8` (1) to `DT_BOOL` (11); 0 is `DT_INVALID`.
const DT_INT8 : Int32 = 1

///|
const DT_UINT8 : Int32 = 2

///|
const DT_INT16 : Int32 = 3

///|
const DT_UINT16 : Int32 = 4

///|
const DT_INT32 : Int32 = 5

///|
const DT_UINT32 : Int32 = 6

///|
const DT_INT64 : Int32 = 7

///|
const DT_UINT64 : Int32 = 8

///|
const DT_FLOAT32 : Int32 = 9

///|
const DT_FLOAT64 : Int32 = 10

///|
const DT_BOOL : Int32 = 11

///|
/// `GeometryAttribute::POSITION`, the first of its `NAMED_ATTRIBUTES_COUNT` types.
const ATTRIBUTE_POSITION : Int32 = 0

///|
const NAMED_ATTRIBUTES_COUNT : Int32 = 5

///|
/// `EncodedGeometryType`'s `TRIANGULAR_MESH` (0 is `POINT_CLOUD`).
const TRIANGULAR_MESH : Int32 = 1

///|
/// The header's encoding method past 0 (sequential): `MESH_EDGEBREAKER_ENCODING` of a mesh,
/// `POINT_CLOUD_KD_TREE_ENCODING` of a point cloud.
const EDGEBREAKER_ENCODING : Int32 = 1

///|
const KD_TREE_ENCODING : Int32 = 1

///|
/// One attribute of a decoded mesh, its fields as docs/FORMATS.md "Draco output" numbers them:
/// `unique_id` (uint32 bits) what KHR_draco_mesh_compression's `attributes` name, Draco's
/// `attribute_type` and `data_type`, and `data` (draco3d's `GetAttributeDataArrayForAllPoints`).
pub struct DracoAttribute {
  unique_id : Int32
  attribute_type : Int32
  data_type : Int32
  num_components : Int32
  normalized : Bool
  data : FixedArray[Byte]
}

///|
/// A decoded Draco mesh or point cloud: `indices` holds three point indices (uint32 bits) per
/// face, as draco3d's `GetTrianglesUInt32Array` (none for a point cloud), and `attributes` every
/// attribute in the order it was decoded.
pub struct DracoMesh {
  indices : FixedArray[Int32]
  num_points : Int32
  attributes : Array[DracoAttribute]
}

///|
/// The first attribute whose unique id is `unique_id`, as draco3d's `GetAttributeByUniqueId`.
pub fn DracoMesh::attribute(
  self : DracoMesh,
  unique_id : Int32,
) -> DracoAttribute? {
  for a in self.attributes {
    if a.unique_id == unique_id {
      return Some(a)
    }
  }
  None
}

///|
/// The decoder's state: the mesh being decoded, its attributes and their decoders.
priv struct Decoder {
  b : Buffer
  mut faces : FixedArray[Int32]
  mut num_points : Int32
  attributes : Array[Attribute]
  decoders : Array[AttributesDecoder]
  att_to_decoder : Array[Int32]
  mut eb : Edgebreaker?
  mut kd : Bool
}

///|
/// `MetadataDecoder::DecodeGeometryMetadata`, read only to skip it (with Draco's checks, which
/// include refusing two sub-metadata of one name).
fn decode_metadata(b : Buffer) -> Bool {
  let num_attribute_metadata = b.varint()
  guard !b.failed else { return false }
  for _ in 0..<num_attribute_metadata {
    let _ = b.varint()
    guard !b.failed && decode_metadata_tree(b) else { return false }
  }
  decode_metadata_tree(b)
}

///|
/// The sub-metadata names met so far, each a parent node and a byte range of the input, in an
/// open-addressed hash table (`slots` holds name indices, -1 for none).
priv struct Names {
  parent : Array[Int32]
  start : Array[Int32]
  len : Array[Int32]
  mut slots : FixedArray[Int32]
}

///|
fn Names::hash(
  data : FixedArray[Byte],
  parent : Int32,
  start : Int32,
  len : Int32,
) -> Int32 {
  let mut h = 0x811c9dc5 ^ parent
  for i in start..<(start + len) {
    h = (h ^ data[i].to_int()) * 0x01000193
  }
  h & 0x7fffffff
}

///|
/// Adds the name at `data[start, start + len)` under `parent`; false when it is there already
/// (Draco's `AddSubMetadata` refuses it).
fn Names::add(
  self : Names,
  data : FixedArray[Byte],
  parent : Int32,
  start : Int32,
  len : Int32,
) -> Bool {
  if 2 * (self.parent.length() + 1) > self.slots.length() {
    let slots = FixedArray::make(2 * self.slots.length(), -1)
    for k in 0..<self.parent.length() {
      let mut at = Names::hash(data, self.parent[k], self.start[k], self.len[k]) &
        (slots.length() - 1)
      while slots[at] >= 0 {
        at = (at + 1) & (slots.length() - 1)
      }
      slots[at] = k
    }
    self.slots = slots
  }
  let mask = self.slots.length() - 1
  let mut at = Names::hash(data, parent, start, len) & mask
  while self.slots[at] >= 0 {
    let k = self.slots[at]
    if self.parent[k] == parent && self.len[k] == len {
      let mut equal = true
      for i in 0..<len {
        if data[self.start[k] + i] != data[start + i] {
          equal = false
          break
        }
      }
      if equal {
        return false
      }
    }
    at = (at + 1) & mask
  }
  self.slots[at] = self.parent.length()
  self.parent.push(parent)
  self.start.push(start)
  self.len.push(len)
  true
}

///|
/// Skips a name (a length byte and its bytes); its start, or -1 when it does not fit.
fn skip_name(b : Buffer) -> Int32 {
  let len = b.u8()
  guard !b.failed && b.has(len) else { return -1 }
  let start = b.head()
  b.pos += len
  start
}

///|
fn decode_metadata_tree(b : Buffer) -> Bool {
  let names : Names = {
    parent: [],
    start: [],
    len: [],
    slots: FixedArray::make(16, -1),
  }
  let stack : Array[(Int32, Int32)] = [(-1, 0)]
  let mut nodes = 1
  while stack.length() > 0 {
    let (parent, level) = stack.unsafe_pop()
    let mut node = 0
    if parent >= 0 {
      guard level <= 1000 else { return false }
      let start = skip_name(b)
      guard start >= 0 else { return false }
      guard names.add(b.data, parent, start, b.head() - start) else {
        return false
      }
      node = nodes
      nodes += 1
    }
    let num_entries = b.varint()
    guard !b.failed else { return false }
    for _ in 0..<num_entries {
      guard skip_name(b) >= 0 else { return false }
      let size = b.varint()
      guard !b.failed else { return false }
      guard size != 0 && b.fits(size.reinterpret_as_uint().to_uint64()) else {
        return false
      }
      b.pos += size
    }
    let num_sub = b.varint()
    guard !b.failed else { return false }
    guard b.fits(num_sub.reinterpret_as_uint().to_uint64()) else {
      return false
    }
    for _ in 0..<num_sub {
      stack.push((node, if parent >= 0 { level + 1 } else { level }))
    }
  }
  true
}

///|
/// `MeshSequentialDecoder::DecodeConnectivity`.
fn Decoder::decode_sequential(self : Decoder) -> Bool {
  let b = self.b
  let version = b.version
  let num_faces = if version < bitstream(2, 2) { b.u32() } else { b.varint() }
  guard !b.failed else { return false }
  let num_points = if version < bitstream(2, 2) { b.u32() } else { b.varint() }
  guard !b.failed else { return false }
  let faces64 = num_faces.reinterpret_as_uint().to_uint64()
  guard faces64 <= 0x55555555UL else { return false }
  guard b.remaining() < 0 || faces64 <= (b.remaining() / 3).to_uint64() else {
    return false
  }
  guard num_faces <= MAX_FACES && num_points >= 0 && num_points <= MAX_POINTS else {
    return false
  }
  let predictor = b.u8()
  guard !b.failed else { return false }
  let n = num_faces * 3
  let faces = FixedArray::make(n, 0)
  if predictor == 0 {
    guard decode_symbols(n, 1, b, faces) else { return false }
    let mut last = 0
    for i in 0..<n {
      let encoded = faces[i]
      let mut diff = (encoded.reinterpret_as_uint() >> 1).reinterpret_as_int()
      if (encoded & 1) != 0 {
        guard diff <= last else { return false }
        diff = -diff
      } else {
        guard diff <= 0x7fffffff - last else { return false }
      }
      last = diff + last
      faces[i] = last
    }
  } else {
    for i in 0..<n {
      faces[i] = if num_points < 256 {
        b.u8()
      } else if num_points < 65536 {
        b.u16()
      } else if num_points < 0x200000 && version >= bitstream(2, 2) {
        b.varint()
      } else {
        b.u32()
      }
      guard !b.failed else { return false }
    }
  }
  self.faces = faces
  self.num_points = num_points
  true
}

///|
/// `MeshEdgebreakerDecoderImpl::CreateAttributesDecoder`'s sequencer.
fn Decoder::edgebreaker_sequencer(
  self : Decoder,
  eb : Edgebreaker,
  id : Int32,
) -> Sequencer? {
  let b = self.b
  let data_id = b.i8()
  guard !b.failed else { return None }
  let decoder_type = b.u8()
  guard !b.failed else { return None }
  if data_id >= 0 {
    guard data_id < eb.attribute_data.length() else { return None }
    guard eb.attribute_data[data_id].decoder_id < 0 else { return None }
    eb.attribute_data[data_id].decoder_id = id
  } else {
    guard eb.pos_decoder_id < 0 else { return None }
    eb.pos_decoder_id = id
  }
  let predictor = b.u8()
  guard !b.failed && predictor < 2 else { return None }
  if decoder_type == 0 {
    let enc = if data_id < 0 {
      eb.pos
    } else {
      eb.attribute_data[data_id].connectivity_used = false
      eb.attribute_data[data_id].enc
    }
    Some(
      if predictor == 1 {
        Degree(eb.ct, enc)
      } else {
        DepthFirst(Main(eb.ct), enc)
      },
    )
  } else {
    guard predictor == 0 && data_id >= 0 else { return None }
    let data = eb.attribute_data[data_id]
    Some(DepthFirst(Seams(data.table.unwrap()), data.enc))
  }
}

///|
/// `PointCloudDecoder::DecodePointAttributes`.
fn Decoder::decode_point_attributes(self : Decoder) -> Bool {
  let b = self.b
  let n = b.u8()
  guard !b.failed else { return false }
  for i in 0..<n {
    let sequencer = match self.eb {
      Some(eb) => {
        guard self.edgebreaker_sequencer(eb, i) is Some(s) else { return false }
        s
      }
      None => Linear(self.num_points)
    }
    self.decoders.push(
      if self.kd {
        AttributesDecoder::kd_tree()
      } else {
        AttributesDecoder::new(sequencer)
      },
    )
  }
  for d in self.decoders {
    guard self.decode_attributes_data(d) else { return false }
  }
  for i, d in self.decoders {
    for att in d.ids {
      while self.att_to_decoder.length() <= att {
        self.att_to_decoder.push(0)
      }
      self.att_to_decoder[att] = i
    }
  }
  for d in self.decoders {
    guard self.decode_attributes(d) else { return false }
  }
  true
}

///|
/// The attribute's values for every point (`GetAttributeDataArrayForAllPoints` in its own type).
fn Decoder::output(self : Decoder, a : Attribute) -> DracoAttribute? {
  let stride = a.stride()
  let bytes = self.num_points.to_int64() * stride.to_int64()
  guard bytes <= MAX_ATTRIBUTE_BYTES.to_int64() else { return None }
  let data = FixedArray::make(bytes.to_int(), b'\x00')
  for p in 0..<self.num_points {
    let v = match a.map {
      None => p
      Some(m) => m[p]
    }
    guard v >= 0 && v < a.size else { return None }
    for k in 0..<stride {
      data[p * stride + k] = a.values[v * stride + k]
    }
  }
  Some({
    unique_id: a.unique_id,
    attribute_type: a.att_type,
    data_type: a.data_type,
    num_components: a.num_components,
    normalized: a.normalized,
    data,
  })
}

///|
/// Decodes the Draco mesh or point cloud (no faces) in `src[offset, offset + length)` as its header
/// says, as draco3d 1.5.7's `DecodeArrayToMesh` / `DecodeArrayToPointCloud` do; None where draco3d
/// fails, before bitstream 2.0 and past the `MAX_*` caps (docs/FORMATS.md "Draco output").
pub fn decode(
  src : FixedArray[Byte],
  offset : Int32,
  length : Int32,
) -> DracoMesh? {
  guard offset >= 0 && length >= 0 && length <= src.length() - offset else {
    return None
  }
  let b = Buffer::new(src, offset, length)
  guard b.has(5) else { return None }
  for c in [68, 82, 65, 67, 79] {
    guard b.u8() == c else { return None }
  }
  let major = b.u8()
  let minor = b.u8()
  let encoder_type = b.u8()
  let encoding = b.u8()
  let flags = b.u16()
  guard !b.failed else { return None }
  guard encoder_type <= TRIANGULAR_MESH && encoding <= EDGEBREAKER_ENCODING else {
    return None
  }
  let mesh = encoder_type == TRIANGULAR_MESH
  guard major == 2 && minor <= (if mesh { 2 } else { 3 }) else { return None }
  b.version = bitstream(major, minor)
  if (flags & 0x8000) != 0 {
    guard decode_metadata(b) else { return None }
  }
  let d : Decoder = {
    b,
    faces: [],
    num_points: 0,
    attributes: [],
    decoders: [],
    att_to_decoder: [],
    eb: None,
    kd: false,
  }
  if !mesh {
    guard d.decode_point_cloud(encoding) else { return None }
  } else if encoding == EDGEBREAKER_ENCODING {
    let kind = b.u8()
    guard !b.failed && kind <= TRAVERSAL_VALENCE else { return None }
    guard decode_edgebreaker(b, kind) is Some((eb, faces, num_points)) else {
      return None
    }
    guard num_points <= MAX_POINTS else { return None }
    d.eb = Some(eb)
    d.faces = faces
    d.num_points = num_points
    guard d.decode_point_attributes() else { return None }
  } else {
    guard d.decode_sequential() else { return None }
    guard d.decode_point_attributes() else { return None }
  }
  let attributes = []
  for a in d.attributes {
    guard d.output(a) is Some(out) else { return None }
    attributes.push(out)
  }
  Some({ indices: d.faces, num_points: d.num_points, attributes, })
}
