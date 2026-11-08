// Ported from Draco 1.5.7 (compression/attributes/kd_tree_attributes_decoder.cc,
// compression/point_cloud/point_cloud_kd_tree_decoder.cc, point_cloud_sequential_decoder.cc,
// algorithms/float_points_tree_decoder.cc, quantize_points_3.h): Apache License 2.0, Copyright
// 2016 The Draco Authors. See NOTICE.

///|
/// Draco's `DT_INT8` to `DT_UINT32` numbers: 1 INT8, 2 UINT8, 3 INT16, 4 UINT16, 5 INT32, 6 UINT32.
fn is_signed_type(dt : Int32) -> Bool {
  dt == 1 || dt == 3 || dt == 5
}

///|
fn is_unsigned_type(dt : Int32) -> Bool {
  dt == 2 || dt == 4 || dt == 6
}

///|
/// `ConvertSymbolToSignedInt`.
fn signed_of_symbol(v : Int32) -> Int32 {
  let half = (v.reinterpret_as_uint() >> 1).reinterpret_as_int()
  if (v & 1) == 0 {
    half
  } else {
    -half - 1
  }
}

///|
/// `PointAttribute::Reset(n)` with an identity mapping: false past `MAX_POINTS` or
/// `MAX_ATTRIBUTE_BYTES`.
fn Attribute::reset(self : Attribute, n : Int64) -> Bool {
  let bytes = n * self.stride().to_int64()
  guard n >= 0L &&
    n <= MAX_POINTS.to_int64() &&
    bytes <= MAX_ATTRIBUTE_BYTES.to_int64() else {
    return false
  }
  self.values = FixedArray::make(bytes.to_int(), b'\x00')
  self.size = n.to_int()
  self.map = None
  true
}

///|
/// A float attribute's quantization (`AttributeQuantizationTransform`'s parameters).
priv struct Quantization {
  min_values : FixedArray[Float]
  range : Float
  bits : Int32
}

///|
/// `KdTreeAttributesDecoder::DecodeAttributes`: its portable attributes, the data of their
/// transforms, then the attributes in their own types.
fn Decoder::decode_kd_attributes(self : Decoder, d : AttributesDecoder) -> Bool {
  let b = self.b
  guard b.version >= bitstream(2, 3) else { return self.decode_legacy_kd(d) }
  let level = b.u8()
  guard !b.failed else { return false }
  let n = self.num_points
  let targets = []
  let mut dim = 0
  let mut signed_components = 0
  for att in d.ids {
    let a = self.attributes[att]
    guard a.reset(n.to_int64()) else { return false }
    let dt = a.data_type
    if dt == DT_FLOAT32 {
      guard n.to_int64() * a.num_components.to_int64() * 4L <=
        MAX_ATTRIBUTE_BYTES.to_int64() else {
        return false
      }
      let ints = FixedArray::make(n * a.num_components, 0)
      a.portable = Some(ints)
      a.portable_components = a.num_components
      targets.push({
        bytes: [],
        ints,
        portable: true,
        offset: dim,
        data_size: 4,
        nc: a.num_components,
        size: n,
      })
    } else if is_signed_type(dt) || is_unsigned_type(dt) {
      if is_signed_type(dt) {
        signed_components += a.num_components
      }
      targets.push({
        bytes: a.values,
        ints: [],
        portable: false,
        offset: dim,
        data_size: data_type_length(dt),
        nc: a.num_components,
        size: n,
      })
    } else {
      return false
    }
    dim += a.num_components
  }
  guard level <= 6 else { return false }
  let out = KdOut::to_attributes(targets)
  guard decode_kd_points(b, level, dim, n.reinterpret_as_uint(), out) &&
    out.count == n.to_int64() else {
    return false
  }
  let quantizations = []
  for att in d.ids {
    let a = self.attributes[att]
    if a.data_type == DT_FLOAT32 {
      let nc = a.num_components
      guard b.has(4 * nc) else { return false }
      let min_values = FixedArray::makei(nc, fn(_) { b.f32() })
      let range = b.f32()
      guard !b.failed else { return false }
      let bits = b.u8()
      guard !b.failed && bits >= 1 && bits <= 30 else { return false }
      quantizations.push({ min_values, range, bits, })
    }
  }
  let min_signed = FixedArray::make(signed_components, 0)
  for i in 0..<signed_components {
    let v = b.varint()
    guard !b.failed else { return false }
    min_signed[i] = signed_of_symbol(v)
  }
  self.kd_to_original(d, quantizations, min_signed)
}

///|
/// `TransformAttributesToOriginalFormat`: signed values from their offsets, floats dequantized.
fn Decoder::kd_to_original(
  self : Decoder,
  d : AttributesDecoder,
  quantizations : Array[Quantization],
  min_signed : FixedArray[Int32],
) -> Bool {
  let mut q = 0
  let mut s = 0
  for att in d.ids {
    let a = self.attributes[att]
    let nc = a.num_components
    if is_signed_type(a.data_type) {
      let len = data_type_length(a.data_type)
      for i in 0..<(a.size * nc) {
        let mut u = 0
        for k in 0..<len {
          u = u | (a.values[i * len + k].to_int() << (8 * k))
        }
        guard u >= 0 else { return false }
        let v = u + min_signed[s + i % nc]
        for k in 0..<len {
          a.values[i * len + k] = (v >> (8 * k)).to_byte()
        }
      }
      s += nc
    } else if a.data_type == DT_FLOAT32 {
      let t = quantizations[q]
      q += 1
      guard a.portable is Some(src) else { return false }
      let delta = t.range / Float::from_int((1 << t.bits) - 1)
      for i in 0..<(a.size * nc) {
        let value = Float::from_int(src[i]) * delta
        let value = value + t.min_values[i % nc]
        store_u32(a.values, 4 * i, value.reinterpret_as_int())
      }
    }
  }
  true
}

///|
/// The kd-tree attributes of bitstreams before 2.3 (`DecodeDataNeededByPortableTransforms`):
/// three float coordinates by `FloatPointsTreeDecoder`, or integers by the kd-tree.
fn Decoder::decode_legacy_kd(self : Decoder, d : AttributesDecoder) -> Bool {
  let b = self.b
  let mut dim = 0
  for att in d.ids {
    let a = self.attributes[att]
    guard data_type_length(a.data_type) <= 4 else { return false }
    dim += a.num_components
  }
  let first = self.attributes[d.ids[0]]
  first.map = None
  let encoding = b.u8()
  guard !b.failed else { return false }
  if encoding == 0 {
    guard d.ids.length() == 1 && first.num_components == 3 else { return false }
    let _ = b.u8()
    guard !b.failed else { return false }
    let num_points = b.u32().reinterpret_as_uint()
    guard !b.failed else { return false }
    guard first.reset(num_points.to_uint64().reinterpret_as_int64()) else {
      return false
    }
    decode_float_tree(b, first, num_points)
  } else if encoding == 1 {
    let level = b.u8()
    guard !b.failed && level <= 6 else { return false }
    let num_points = b.u32().reinterpret_as_uint()
    guard !b.failed else { return false }
    let targets = []
    let mut offset = 0
    for att in d.ids {
      let a = self.attributes[att]
      guard a.reset(num_points.to_uint64().reinterpret_as_int64()) else {
        return false
      }
      targets.push({
        bytes: a.values,
        ints: [],
        portable: false,
        offset,
        data_size: data_type_length(a.data_type),
        nc: a.num_components,
        size: a.size,
      })
      offset += a.num_components
    }
    decode_kd_points(b, level, dim, 0xffffffffU, KdOut::to_attributes(targets))
  } else {
    false
  }
}

///|
/// `FloatPointsTreeDecoder::DecodePointCloud` into `att` (its first `size` points): the points
/// quantized around zero, then `DequantizePoints3`, each stored as the first bytes of its three
/// floats that the attribute's value takes.
fn decode_float_tree(
  b : Buffer,
  att : Attribute,
  header_points : UInt32,
) -> Bool {
  let version = b.u32()
  guard !b.failed else { return false }
  if version == 3 {
    let encoding = b.i8()
    guard !b.failed && encoding == 1 else { return false }
  } else {
    guard version == 2 else { return false }
  }
  let bits = b.u32().reinterpret_as_uint()
  guard !b.failed && bits <= 31 else { return false }
  let range = b.f32()
  guard !b.failed else { return false }
  let num_points = b.u32().reinterpret_as_uint()
  guard !b.failed else { return false }
  guard header_points == 0 || num_points == header_points else { return false }
  let level = b.u32().reinterpret_as_uint()
  guard !b.failed && level <= 6 else { return false }
  let out = KdOut::collecting(num_points.to_uint64().reinterpret_as_int64())
  if num_points > 0 {
    guard num_points <= MAX_POINTS.reinterpret_as_uint() else { return false }
    let _ = decode_kd_points(b, level.reinterpret_as_int(), 3, 0xffffffffU, out)
    guard !out.over else { return false }
    b.failed = false
  }
  guard out.count == out.limit else { return false }
  let max = (1U << bits.reinterpret_as_int()) - 1
  let delta = if max > 0 {
    range / Float::from_int(max.reinterpret_as_int())
  } else {
    1.0
  }
  let stride = att.stride()
  let floats = FixedArray::make(12, b'\x00')
  let count = if out.count < att.size.to_int64() {
    out.count.to_int()
  } else {
    att.size
  }
  for i in 0..<count {
    for c in 0..<3 {
      let q = (out.collected[3 * i + c] - max).reinterpret_as_int()
      store_u32(
        floats,
        4 * c,
        (Float::from_int(q) * delta).reinterpret_as_int(),
      )
    }
    for k in 0..<stride {
      att.values[i * stride + k] = floats[k]
    }
  }
  true
}

///|
/// `PointCloudDecoder::Decode` after the header, with `PointCloudSequentialDecoder` (`encoding` 0)
/// or `PointCloudKdTreeDecoder` (1).
fn Decoder::decode_point_cloud(self : Decoder, encoding : Int32) -> Bool {
  let b = self.b
  let num_points = b.u32()
  guard !b.failed && num_points >= 0 && num_points <= MAX_POINTS else {
    return false
  }
  self.num_points = num_points
  self.kd = encoding == 1
  self.decode_point_attributes()
}
