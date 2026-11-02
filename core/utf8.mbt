///|
/// `b` decoded as UTF-8, each maximal malformed subpart replaced by U+FFFD (as
/// `@utf8.decode_lossy` and the WHATWG decoder do); a BOM is kept.
pub fn utf8_lossy(b : BytesView) -> String {
  decode_lossy(b)
}
