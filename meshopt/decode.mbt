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
/// The fewest source bytes for `count` elements of `size` bytes in `mode`: a header, then a byte
/// per triangle and the 16-byte table, a byte per index and the 4-byte tail, or each vertex
/// block's control bytes and the tail.
fn min_source_length(count : Int32, size : Int32, mode : Mode) -> Int64 {
  match mode {
    Triangles => (count / 3).to_int64() + 17L
    Indices => count.to_int64() + 5L
    Attributes => {
      let block = vertex_block_size(size).to_int64()
      let blocks = (count.to_int64() + block - 1L) / block
      let tail = if size < 24 { 24 } else { size }
      1L + blocks * (size / 4).to_int64() + tail.to_int64()
    }
  }
}

///|
/// Whether `source_length` bytes could hold `count` elements of `size` bytes in
/// `mode` and `filter`: callers check it before making room for the output.
pub fn source_fits(
  count : Int32,
  size : Int32,
  source_length : Int32,
  mode : Mode,
  filter : Filter,
) -> Bool {
  count >= 0 &&
  source_length >= 0 &&
  valid_layout(count, size, mode, filter) &&
  source_length.to_int64() >= min_source_length(count, size, mode)
}

///|
/// `MeshoptDecoder.decodeGltfBuffer`: `count` elements of `size` bytes from `source[source_offset:
/// source_offset + source_length]` into the start of `target`, then `filter`. False where
/// meshoptimizer throws or asserts (malformed or too short); `target` is then partly written.
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
    !source_fits(count, size, source_length, mode, filter) ||
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
