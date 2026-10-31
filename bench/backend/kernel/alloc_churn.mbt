// Allocation-heavy kernel: builds one Array of boxed points per "feature",
// like a naive geometry decoder would. Measures allocator / GC throughput,
// which differs most between backends (RC + TLSF on wasm, host GC elsewhere).

///|
priv struct Point {
  x : Int32
  y : Int32
}

///|
/// Builds `features` rings of `ring` points and returns a checksum.
pub fn alloc_churn(features : Int32, ring : Int32) -> Int32 {
  let mut sum = 0
  for f in 0..<features {
    let pts : Array[Point] = []
    for i in 0..<ring {
      pts.push({ x: i ^ f, y: i + f, })
    }
    let p = pts[ring / 2]
    sum = sum + p.x - p.y + pts.length()
  }
  sum
}
