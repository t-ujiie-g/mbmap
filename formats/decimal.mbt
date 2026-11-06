// Ported from papaparse 5.7.0: MIT License, Copyright (c) 2015 Matthew Holt. See NOTICE.

///|
/// The decimal number at `start` of `b` before `limit` (`-`, or `+` if `plus`, then
/// `1`, `1.`, `1.5` or `.5`, then an exponent) and the position after it, or `start`.
/// Up to 15 digits and exponents within ±22 are exact (Clinger); `slow` takes the rest.
fn read_decimal(
  b : BytesView,
  start : Int32,
  limit : Int32,
  plus : Bool,
  slow : (Int32, Int32) -> Double,
) -> (Double, Int32) {
  let mut i = start
  let negative = i < limit && b[i] == b'-'
  if negative || (plus && i < limit && b[i] == b'+') {
    i += 1
  }
  let mut mantissa = 0L
  let mut digits = 0
  let mut exponent = 0
  let mut seen = 0
  while i < limit && b[i] >= b'0' && b[i] <= b'9' {
    if digits < 18 {
      mantissa = mantissa * 10L + (b[i].to_int() - '0'.to_int()).to_int64()
      if mantissa > 0L {
        digits += 1
      }
    } else {
      exponent += 1
      digits += 1
    }
    seen += 1
    i += 1
  }
  if i < limit && b[i] == b'.' {
    i += 1
    while i < limit && b[i] >= b'0' && b[i] <= b'9' {
      if digits < 18 {
        mantissa = mantissa * 10L + (b[i].to_int() - '0'.to_int()).to_int64()
        if mantissa > 0L {
          digits += 1
        }
        exponent -= 1
      } else {
        digits += 1
      }
      seen += 1
      i += 1
    }
  }
  if seen == 0 {
    return (@double.not_a_number, start)
  }
  if i < limit && (b[i] == b'e' || b[i] == b'E') {
    let mut j = i + 1
    let mut sign = 1
    if j < limit && (b[j] == b'+' || b[j] == b'-') {
      sign = if b[j] == b'-' { -1 } else { 1 }
      j += 1
    }
    let mut e = 0
    let digits_at = j
    while j < limit && b[j] >= b'0' && b[j] <= b'9' {
      e = @cmp.minimum(e * 10 + (b[j].to_int() - '0'.to_int()), 100000)
      j += 1
    }
    // An 'e' without digits is not part of the number.
    if j > digits_at {
      exponent += sign * e
      i = j
    }
  }
  if digits <= 15 && exponent.abs() <= 22 {
    let m = mantissa.to_double()
    let v = if exponent < 0 {
      m / @core.exact_powers[-exponent]
    } else {
      m * @core.exact_powers[exponent]
    }
    return (if negative { -v } else { v }, i)
  }
  (slow(start, i), i)
}

///|
/// The length of the JavaScript white space or line terminator (what a regular
/// expression's `\s` matches) starting at `i` of `b` before `end`, or 0.
fn space_at(b : BytesView, i : Int32, end : Int32) -> Int32 {
  let c = b[i]
  if c == b' ' || (c >= b'\t' && c <= b'\r') {
    return 1
  }
  if c == b'\xc2' && i + 1 < end && b[i + 1] == b'\xa0' {
    return 2
  }
  if i + 2 >= end {
    return 0
  }
  let (c1, c2) = (b[i + 1], b[i + 2])
  let space = match c {
    b'\xe1' => c1 == b'\x9a' && c2 == b'\x80'
    b'\xe2' =>
      (
        c1 == b'\x80' &&
        (
          (c2 >= b'\x80' && c2 <= b'\x8a') ||
          c2 == b'\xa8' ||
          c2 == b'\xa9' ||
          c2 == b'\xaf'
        )
      ) ||
      (c1 == b'\x81' && c2 == b'\x9f')
    b'\xe3' => c1 == b'\x80' && c2 == b'\x80'
    b'\xef' => c1 == b'\xbb' && c2 == b'\xbf'
    _ => false
  }
  if space {
    3
  } else {
    0
  }
}

///|
/// The length of the white space (as `space_at`) ending just before `i`, after
/// `start`, or 0.
fn space_before(b : BytesView, start : Int32, i : Int32) -> Int32 {
  for n in [1, 2, 3] {
    if i - n >= start && space_at(b, i - n, i) == n {
      return n
    }
  }
  0
}

///|
/// Largest magnitude papaparse's `dynamicTyping` turns into a number: 2^53, excluded.
const MAX_TYPED_NUMBER : Double = 9007199254740992.0

///|
/// `b[start:end]` as a number the way papaparse's `dynamicTyping` reads one: white
/// space around it, a '-', digits with an optional point (or a point and digits)
/// and an exponent, below 2^53 in magnitude; None otherwise.
fn typed_number(
  b : BytesView,
  start : Int32,
  end : Int32,
  slow : (Int32, Int32) -> Double,
) -> Double? {
  let mut s = start
  let mut e = end
  while s < e {
    let n = space_at(b, s, e)
    if n == 0 {
      break
    }
    s += n
  }
  while e > s {
    let n = space_before(b, s, e)
    if n == 0 {
      break
    }
    e -= n
  }
  let (v, after) = read_decimal(b, s, e, false, slow)
  if after == e && after > s && v > -MAX_TYPED_NUMBER && v < MAX_TYPED_NUMBER {
    Some(v)
  } else {
    None
  }
}
