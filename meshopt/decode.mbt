// Ported from meshoptimizer 1.3.0: MIT License, Copyright (c) 2016-2026 Arseny Kapoulkine. See NOTICE.

///|
/// A compressed buffer view's `mode` (the extension's strings): `Attributes` the vertex
/// codec, `Triangles` the index codec, `Indices` the index sequence codec.
pub(all) enum Mode {
  Attributes
  Triangles
  Indices
}

///|
/// The mode named by the extension's string ("ATTRIBUTES", "TRIANGLES", "INDICES").
pub fn Mode::from_string(s : String) -> Mode? {
  match s {
    "ATTRIBUTES" => Some(Attributes)
    "TRIANGLES" => Some(Triangles)
    "INDICES" => Some(Indices)
    _ => None
  }
}

///|
/// A compressed buffer view's `filter`, applied to decoded attributes: `NoFilter`
/// ("NONE"), `Octahedral`, `Quaternion`, `Exponential` and `Color`.
pub(all) enum Filter {
  NoFilter
  Octahedral
  Quaternion
  Exponential
  Color
}

///|
/// The filter named by the extension's string ("NONE", "OCTAHEDRAL", "QUATERNION",
/// "EXPONENTIAL", "COLOR").
pub fn Filter::from_string(s : String) -> Filter? {
  match s {
    "NONE" => Some(NoFilter)
    "OCTAHEDRAL" => Some(Octahedral)
    "QUATERNION" => Some(Quaternion)
    "EXPONENTIAL" => Some(Exponential)
    "COLOR" => Some(Color)
    _ => None
  }
}

///|
/// Whether `size` bytes per element suit `mode` and `filter`, as the extension requires:
/// attributes a multiple of 4 up to 256 bytes (8 for quaternions, 4 or 8 for octahedral
/// and color filters), indices 2 or 4 bytes; filters only on attributes.
fn valid_layout(
  count : Int32,
  size : Int32,
  mode : Mode,
  filter : Filter,
) -> Bool {
  match mode {
    Attributes =>
      size > 0 &&
      size <= 256 &&
      size % 4 == 0 &&
      (match filter {
        NoFilter | Exponential => true
        Octahedral | Color => size == 4 || size == 8
        Quaternion => size == 8
      })
    Triangles =>
      (size == 2 || size == 4) && count % 3 == 0 && filter is NoFilter
    Indices => (size == 2 || size == 4) && filter is NoFilter
  }
}

///|
/// Decodes `count` elements of `size` bytes from `source[source_offset:source_offset +
/// source_length]` into the start of `target`, then applies `filter`, as meshoptimizer's
/// `MeshoptDecoder.decodeGltfBuffer` does. Returns false when the input is malformed or
/// does not fit (where meshoptimizer throws or asserts); `target` is then left partly written.
pub fn decode_gltf_buffer(
  target : FixedArray[Byte],
  count : Int32,
  size : Int32,
  source : FixedArray[Byte],
  source_offset : Int32,
  source_length : Int32,
  mode : Mode,
  filter : Filter,
) -> Bool {
  if count < 0 ||
    source_offset < 0 ||
    source_length < 0 ||
    source_offset > source.length() - source_length ||
    !valid_layout(count, size, mode, filter) ||
    count.to_int64() * size.to_int64() > target.length().to_int64() {
    return false
  }
  let end = source_offset + source_length
  match mode {
    Attributes => {
      if !decode_vertex_buffer(target, count, size, source, source_offset, end) {
        return false
      }
      match filter {
        NoFilter => ()
        Octahedral =>
          if size == 4 {
            filter_oct8(target, count)
          } else {
            filter_oct16(target, count)
          }
        Quaternion => filter_quat(target, count)
        Exponential => filter_exp(target, count * (size / 4))
        Color =>
          if size == 4 {
            filter_color8(target, count)
          } else {
            filter_color16(target, count)
          }
      }
      true
    }
    Triangles =>
      decode_index_buffer(target, count, size, source, source_offset, end)
    Indices =>
      decode_index_sequence(target, count, size, source, source_offset, end)
  }
}
