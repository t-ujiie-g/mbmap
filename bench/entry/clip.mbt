///|
/// Paths from `words`, i32s from `at`: a path count, then per path its point
/// count and x, y pairs. Returns the paths and the next index.
fn read_paths(
  words : Array[Int32],
  at : Int32,
) -> (Array[Array[@clipper.Point64]], Int32) {
  let n = words[at]
  let mut i = at + 1
  let paths = []
  for _ in 0..<n {
    let len = words[i]
    i += 1
    let path : Array[@clipper.Point64] = []
    for _ in 0..<len {
      path.push({ x: words[i].to_int64(), y: words[i + 1].to_int64(), })
      i += 2
    }
    paths.push(path)
  }
  (paths, i)
}

///|
/// Runs Clipper64 on input i32s (subjects, open subjects, clips, as in
/// `read_paths`) with ClipType `op` (1-4) and FillRule `fill` (0-3), as
/// i32s: closed solution paths in `read_paths` form (or with `tree`, the
/// solution tree in preorder), then open ones.
fn clip_words(
  words : Array[Int32],
  op : Int32,
  fill : Int32,
  tree~ : Bool = false,
) -> Array[Int32] {
  let (subjects, at) = read_paths(words, 0)
  let (open, at) = read_paths(words, at)
  let (clips, _) = read_paths(words, at)
  let c = @clipper.Clipper64::new()
  c.add_subject(subjects)
  c.add_open_subject(open)
  c.add_clip(clips)
  let ct : @clipper.ClipType = match op {
    1 => Intersection
    2 => Union
    3 => Difference
    _ => Xor
  }
  let fr : @clipper.FillRule = match fill {
    0 => EvenOdd
    1 => NonZero
    2 => Positive
    _ => Negative
  }
  let out = []
  let put_path = (p : Array[@clipper.Point64]) => {
    out.push(p.length())
    for pt in p {
      out.push(pt.x.to_int())
      out.push(pt.y.to_int())
    }
  }
  let put_paths = (paths : Array[Array[@clipper.Point64]]) => {
    out.push(paths.length())
    for p in paths {
      put_path(p)
    }
  }
  if tree {
    // Preorder: each node's child count, then per child its polygon and
    // subtree.
    fn put_node(
      n : @clipper.PolyPath64,
      put_path : (Array[@clipper.Point64]) -> Unit,
      out : Array[Int32],
    ) -> Unit {
      out.push(n.children.length())
      for child in n.children {
        put_path(child.polygon)
        put_node(child, put_path, out)
      }
    }
    match c.execute_tree(ct, fr) {
      None => out.push(-1)
      Some((root, open)) => {
        put_node(root, put_path, out)
        put_paths(open)
      }
    }
  } else {
    match c.execute(ct, fr) {
      None => out.push(-1)
      Some((closed, open)) => {
        put_paths(closed)
        put_paths(open)
      }
    }
  }
  out
}

///|
fn words_of(bytes : BytesView) -> Array[Int32] {
  Array::makei(bytes.length() / 4, i => {
    bytes[i * 4].to_int() |
    (bytes[i * 4 + 1].to_int() << 8) |
    (bytes[i * 4 + 2].to_int() << 16) |
    (bytes[i * 4 + 3].to_int() << 24)
  })
}

///|
/// Offsets input i32s (paths as in `read_paths`) by `delta` with JoinType
/// `join` (0 Square, 1 Bevel, 2 Round, 3 Miter) and EndType `end` (0 Polygon,
/// 1 Joined, 2 Butt, 3 Square, 4 Round), as `read_paths` i32s.
fn offset_words(
  words : Array[Int32],
  delta : Double,
  join : Int32,
  end : Int32,
  miter_limit : Double,
  arc_tolerance : Double,
) -> Array[Int32] {
  let (paths, _) = read_paths(words, 0)
  let jt : @clipper.JoinType = match join {
    0 => Square
    1 => Bevel
    2 => Round
    _ => Miter
  }
  let et : @clipper.EndType = match end {
    0 => Polygon
    1 => Joined
    2 => Butt
    3 => Square
    _ => Round
  }
  let out = []
  let result = @clipper.inflate_paths(
    paths,
    delta,
    jt,
    et,
    miter_limit~,
    arc_tolerance~,
  )
  out.push(result.length())
  for p in result {
    out.push(p.length())
    for pt in p {
      out.push(pt.x.to_int())
      out.push(pt.y.to_int())
    }
  }
  out
}
