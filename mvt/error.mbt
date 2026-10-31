///|
/// Malformed vector tile. `pos` is the absolute byte offset in the tile.
pub(all) suberror MvtError {
  Malformed(@pbf.PbfError)
  InvalidCommand(pos~ : Int32, Int32)
  IndexOutOfRange(pos~ : Int32, Int32)
  OddTagCount(pos~ : Int32)
} derive(Debug, Eq)
