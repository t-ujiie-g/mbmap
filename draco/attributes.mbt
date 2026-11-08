// Ported from Draco 1.5.7 (compression/attributes/attributes_decoder.cc,
// sequential_attribute_decoders_controller.cc, sequential_*_attribute_decoder.cc,
// attributes/attribute_quantization_transform.cc, attribute_octahedron_transform.cc): Apache License
// 2.0, Copyright 2016 The Draco Authors. See NOTICE.

///|
/// `SequentialAttributeEncoderType`.
const SEQUENTIAL_GENERIC = 0

///|
const SEQUENTIAL_INTEGER = 1

///|
const SEQUENTIAL_QUANTIZATION = 2

///|
const SEQUENTIAL_NORMALS = 3

///|
/// `DataTypeLength` of Draco's `DataType` (1 `DT_INT8` to 11 `DT_BOOL`; 0 and 12 on are invalid).
fn data_type_length(dt : Int32) -> Int32 {
  match dt {
    1 | 2 | 11 => 1
    3 | 4 => 2
    5 | 6 | 9 => 4
    7 | 8 | 10 => 8
    _ => -1
  }
}

///|
/// A decoded `PointAttribute`: `values` holds `size` entries of `num_components` values of
/// `data_type`; `map` gives each point's entry (None for the identity), and `portable` the
/// integer values the sequential integer decoders produce.
priv struct Attribute {
  att_type : Int32
  data_type : Int32
  num_components : Int32
  normalized : Bool
  unique_id : Int32
  mut values : FixedArray[Byte]
  mut size : Int32
  mut map : FixedArray[Int32]?
  mut portable : FixedArray[Int32]?
  mut portable_components : Int32
}

///|
fn Attribute::stride(self : Attribute) -> Int32 {
  data_type_length(self.data_type) * self.num_components
}

///|
/// A `SequentialAttributeDecoder` of `kind` (`SEQUENTIAL_*`) for attribute `att`, with the
/// quantization or octahedron parameters it reads.
priv struct SequentialDecoder {
  kind : Int32
  att : Int32
  mut min_values : FixedArray[Float]
  mut range : Float
  mut bits : Int32
}

///|
/// `SequentialAttributeDecodersController`.
priv struct AttributesDecoder {
  sequencer : Sequencer
  ids : Array[Int32]
  local_ids : Array[Int32]
  decoders : Array[SequentialDecoder]
}

///|
fn AttributesDecoder::new(sequencer : Sequencer) -> AttributesDecoder {
  { sequencer, ids: [], local_ids: [], decoders: [], }
}

///|
fn AttributesDecoder::local_id(self : AttributesDecoder, att : Int32) -> Int32 {
  if att < 0 || att >= self.local_ids.length() {
    -1
  } else {
    self.local_ids[att]
  }
}

///|
fn store_u32(out : FixedArray[Byte], at : Int32, v : Int32) -> Unit {
  out[at] = v.to_byte()
  out[at + 1] = (v >> 8).to_byte()
  out[at + 2] = (v >> 16).to_byte()
  out[at + 3] = (v >> 24).to_byte()
}

///|
fn Decoder::decode_attributes_data(
  self : Decoder,
  d : AttributesDecoder,
) -> Bool {
  let b = self.b
  let n = b.varint()
  guard !b.failed else { return false }
  guard n != 0 else { return false }
  guard b.remaining() >= 0 &&
    n.reinterpret_as_uint().to_int64() <= 5L * b.remaining().to_int64() else {
    return false
  }
  guard n <= MAX_ATTRIBUTES && self.attributes.length() + n <= MAX_ATTRIBUTES else {
    return false
  }
  for i in 0..<n {
    let att_type = b.u8()
    guard !b.failed else { return false }
    let data_type = b.u8()
    guard !b.failed else { return false }
    let num_components = b.u8()
    guard !b.failed else { return false }
    let normalized = b.u8()
    guard !b.failed else { return false }
    guard att_type < 5 else { return false }
    guard data_type != 0 && data_type < 12 else { return false }
    guard num_components != 0 else { return false }
    let unique_id = b.varint()
    guard !b.failed else { return false }
    let att_id = self.attributes.length()
    self.attributes.push({
      att_type,
      data_type,
      num_components,
      normalized: normalized > 0,
      unique_id,
      values: [],
      size: 0,
      map: None,
      portable: None,
      portable_components: 0,
    })
    d.ids.push(att_id)
    while d.local_ids.length() <= att_id {
      d.local_ids.push(-1)
    }
    d.local_ids[att_id] = i
  }
  for att in d.ids {
    let kind = b.u8()
    guard !b.failed else { return false }
    guard kind <= SEQUENTIAL_NORMALS else { return false }
    let a = self.attributes[att]
    if kind == SEQUENTIAL_QUANTIZATION {
      guard a.data_type == DT_FLOAT32 else { return false }
    } else if kind == SEQUENTIAL_NORMALS {
      guard a.num_components == 3 && a.data_type == DT_FLOAT32 else {
        return false
      }
    }
    d.decoders.push({ kind, att, min_values: [], range: 0.0, bits: -1, })
  }
  true
}

///|
/// `PointCloudDecoder::GetPortableAttribute` of the first position attribute, as the prediction
/// schemes with a parent ask for it.
fn Decoder::position_parent(self : Decoder) -> Parent? {
  let mut pos = -1
  for i, a in self.attributes {
    if a.att_type == 0 {
      pos = i
      break
    }
  }
  guard pos >= 0 && pos < self.att_to_decoder.length() else { return None }
  let dec = self.att_to_decoder[pos]
  guard dec >= 0 && dec < self.decoders.length() else { return None }
  guard self.decoders[dec].local_id(pos) >= 0 else { return None }
  let a = self.attributes[pos]
  guard a.portable is Some(values) && a.portable_components == 3 else {
    return None
  }
  Some({ values, map: a.map, })
}

///|
/// `CreateIntPredictionScheme` and `CreatePredictionSchemeForDecoder`: None when the transform is
/// not one the decoder takes (the values are then decoded without prediction).
fn Decoder::create_scheme(
  self : Decoder,
  att : Int32,
  kind : Int32,
  predictor : Int32,
  transform_type : Int32,
) -> Scheme? {
  let tkind = if kind == SEQUENTIAL_NORMALS {
    if transform_type == TRANSFORM_OCTAHEDRON ||
      transform_type == TRANSFORM_CANONICALIZED {
      transform_type
    } else {
      return None
    }
  } else if transform_type == TRANSFORM_WRAP {
    TRANSFORM_WRAP
  } else {
    return None
  }
  let transform = Transform::new(tkind)
  if predictor >= PREDICTION_PARALLELOGRAM &&
    predictor <= PREDICTION_GEOMETRIC_NORMAL {
    if self.eb is Some(eb) &&
      (tkind == TRANSFORM_WRAP || predictor == PREDICTION_GEOMETRIC_NORMAL) {
      let (table, enc) = self.mesh_data(eb, att)
      return Some(
        Scheme::new(predictor, transform, Some(table), enc, self.b.data),
      )
    }
  }
  Some(
    Scheme::new(
      PREDICTION_DELTA,
      transform,
      None,
      EncodingData::new(),
      self.b.data,
    ),
  )
}

///|
/// `GetAttributeCornerTable` and `GetAttributeEncodingData` of the edgebreaker decoder.
fn Decoder::mesh_data(
  self : Decoder,
  eb : Edgebreaker,
  att : Int32,
) -> (Table, EncodingData) {
  for data in eb.attribute_data {
    let id = data.decoder_id
    if id < 0 || id >= self.decoders.length() {
      continue
    }
    if self.decoders[id].ids.contains(att) {
      match data.table {
        Some(t) if data.connectivity_used => return (Seams(t), data.enc)
        _ => return (Main(eb.ct), data.enc)
      }
    }
  }
  (Main(eb.ct), eb.pos)
}

///|
/// `SequentialIntegerAttributeDecoder::DecodeValues` and `DecodeIntegerValues`.
fn Decoder::decode_integer_values(
  self : Decoder,
  sd : SequentialDecoder,
  points : Array[Int32],
) -> Bool {
  let b = self.b
  let a = self.attributes[sd.att]
  let predictor = b.i8()
  guard !b.failed else { return false }
  guard predictor >= -2 && predictor < 7 else { return false }
  let mut scheme = None
  if predictor != -2 {
    let transform_type = b.i8()
    guard !b.failed else { return false }
    guard transform_type >= -1 && transform_type < 4 else { return false }
    scheme = self.create_scheme(sd.att, sd.kind, predictor, transform_type)
  }
  if scheme is Some(s) && s.has_parent() {
    guard self.position_parent() is Some(parent) else { return false }
    s.parent = Some(parent)
  }
  let nc = if sd.kind == SEQUENTIAL_NORMALS { 2 } else { a.num_components }
  let num_entries = points.length()
  let num_values = num_entries * nc
  guard num_values.to_int64() * 4L <= MAX_ATTRIBUTE_BYTES.to_int64() else {
    return false
  }
  let data = FixedArray::make(num_values, 0)
  a.portable = Some(data)
  a.portable_components = nc
  guard num_entries > 0 else { return false }
  let compressed = b.u8()
  guard !b.failed else { return false }
  if compressed > 0 {
    guard decode_symbols(num_values, nc, b, data) else { return false }
  } else {
    let num_bytes = b.u8()
    guard !b.failed else { return false }
    guard num_bytes <= 4 else { return false }
    guard b.remaining() >= 0 &&
      b.remaining().to_int64() >= num_bytes.to_int64() * num_values.to_int64() else {
      return false
    }
    for i in 0..<num_values {
      let mut v = 0
      for k in 0..<num_bytes {
        v = v | (b.u8() << (8 * k))
      }
      data[i] = v
    }
  }
  let positive = match scheme {
    Some(s) => s.transform.corrections_positive()
    None => false
  }
  if num_values > 0 && !positive {
    for i in 0..<num_values {
      let v = data[i]
      data[i] = if (v & 1) == 0 {
        (v.reinterpret_as_uint() >> 1).reinterpret_as_int()
      } else {
        -(v.reinterpret_as_uint() >> 1).reinterpret_as_int() - 1
      }
    }
  }
  if scheme is Some(s) {
    guard s.decode_data(b) else { return false }
    if num_values > 0 {
      guard s.compute(data, num_values, nc, points) else { return false }
    }
  }
  true
}

///|
fn Decoder::decode_portable(
  self : Decoder,
  sd : SequentialDecoder,
  points : Array[Int32],
) -> Bool {
  let a = self.attributes[sd.att]
  let bytes = points.length().to_int64() * a.stride().to_int64()
  guard bytes <= MAX_ATTRIBUTE_BYTES.to_int64() else { return false }
  a.values = FixedArray::make(bytes.to_int(), b'\x00')
  a.size = points.length()
  if sd.kind != SEQUENTIAL_GENERIC {
    return self.decode_integer_values(sd, points)
  }
  let b = self.b
  let n = bytes.to_int()
  guard b.has(n) else { return false }
  let base = b.head()
  for i in 0..<n {
    a.values[i] = b.data[base + i]
  }
  b.pos += n
  true
}

///|
fn Decoder::decode_transform_data(
  self : Decoder,
  sd : SequentialDecoder,
) -> Bool {
  let b = self.b
  let a = self.attributes[sd.att]
  match sd.kind {
    SEQUENTIAL_QUANTIZATION => {
      let nc = if a.portable is Some(_) {
        a.portable_components
      } else {
        a.num_components
      }
      guard b.has(4 * nc) else { return false }
      sd.min_values = FixedArray::makei(nc, fn(_) { b.f32() })
      sd.range = b.f32()
      guard !b.failed else { return false }
      let bits = b.u8()
      guard !b.failed else { return false }
      guard bits >= 1 && bits <= 30 else { return false }
      sd.bits = bits
    }
    SEQUENTIAL_NORMALS => {
      sd.bits = b.u8()
      guard !b.failed else { return false }
    }
    _ => ()
  }
  true
}

///|
/// `TransformAttributeToOriginalFormat`: the attribute's values from its portable ones.
fn Decoder::store_values(self : Decoder, sd : SequentialDecoder) -> Bool {
  let a = self.attributes[sd.att]
  guard sd.kind != SEQUENTIAL_GENERIC else { return true }
  guard a.portable is Some(src) else { return false }
  let out = a.values
  let nc = a.num_components
  let count = a.size * nc
  match sd.kind {
    SEQUENTIAL_INTEGER => {
      let len = data_type_length(a.data_type)
      guard a.data_type <= 6 && count <= src.length() else { return false }
      for i in 0..<count {
        let v = src[i]
        for k in 0..<len {
          out[i * len + k] = (v >> (8 * k)).to_byte()
        }
      }
    }
    SEQUENTIAL_QUANTIZATION => {
      let max_quantized = (1 << sd.bits) - 1
      let delta = sd.range / Float::from_int(max_quantized)
      guard count <= src.length() && nc <= sd.min_values.length() else {
        return false
      }
      for i in 0..<count {
        let value = Float::from_int(src[i]) * delta + sd.min_values[i % nc]
        store_u32(out, 4 * i, value.reinterpret_as_int())
      }
    }
    _ => {
      let tb = Toolbox::new()
      guard tb.set_bits(sd.bits) else { return false }
      guard 2 * a.size <= src.length() else { return false }
      let v = FixedArray::make(3, (0.0 : Float))
      for i in 0..<a.size {
        tb.unit_vector(src[2 * i], src[2 * i + 1], v)
        for k in 0..<3 {
          store_u32(out, 12 * i + 4 * k, v[k].reinterpret_as_int())
        }
      }
    }
  }
  true
}

///|
/// `SequentialAttributeDecodersController::DecodeAttributes`.
fn Decoder::decode_attributes(self : Decoder, d : AttributesDecoder) -> Bool {
  guard d.sequencer.generate(self.faces) is Some(points) else { return false }
  for att in d.ids {
    guard d.sequencer.mapping(self.faces, self.num_points) is Some(map) else {
      return false
    }
    self.attributes[att].map = map
  }
  for sd in d.decoders {
    guard self.decode_portable(sd, points) else { return false }
  }
  for sd in d.decoders {
    guard self.decode_transform_data(sd) else { return false }
  }
  for sd in d.decoders {
    guard self.store_values(sd) else { return false }
  }
  true
}
