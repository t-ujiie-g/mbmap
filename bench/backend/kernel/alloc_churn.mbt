///|
priv struct Point {
  x : Int32
  y : Int32
}

///|
/// Builds `features` arrays of `ring` boxed points and returns a checksum.
/// Exists to stress the allocator / GC, so it allocates on purpose.
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
