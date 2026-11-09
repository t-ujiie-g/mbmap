///|
/// The most bytes `DracoMesh::to_bytes` writes by default (the model worker's output cap).
pub const MAX_OUTPUT_BYTES : Int32 = 0x40000000

///|
/// The mesh as docs/FORMATS.md "Draco output" lays it out: a header of u32s, the indices, then
/// each attribute's data padded to four bytes; None past `max_bytes`.
pub fn DracoMesh::to_bytes(
  self : DracoMesh,
  max_bytes~ : Int32 = MAX_OUTPUT_BYTES,
) -> FixedArray[Byte]? {
  let n = self.attributes.length()
  let mut size = 12L +
    12L * n.to_int64() +
    4L * self.indices.length().to_int64()
  for a in self.attributes {
    size += (a.data.length().to_int64() + 3L) / 4L * 4L
  }
  guard size <= max_bytes.to_int64() else { return None }
  let out = FixedArray::make(size.to_int(), b'\x00')
  store_u32(out, 0, self.indices.length() / 3)
  store_u32(out, 4, self.num_points)
  store_u32(out, 8, n)
  for i, a in self.attributes {
    let at = 12 + 12 * i
    store_u32(out, at, a.unique_id)
    out[at + 4] = a.attribute_type.to_byte()
    out[at + 5] = a.data_type.to_byte()
    out[at + 6] = a.num_components.to_byte()
    out[at + 7] = (if a.normalized { 1 } else { 0 }).to_byte()
    store_u32(out, at + 8, a.data.length())
  }
  let mut at = 12 + 12 * n
  for v in self.indices {
    store_u32(out, at, v)
    at += 4
  }
  for a in self.attributes {
    for i, v in a.data {
      out[at + i] = v
    }
    at += (a.data.length() + 3) / 4 * 4
  }
  Some(out)
}
