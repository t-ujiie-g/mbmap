///|
/// The mesh as docs/FORMATS.md "Draco output" lays it out: a header of u32s, the indices, then
/// each attribute's data padded to four bytes.
pub fn DracoMesh::to_bytes(self : DracoMesh) -> FixedArray[Byte] {
  let n = self.attributes.length()
  let mut size = 12 + 12 * n + 4 * self.indices.length()
  for a in self.attributes {
    size += (a.data.length() + 3) / 4 * 4
  }
  let out = FixedArray::make(size, b'\x00')
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
  out
}
