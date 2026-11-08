///|
/// `@route.snap_lines` of lines given as their point counts (`counts`) over
/// x, y pairs (`coords`): the counts of the lines out, then their pairs; empty
/// where it gives None.
#export_name("route_snap")
pub fn route_snap(
  counts : FixedArray[Int32],
  coords : FixedArray[Double],
  snap : Double,
) -> FixedArray[Double] {
  let lines = []
  let mut at = 0
  for c in counts {
    lines.push((at, at + c))
    at += c
  }
  guard @route.snap_lines(Array::from_fixed_array(coords), lines, snap)
    is Some((out, ranges)) else {
    return []
  }
  let result = FixedArray::make(ranges.length() + out.length(), 0.0)
  for i, r in ranges {
    result[i] = (r.1 - r.0).to_double()
  }
  for i, v in out {
    result[ranges.length() + i] = v
  }
  result
}
