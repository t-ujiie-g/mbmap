// Ports d3-array 3.2.5's ticks.js, max.js and blur.js (ISC License, Copyright
// 2010-2023 Mike Bostock). See NOTICE.

///|
using @core {type Trig}

///|
/// Most ticks `contour_density` turns a threshold count into; d3 makes
/// `new Array(n)` of any length.
pub const MAX_TICKS : Int32 = 16384

///|
/// JavaScript's `Math.log10` as V8 computes it (fdlibm's e_log10.c over
/// `Math.log`), with `trig.ln` for the logarithm.
fn log10(x : Double, trig : Trig) -> Double {
  let two54 = 1.80143985094819840000e+16
  let ivln10 = 4.34294481903251816668e-01
  let log10_2hi = 3.01029995663611771306e-01
  let log10_2lo = 3.69423907715893078616e-13
  let mut x = x
  let mut hx = (x.reinterpret_as_int64() >> 32).to_int()
  let mut lx = x.reinterpret_as_int64() & 0xFFFFFFFFL
  let mut k = 0
  if hx < 0x00100000 {
    if (hx & 0x7fffffff).to_int64() == 0L && lx == 0L {
      return @double.neg_infinity
    }
    if hx < 0 {
      return @double.not_a_number
    }
    k -= 54
    x *= two54
    hx = (x.reinterpret_as_int64() >> 32).to_int()
    lx = x.reinterpret_as_int64() & 0xFFFFFFFFL
  }
  if hx >= 0x7ff00000 {
    return x + x
  }
  if hx == 0x3ff00000 && lx == 0L {
    return 0.0
  }
  k += (hx >> 20) - 1023
  let i = if k < 0 { 1 } else { 0 }
  hx = (hx & 0x000fffff) | ((0x3ff - i) << 20)
  let y = (k + i).to_double()
  let reduced = ((hx.to_int64() << 32) | lx).reinterpret_as_double()
  let z = y * log10_2lo + ivln10 * trig.ln(reduced)
  z + y * log10_2hi
}

///|
/// d3-array's `tickSpec`: (i1, i2, inc).
fn tick_spec(
  start : Double,
  stop : Double,
  count : Double,
  trig : Trig,
) -> (Double, Double, Double) {
  let step = (stop - start) / (if count > 0.0 { count } else { 0.0 })
  let power = log10(step, trig).floor()
  let error = step / trig.pow(10.0, power)
  let factor = if error >= 50.0.sqrt() {
    10.0
  } else if error >= 10.0.sqrt() {
    5.0
  } else if error >= 2.0.sqrt() {
    2.0
  } else {
    1.0
  }
  let mut i1 = 0.0
  let mut i2 = 0.0
  let mut inc = 0.0
  if power < 0.0 {
    inc = trig.pow(10.0, -power) / factor
    i1 = @core.js_round(start * inc)
    i2 = @core.js_round(stop * inc)
    if i1 / inc < start {
      i1 += 1.0
    }
    if i2 / inc > stop {
      i2 -= 1.0
    }
    inc = -inc
  } else {
    inc = trig.pow(10.0, power) * factor
    i1 = @core.js_round(start / inc)
    i2 = @core.js_round(stop / inc)
    if i1 * inc < start {
      i1 += 1.0
    }
    if i2 * inc > stop {
      i2 -= 1.0
    }
  }
  if i2 < i1 && 0.5 <= count && count < 2.0 {
    return tick_spec(start, stop, count * 2.0, trig)
  }
  (i1, i2, inc)
}

///|
/// d3-array's `ticks(start, stop, count)`; None where it would make more than
/// `MAX_TICKS` (or throws on a non-finite length).
fn ticks(
  start : Double,
  stop : Double,
  count : Double,
  trig : Trig,
) -> Array[Double]? {
  if !(count > 0.0) {
    return Some([])
  }
  if start == stop {
    return Some([start])
  }
  let reverse = stop < start
  let (i1, i2, inc) = if reverse {
    tick_spec(stop, start, count, trig)
  } else {
    tick_spec(start, stop, count, trig)
  }
  if !(i2 >= i1) {
    return Some([])
  }
  let n = i2 - i1 + 1.0
  if !(n <= MAX_TICKS.to_double()) {
    return None
  }
  let out = []
  for i in 0..<n.to_int() {
    let k = i.to_double()
    out.push(
      match (reverse, inc < 0.0) {
        (true, true) => (i2 - k) / -inc
        (true, false) => (i2 - k) * inc
        (false, true) => (i1 + k) / -inc
        (false, false) => (i1 + k) * inc
      },
    )
  }
  Some(out)
}

///|
/// d3-array's `max`: the largest value that is not NaN, NaN if none.
fn max_of(values : FixedArray[Float]) -> Double {
  let mut m = @double.not_a_number
  for v in values {
    let d = v.to_double()
    if m < d || (m.is_nan() && d >= d) {
      m = d
    }
  }
  m
}

///|
/// d3-array's `blurf` (or `bluri` for an integer radius) over one line of a
/// Float32Array: `target[i]` for `start <= i < stop` by `step` gets the mean of
/// `source` within the radius, clamped to the line.
fn blur_line(
  radius : Double,
  target : FixedArray[Float],
  source : FixedArray[Float],
  start : Int32,
  stop : Int32,
  step : Int32,
) -> Unit {
  let last = stop - step
  if !(last >= start) {
    return
  }
  let radius0 = radius.floor()
  let r = radius0.to_int()
  let s = source
  let at = (i : Int32) => s[i].to_double()
  let s0 = step * r
  if radius0 == radius {
    let w = 2.0 * radius + 1.0
    let mut sum = radius * at(start)
    for i = start; i < start + s0; i = i + step {
      sum += at(@cmp.minimum(last, i))
    }
    for i = start; i <= last; i = i + step {
      sum += at(@cmp.minimum(last, i + s0))
      target[i] = Float::from_double(sum / w)
      sum -= at(@cmp.maximum(start, i - s0))
    }
  } else {
    let t = radius - radius0
    let w = 2.0 * radius + 1.0
    let s1 = s0 + step
    let mut sum = radius0 * at(start)
    for i = start; i < start + s0; i = i + step {
      sum += at(@cmp.minimum(last, i))
    }
    for i = start; i <= last; i = i + step {
      sum += at(@cmp.minimum(last, i + s0))
      target[i] = Float::from_double(
        (
          sum +
          t * (at(@cmp.maximum(start, i - s1)) + at(@cmp.minimum(last, i + s1)))
        ) /
        w,
      )
      sum -= at(@cmp.maximum(start, i - s0))
    }
  }
}

///|
/// d3-array's `blur2({data: values, width, height}, radius)` in place.
fn blur2(
  values : FixedArray[Float],
  width : Int32,
  height : Int32,
  radius : Double,
) -> Unit {
  if width == 0 || height == 0 || radius == 0.0 {
    return
  }
  let temp = values.copy()
  let n = width * height
  fn h(target : FixedArray[Float], source : FixedArray[Float]) {
    for y = 0; y < n; y = y + width {
      blur_line(radius, target, source, y, y + width, 1)
    }
  }

  fn v(target : FixedArray[Float], source : FixedArray[Float]) {
    for x in 0..<width {
      blur_line(radius, target, source, x, x + n, width)
    }
  }

  h(temp, values)
  h(values, temp)
  h(temp, values)
  v(values, temp)
  v(temp, values)
  v(values, temp)
}
