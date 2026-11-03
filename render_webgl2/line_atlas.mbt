///|
/// Size of the dash texture, as MapLibre's `LineAtlas`: a row (or 15 for
/// round dashes) per pattern, each pattern stretched over the width.
pub const LINE_ATLAS_WIDTH : Int32 = 256

///|
pub const LINE_ATLAS_HEIGHT : Int32 = 512

///|
/// Most numbers a dash pattern may have; longer ones are refused (building a
/// pattern takes time quadratic in its length).
pub const MAX_DASH_PARTS : Int32 = 64

///|
/// Rows above and below a round dash's middle row.
const ROUND_DASH_ROWS : Int32 = 7

///|
/// Where a pattern lies: its middle row `y`, the rows `height` it spans around
/// it and its length `width` (in line widths).
pub struct DashEntry {
  y : Int32
  height : Int32
  width : Double
}

///|
priv struct DashRange {
  mut left : Double
  mut right : Double
  is_dash : Bool
  zero_length : Bool
}

///|
/// A port of MapLibre's `LineAtlas`: dash patterns as signed distance fields
/// (128 at a dash's edge), one byte per pixel, each pattern written once.
pub struct LineAtlas {
  data : FixedArray[Byte]
  priv entries : Array[(Array[Double], Bool, DashEntry?)]
  priv mut next_row : Int32
  priv mut dirty : Bool
}

///|
pub fn LineAtlas::new() -> LineAtlas {
  {
    data: FixedArray::make(LINE_ATLAS_WIDTH * LINE_ATLAS_HEIGHT, b'\x00'),
    entries: [],
    next_row: 0,
    dirty: false,
  }
}

///|
/// The pattern `dasharray` (dash, gap, … in line widths), with round ends when
/// `round`; None once the atlas is full or past `MAX_DASH_PARTS` numbers.
pub fn LineAtlas::dash(
  self : LineAtlas,
  dasharray : Array[Double],
  round : Bool,
) -> DashEntry? {
  if dasharray.length() > MAX_DASH_PARTS {
    return None
  }
  for e in self.entries {
    if e.0 == dasharray && e.1 == round {
      return e.2
    }
  }
  let entry = self.add(dasharray, round)
  self.entries.push((dasharray, round, entry))
  entry
}

///|
/// Whether patterns were added since the last call.
pub fn LineAtlas::take_dirty(self : LineAtlas) -> Bool {
  let d = self.dirty
  self.dirty = false
  d
}

///|
fn ranges_of(dasharray : Array[Double], stretch : Double) -> Array[DashRange] {
  let n = dasharray.length()
  // An odd count joins the first and last dashes seamlessly.
  let left = if n % 2 == 1 { -dasharray[n - 1] * stretch } else { 0.0 }
  let ranges = [
    {
      left,
      right: dasharray[0] * stretch,
      is_dash: true,
      zero_length: dasharray[0] == 0.0,
    },
  ]
  let mut total = dasharray[0]
  for i in 1..<n {
    let left = total * stretch
    total += dasharray[i]
    ranges.push({
      left,
      right: total * stretch,
      is_dash: i % 2 == 0,
      zero_length: dasharray[i] == 0.0,
    })
  }
  ranges
}

///|
fn byte_of(d : Double) -> Byte {
  @cmp.maximum(0.0, @cmp.minimum(255.0, d + 128.0)).to_int().to_byte()
}

///|
/// The range at `x`, moving on as MapLibre does (`x / right > 1`).
fn advance(ranges : Array[DashRange], k : Int32, x : Double) -> Int32 {
  if x / ranges[k].right > 1.0 && k + 1 < ranges.length() {
    k + 1
  } else {
    k
  }
}

///|
fn LineAtlas::add_regular(self : LineAtlas, ranges : Array[DashRange]) -> Unit {
  // Drop empty parts and merge neighbours of the same kind.
  for i = ranges.length() - 1; i >= 0; i = i - 1 {
    let part = ranges[i]
    if part.zero_length {
      ranges.remove(i) |> ignore
    } else if i + 1 < ranges.length() && ranges[i + 1].is_dash == part.is_dash {
      ranges[i + 1].left = part.left
      ranges.remove(i) |> ignore
    }
  }
  guard ranges.length() > 0 else { return }
  let first = ranges[0]
  let last = ranges[ranges.length() - 1]
  if first.is_dash == last.is_dash {
    let w = LINE_ATLAS_WIDTH.to_double()
    first.left = last.left - w
    last.right = first.right + w
  }
  let row = LINE_ATLAS_WIDTH * self.next_row
  let mut k = 0
  for x in 0..<LINE_ATLAS_WIDTH {
    let xd = x.to_double()
    k = advance(ranges, k, xd)
    let r = ranges[k]
    let d = @cmp.minimum((xd - r.left).abs(), (xd - r.right).abs())
    self.data[row + x] = byte_of(if r.is_dash { d } else { -d })
  }
}

///|
fn LineAtlas::add_round(
  self : LineAtlas,
  ranges : Array[DashRange],
  stretch : Double,
) -> Unit {
  let half = stretch / 2.0
  let n = ROUND_DASH_ROWS
  for y in -n..<=n {
    let row = LINE_ATLAS_WIDTH * (self.next_row + n + y)
    let middle = y.to_double() / n.to_double() * (half + 1.0)
    let mut k = 0
    for x in 0..<LINE_ATLAS_WIDTH {
      let xd = x.to_double()
      k = advance(ranges, k, xd)
      let r = ranges[k]
      let d = @cmp.minimum((xd - r.left).abs(), (xd - r.right).abs())
      let signed = if r.is_dash {
        let edge = half - middle.abs()
        (d * d + edge * edge).sqrt()
      } else {
        half - (d * d + middle * middle).sqrt()
      }
      self.data[row + x] = byte_of(signed)
    }
  }
}

///|
fn LineAtlas::add(
  self : LineAtlas,
  dasharray : Array[Double],
  round : Bool,
) -> DashEntry? {
  let n = if round { ROUND_DASH_ROWS } else { 0 }
  if dasharray.is_empty() || self.next_row + 2 * n + 1 > LINE_ATLAS_HEIGHT {
    return None
  }
  let length = dasharray.fold(init=0.0, (a, b) => a + b)
  if length != 0.0 {
    let stretch = LINE_ATLAS_WIDTH.to_double() / length
    let ranges = ranges_of(dasharray, stretch)
    if round {
      self.add_round(ranges, stretch)
    } else {
      self.add_regular(ranges)
    }
  }
  let entry = { y: self.next_row + n, height: 2 * n, width: length, }
  self.next_row += 2 * n + 1
  self.dirty = true
  Some(entry)
}
