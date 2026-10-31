///|
/// The tile as bytes for the display worker (docs/FORMATS.md, "Columnar
/// tile"), with properties from `table`'s rows.
pub fn encode_tile(d : TileData, table : @geom.Table) -> Bytes {
  let w = @core.ByteWriter::new()
  let columns = table.columns.filter(c => {
    d.rows.iter().any(row => c.values[row] is Some(_))
  })
  w.u32(d.types.length())
  w.u32(d.point_ends.length())
  w.u32(d.xy.length() / 2)
  w.u32(columns.length())
  for t in d.types {
    w.u8(t)
  }
  w.pad4()
  for e in d.ring_ends {
    w.u32(e)
  }
  for e in d.point_ends {
    w.u32(e)
  }
  for v in d.xy {
    w.i16(v)
  }
  w.pad4()
  for c in columns {
    w.utf8(c.name)
  }
  for c in columns {
    for row in d.rows {
      @geom.write_prop(w, c.values[row])
    }
  }
  w.to_bytes()
}
