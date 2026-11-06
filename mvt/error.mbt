///|
/// Malformed vector tile. `pos` is the absolute byte offset in the tile.
#derive(Debug, Eq)
pub(all) suberror MvtError {
  Malformed(@pbf.PbfError)
  InvalidCommand(pos~ : Int32, Int32)
  IndexOutOfRange(pos~ : Int32, Int32)
  OddTagCount(pos~ : Int32)
}

///|
/// A one-line description with the byte offset.
pub fn MvtError::message(self : MvtError) -> String {
  match self {
    Malformed(e) => {
      let (pos, what) = match e {
        UnexpectedEof(pos~) => (pos, "unexpected end")
        VarintTooLong(pos~) => (pos, "varint too long")
        UnsupportedWireType(pos~, _) => (pos, "unsupported wire type")
        LengthOutOfRange(pos~, _) => (pos, "length out of range")
      }
      "malformed protobuf at \{pos}: \{what}"
    }
    InvalidCommand(pos~, c) => "invalid geometry command \{c} at \{pos}"
    IndexOutOfRange(pos~, i) => "tag index \{i} out of range at \{pos}"
    OddTagCount(pos~) => "odd tag count at \{pos}"
  }
}
