// Ported from meshoptimizer 1.3.0 (src/vertexcodec.cpp): MIT License, Copyright (c) 2016-2026
// Arseny Kapoulkine. See NOTICE.

///|
const VERTEX_HEADER : Int32 = 0xa0

///|
const VERTEX_BLOCK_SIZE_BYTES : Int32 = 8192

///|
const VERTEX_BLOCK_MAX_SIZE : Int32 = 256

///|
const BYTE_GROUP_SIZE : Int32 = 16

///|
/// Bytes a byte group may read (16 deltas of 4 bits with all 16 sentinels), checked
/// before each group so a group's reads stay inside the input.
const BYTE_GROUP_DECODE_LIMIT : Int32 = 24

///|
/// Bits per delta for a group's 2-bit header: v0 headers index 0..3, v1 headers
/// index 4 + control (0 or 1) onwards, as `decodeBytesSimd`'s `hshift`.
let group_bits : FixedArray[Int32] = [0, 2, 4, 8, 0, 1, 2, 4, 8]

///|
fn vertex_block_size(vertex_size : Int32) -> Int32 {
  let result = (VERTEX_BLOCK_SIZE_BYTES / vertex_size) &
    (BYTE_GROUP_SIZE - 1).lnot()
  if result < VERTEX_BLOCK_MAX_SIZE {
    result
  } else {
    VERTEX_BLOCK_MAX_SIZE
  }
}

///|
/// `meshopt_decodeVertexBuffer` on `source[start:end]` into `target`; `vertex_size` is a
/// multiple of 4 up to 256 and `target` holds `count * vertex_size` bytes.
fn decode_vertex_buffer(
  target : FixedArray[Byte],
  count : Int32,
  vertex_size : Int32,
  source : FixedArray[Byte],
  start : Int32,
  end : Int32,
) -> Bool {
  if end - start < 1 {
    return false
  }
  let header = source[start].to_int()
  if (header & 0xf0) != VERTEX_HEADER {
    return false
  }
  let version = header & 0x0f
  if version > 1 {
    return false
  }
  let tail_size = vertex_size + (if version == 0 { 0 } else { vertex_size / 4 })
  let tail_min = if version == 0 { 32 } else { 24 }
  let tail_pad = if tail_size < tail_min { tail_min } else { tail_size }
  let mut data = start + 1
  if end - data < tail_pad {
    return false
  }
  let tail = end - tail_size
  let last = FixedArray::make(256, b'\x00')
  for i in 0..<vertex_size {
    last[i] = source[tail + i]
  }
  let buffer = FixedArray::make(VERTEX_BLOCK_MAX_SIZE * 4, b'\x00')
  let block = vertex_block_size(vertex_size)
  let mut offset = 0
  while offset < count {
    let n = if offset + block < count { block } else { count - offset }
    data = decode_vertex_block(
      source,
      data,
      end,
      target,
      offset * vertex_size,
      n,
      vertex_size,
      last,
      buffer,
      tail + vertex_size,
      version,
    )
    if data < 0 {
      return false
    }
    offset += n
  }
  end - data == tail_pad
}

///|
/// `decodeVertexBlockSimd`, writing straight into `target` at `out`: returns where the
/// block's data ends, or -1. Byte streams sit in `buffer` at multiples of the aligned count.
fn decode_vertex_block(
  source : FixedArray[Byte],
  start : Int32,
  end : Int32,
  target : FixedArray[Byte],
  out : Int32,
  vertex_count : Int32,
  vertex_size : Int32,
  last : FixedArray[Byte],
  buffer : FixedArray[Byte],
  channels : Int32,
  version : Int32,
) -> Int32 {
  let aligned = (vertex_count + BYTE_GROUP_SIZE - 1) &
    (BYTE_GROUP_SIZE - 1).lnot()
  let control_size = if version == 0 { 0 } else { vertex_size / 4 }
  let mut data = start
  if end - data < control_size {
    return -1
  }
  let control = data
  data += control_size
  for k = 0; k < vertex_size; k = k + 4 {
    let ctrl_byte = if version == 0 {
      0
    } else {
      source[control + k / 4].to_int()
    }
    for j in 0..<4 {
      let ctrl = (ctrl_byte >> (j * 2)) & 3
      let base = j * aligned
      if ctrl == 3 {
        // The SIMD decoder over-copies a whole aligned run, so it asks for that much.
        if end - data < aligned {
          return -1
        }
        for i in 0..<vertex_count {
          buffer[base + i] = source[data + i]
        }
        data += vertex_count
      } else if ctrl == 2 {
        for i in 0..<vertex_count {
          buffer[base + i] = b'\x00'
        }
      } else {
        let bits = if version == 0 { 0 } else { 4 + ctrl }
        data = decode_bytes(source, data, end, buffer, base, aligned, bits)
        if data < 0 {
          return -1
        }
      }
    }
    let channel = if version == 0 {
      0
    } else {
      source[channels + k / 4].to_int()
    }
    match channel & 3 {
      0 =>
        decode_deltas8(
          buffer,
          aligned,
          target,
          out + k,
          vertex_count,
          vertex_size,
          last,
          k,
        )
      1 =>
        decode_deltas16(
          buffer,
          aligned,
          target,
          out + k,
          vertex_count,
          vertex_size,
          last,
          k,
        )
      2 =>
        decode_deltas_xor(
          buffer,
          aligned,
          target,
          out + k,
          vertex_count,
          vertex_size,
          last,
          k,
          (32 - (channel >> 4)) & 31,
        )
      _ => return -1
    }
  }
  let final_ = out + (vertex_count - 1) * vertex_size
  for i in 0..<vertex_size {
    last[i] = target[final_ + i]
  }
  data
}

///|
/// `decodeBytes`: the 2-bit group headers, then `size` (a multiple of 16) deltas into
/// `buffer` at `base`; `bits` indexes `group_bits`. Returns the end of the data, or -1.
fn decode_bytes(
  source : FixedArray[Byte],
  start : Int32,
  end : Int32,
  buffer : FixedArray[Byte],
  base : Int32,
  size : Int32,
  bits : Int32,
) -> Int32 {
  let header_size = (size / BYTE_GROUP_SIZE + 3) / 4
  if end - start < header_size {
    return -1
  }
  let header = start
  let mut data = start + header_size
  for i = 0; i < size; i = i + BYTE_GROUP_SIZE {
    if end - data < BYTE_GROUP_DECODE_LIMIT {
      return -1
    }
    let group = i / BYTE_GROUP_SIZE
    let h = (source[header + group / 4].to_int() >> (group % 4 * 2)) & 3
    data = decode_bytes_group(
      source,
      data,
      buffer,
      base + i,
      group_bits[bits + h],
    )
  }
  data
}

///|
/// `decodeBytesGroup`: 16 deltas of `bits` bits, a delta of all ones (in 1, 2 and 4 bits)
/// being a sentinel for a byte that follows. The caller checked 24 bytes remain.
fn decode_bytes_group(
  source : FixedArray[Byte],
  data : Int32,
  buffer : FixedArray[Byte],
  out : Int32,
  bits : Int32,
) -> Int32 {
  match bits {
    0 => {
      for m in 0..<16 {
        buffer[out + m] = b'\x00'
      }
      data
    }
    8 => {
      for m in 0..<16 {
        buffer[out + m] = source[data + m]
      }
      data + 16
    }
    _ => {
      let sentinel = (1 << bits) - 1
      let per_byte = 8 / bits
      let mut extra = data + 16 * bits / 8
      for m in 0..<16 {
        let byte = source[data + m / per_byte].to_int()
        // 1-bit deltas run from the low bit up; wider ones from the high bits down.
        let shift = if bits == 1 {
          m % 8
        } else {
          8 - bits - m % per_byte * bits
        }
        let enc = (byte >> shift) & sentinel
        if enc == sentinel {
          buffer[out + m] = source[extra]
          extra += 1
        } else {
          buffer[out + m] = enc.to_byte()
        }
      }
      extra
    }
  }
}

///|
/// Byte deltas (channel 0): zigzag differences from the previous vertex's bytes.
fn decode_deltas8(
  buffer : FixedArray[Byte],
  stride : Int32,
  target : FixedArray[Byte],
  out : Int32,
  vertex_count : Int32,
  vertex_size : Int32,
  last : FixedArray[Byte],
  k : Int32,
) -> Unit {
  for j in 0..<4 {
    let mut p = last[k + j].to_int()
    let mut o = out + j
    for i in 0..<vertex_count {
      let v = buffer[j * stride + i].to_int()
      p = (((v & 1).lnot() + 1) ^ (v >> 1)) + p
      target[o] = p.to_byte()
      p = p & 0xff
      o += vertex_size
    }
  }
}

///|
/// 16-bit deltas (channel 1): zigzag differences of little-endian pairs.
fn decode_deltas16(
  buffer : FixedArray[Byte],
  stride : Int32,
  target : FixedArray[Byte],
  out : Int32,
  vertex_count : Int32,
  vertex_size : Int32,
  last : FixedArray[Byte],
  k : Int32,
) -> Unit {
  for j = 0; j < 4; j = j + 2 {
    let mut p = last[k + j].to_int() | (last[k + j + 1].to_int() << 8)
    let mut o = out + j
    for i in 0..<vertex_count {
      let v = buffer[j * stride + i].to_int() |
        (buffer[(j + 1) * stride + i].to_int() << 8)
      p = ((((v & 1).lnot() + 1) ^ (v >> 1)) + p) & 0xffff
      target[o] = p.to_byte()
      target[o + 1] = (p >> 8).to_byte()
      o += vertex_size
    }
  }
}

///|
/// 32-bit XOR deltas (channel 2): each word rotated left by `rot` and XORed with the
/// previous vertex's.
fn decode_deltas_xor(
  buffer : FixedArray[Byte],
  stride : Int32,
  target : FixedArray[Byte],
  out : Int32,
  vertex_count : Int32,
  vertex_size : Int32,
  last : FixedArray[Byte],
  k : Int32,
  rot : Int32,
) -> Unit {
  let mut p = last[k].to_uint() |
    (last[k + 1].to_uint() << 8) |
    (last[k + 2].to_uint() << 16) |
    (last[k + 3].to_uint() << 24)
  let mut o = out
  for i in 0..<vertex_count {
    let v = buffer[i].to_uint() |
      (buffer[stride + i].to_uint() << 8) |
      (buffer[2 * stride + i].to_uint() << 16) |
      (buffer[3 * stride + i].to_uint() << 24)
    p = ((v << rot) | (v >> ((32 - rot) & 31))) ^ p
    target[o] = p.to_byte()
    target[o + 1] = (p >> 8).to_byte()
    target[o + 2] = (p >> 16).to_byte()
    target[o + 3] = (p >> 24).to_byte()
    o += vertex_size
  }
}
