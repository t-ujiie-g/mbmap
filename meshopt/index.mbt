// Ported from meshoptimizer 1.3.0 (src/indexcodec.cpp): MIT License, Copyright (c) 2016-2026
// Arseny Kapoulkine. See NOTICE.

///|
const INDEX_HEADER : Int32 = 0xe0

///|
const SEQUENCE_HEADER : Int32 = 0xd0

///|
/// `decodeVByte`: a 32-bit value in up to 5 groups of 7 bits, `at[0]` advanced past it.
fn decode_vbyte(source : FixedArray[Byte], at : FixedArray[Int32]) -> Int32 {
  let mut data = at[0]
  let lead = source[data].to_int()
  data += 1
  if lead < 128 {
    at[0] = data
    return lead
  }
  let mut result = lead & 127
  let mut shift = 7
  for _ in 0..<4 {
    let group = source[data].to_int()
    data += 1
    result = result | ((group & 127) << shift)
    shift += 7
    if group < 128 {
      break
    }
  }
  at[0] = data
  result
}

///|
fn unzigzag32(v : Int32) -> Int32 {
  (v.reinterpret_as_uint() >> 1).reinterpret_as_int() ^ ((v & 1).lnot() + 1)
}

///|
fn write_index(
  target : FixedArray[Byte],
  i : Int32,
  index_size : Int32,
  v : Int32,
) -> Unit {
  if index_size == 2 {
    target[i * 2] = v.to_byte()
    target[i * 2 + 1] = (v >> 8).to_byte()
  } else {
    target[i * 4] = v.to_byte()
    target[i * 4 + 1] = (v >> 8).to_byte()
    target[i * 4 + 2] = (v >> 16).to_byte()
    target[i * 4 + 3] = (v >> 24).to_byte()
  }
}

///|
/// `meshopt_decodeIndexBuffer` on `source[start:end]`: `index_count` (a multiple of 3)
/// indices of `index_size` (2 or 4) bytes into `target`.
fn decode_index_buffer(
  target : FixedArray[Byte],
  index_count : Int32,
  index_size : Int32,
  source : FixedArray[Byte],
  start : Int32,
  end : Int32,
) -> Bool {
  let triangles = index_count / 3
  // header, a code byte per triangle and the 16-byte codeaux table
  if end - start - 17 < triangles {
    return false
  }
  if (source[start].to_int() & 0xf0) != INDEX_HEADER {
    return false
  }
  let version = source[start].to_int() & 0x0f
  if version > 1 {
    return false
  }
  let edges = FixedArray::make(32, -1)
  let vertices = FixedArray::make(16, -1)
  let mut edge_offset = 0
  let mut vertex_offset = 0
  let mut next = 0
  let mut last = 0
  let fecmax = if version >= 1 { 13 } else { 15 }
  let code_start = start + 1
  // each triangle reads at most 16 bytes of data: a codeaux byte and 5 per free index
  let data_safe_end = end - 16
  let codeaux_table = data_safe_end
  let at : FixedArray[Int32] = [code_start + triangles]
  let mut out = 0
  for t in 0..<triangles {
    let codetri = source[code_start + t].to_int()
    if codetri < 0xf0 {
      let fe = codetri >> 4
      let e = (edge_offset - 1 - fe) & 15
      let a = edges[e * 2]
      let b = edges[e * 2 + 1]
      let fec = codetri & 15
      let c = if fec < fecmax {
        let c = if fec == 0 {
          next
        } else {
          vertices[(vertex_offset - 1 - fec) & 15]
        }
        let fec0 = if fec == 0 { 1 } else { 0 }
        next += fec0
        vertices[vertex_offset] = c
        vertex_offset = (vertex_offset + fec0) & 15
        c
      } else {
        if at[0] > data_safe_end {
          return false
        }
        // fec 13 and 14 are -1 and +1 from the last free index
        last = if fec != 15 {
          last + (fec * 2 - 27)
        } else {
          last + unzigzag32(decode_vbyte(source, at))
        }
        vertices[vertex_offset] = last
        vertex_offset = (vertex_offset + 1) & 15
        last
      }
      edges[edge_offset * 2] = c
      edges[edge_offset * 2 + 1] = b
      edge_offset = (edge_offset + 1) & 15
      edges[edge_offset * 2] = a
      edges[edge_offset * 2 + 1] = c
      edge_offset = (edge_offset + 1) & 15
      write_index(target, out, index_size, a)
      write_index(target, out + 1, index_size, b)
      write_index(target, out + 2, index_size, c)
    } else {
      let mut a = 0
      let mut b = 0
      let mut c = 0
      let mut push_b = 0
      let mut push_c = 0
      if codetri < 0xfe {
        let codeaux = source[codeaux_table + (codetri & 15)].to_int()
        let feb = codeaux >> 4
        let fec = codeaux & 15
        a = next
        next += 1
        b = if feb == 0 { next } else { vertices[(vertex_offset - feb) & 15] }
        push_b = if feb == 0 { 1 } else { 0 }
        next += push_b
        c = if fec == 0 { next } else { vertices[(vertex_offset - fec) & 15] }
        push_c = if fec == 0 { 1 } else { 0 }
        next += push_c
      } else {
        if at[0] > data_safe_end {
          return false
        }
        let codeaux = source[at[0]].to_int()
        at[0] = at[0] + 1
        let fea = if codetri == 0xfe { 0 } else { 15 }
        let feb = codeaux >> 4
        let fec = codeaux & 15
        if codeaux == 0 {
          next = 0
        }
        if fea == 0 {
          a = next
          next += 1
        }
        if feb == 0 {
          b = next
          next += 1
        } else {
          b = vertices[(vertex_offset - feb) & 15]
        }
        if fec == 0 {
          c = next
          next += 1
        } else {
          c = vertices[(vertex_offset - fec) & 15]
        }
        if fea == 15 {
          last = last + unzigzag32(decode_vbyte(source, at))
          a = last
        }
        if feb == 15 {
          last = last + unzigzag32(decode_vbyte(source, at))
          b = last
        }
        if fec == 15 {
          last = last + unzigzag32(decode_vbyte(source, at))
          c = last
        }
        push_b = if feb == 0 || feb == 15 { 1 } else { 0 }
        push_c = if fec == 0 || fec == 15 { 1 } else { 0 }
      }
      write_index(target, out, index_size, a)
      write_index(target, out + 1, index_size, b)
      write_index(target, out + 2, index_size, c)
      vertices[vertex_offset] = a
      vertex_offset = (vertex_offset + 1) & 15
      vertices[vertex_offset] = b
      vertex_offset = (vertex_offset + push_b) & 15
      vertices[vertex_offset] = c
      vertex_offset = (vertex_offset + push_c) & 15
      edges[edge_offset * 2] = b
      edges[edge_offset * 2 + 1] = a
      edge_offset = (edge_offset + 1) & 15
      edges[edge_offset * 2] = c
      edges[edge_offset * 2 + 1] = b
      edge_offset = (edge_offset + 1) & 15
      edges[edge_offset * 2] = a
      edges[edge_offset * 2 + 1] = c
      edge_offset = (edge_offset + 1) & 15
    }
    out += 3
  }
  at[0] == data_safe_end
}

///|
/// `meshopt_decodeIndexSequence` on `source[start:end]`: `index_count` indices of
/// `index_size` (2 or 4) bytes into `target`.
fn decode_index_sequence(
  target : FixedArray[Byte],
  index_count : Int32,
  index_size : Int32,
  source : FixedArray[Byte],
  start : Int32,
  end : Int32,
) -> Bool {
  // header, a byte per index and a 4-byte tail
  if end - start - 5 < index_count {
    return false
  }
  if (source[start].to_int() & 0xf0) != SEQUENCE_HEADER {
    return false
  }
  if (source[start].to_int() & 0x0f) > 1 {
    return false
  }
  let data_safe_end = end - 4
  let at : FixedArray[Int32] = [start + 1]
  let mut last0 = 0
  let mut last1 = 0
  for i in 0..<index_count {
    // an index reads at most 5 bytes, which the 4-byte tail leaves room for
    if at[0] >= data_safe_end {
      return false
    }
    let v = decode_vbyte(source, at)
    let d = unzigzag32((v.reinterpret_as_uint() >> 1).reinterpret_as_int())
    let index = if (v & 1) == 0 {
      last0 = last0 + d
      last0
    } else {
      last1 = last1 + d
      last1
    }
    write_index(target, i, index_size, index)
  }
  at[0] == data_safe_end
}
