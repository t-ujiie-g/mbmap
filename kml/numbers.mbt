///|
/// Powers of ten that doubles hold exactly.
let exact_powers : FixedArray[Double] = [
  1.0e0, 1.0e1, 1.0e2, 1.0e3, 1.0e4, 1.0e5, 1.0e6, 1.0e7, 1.0e8, 1.0e9, 1.0e10, 1.0e11,
  1.0e12, 1.0e13, 1.0e14, 1.0e15, 1.0e16, 1.0e17, 1.0e18, 1.0e19, 1.0e20, 1.0e21,
  1.0e22,
]

///|
fn is_digit(c : UInt16) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// JavaScript's `Number.parseFloat(s)`: white space skipped, then the longest
/// decimal literal (or `Infinity`) at the start, NaN without one. Clinger's fast
/// path takes up to 15 digits and exponents within ±22; the rest of the literal
/// goes to `number` (the host's `Number`).
pub fn parse_float(s : String, number : (String) -> Double) -> Double {
  parse_float_in(s, 0, s.length(), number)
}

///|
/// `parse_float` of code units `from` to `n` of `s`.
fn parse_float_in(
  s : String,
  from : Int32,
  n : Int32,
  number : (String) -> Double,
) -> Double {
  let mut i = from
  while i < n && @xml.is_js_space(s[i]) {
    i += 1
  }
  let start = i
  let negative = i < n && s[i] == '-'
  if i < n && (s[i] == '-' || s[i] == '+') {
    i += 1
  }
  if i + 8 <= n && @xml.units(s, i, i + 8) == "Infinity" {
    return if negative { @double.neg_infinity } else { @double.infinity }
  }
  let mut mantissa = 0L
  let mut digits = 0
  let mut exponent = 0
  let mut any = false
  while i < n && is_digit(s[i]) {
    if digits < 18 {
      mantissa = mantissa * 10L + (s[i].to_int() - 0x30).to_int64()
      if mantissa > 0L {
        digits += 1
      }
    } else {
      exponent += 1
      digits += 1
    }
    any = true
    i += 1
  }
  if i < n && s[i] == '.' {
    i += 1
    while i < n && is_digit(s[i]) {
      if digits < 18 {
        mantissa = mantissa * 10L + (s[i].to_int() - 0x30).to_int64()
        if mantissa > 0L {
          digits += 1
        }
        exponent -= 1
      } else {
        digits += 1
      }
      any = true
      i += 1
    }
  }
  guard any else { return @double.not_a_number }
  if i < n && (s[i] == 'e' || s[i] == 'E') {
    let mut j = i + 1
    let mut sign = 1
    if j < n && (s[j] == '+' || s[j] == '-') {
      sign = if s[j] == '-' { -1 } else { 1 }
      j += 1
    }
    if j < n && is_digit(s[j]) {
      let mut e = 0
      while j < n && is_digit(s[j]) {
        e = @cmp.minimum(e * 10 + (s[j].to_int() - 0x30), 100000)
        j += 1
      }
      exponent += sign * e
      i = j
    }
  }
  if digits <= 15 && exponent.abs() <= 22 {
    let m = mantissa.to_double()
    let v = if exponent < 0 {
      m / exact_powers[-exponent]
    } else {
      m * exact_powers[exponent]
    }
    return if negative { -v } else { v }
  }
  number(s.view(start_offset=start, end_offset=i).to_owned())
}

///|
fn hex_digit(c : UInt16) -> Int32 {
  let c = c.to_int()
  if c >= 0x30 && c <= 0x39 {
    c - 0x30
  } else if c >= 0x61 && c <= 0x66 {
    c - 0x57
  } else if c >= 0x41 && c <= 0x46 {
    c - 0x37
  } else {
    -1
  }
}

///|
/// JavaScript's `parseInt(s.substring(at, at + 2), 16)`: white space or a sign
/// then a digit, or one or two digits (`0x` alone is NaN).
fn parse_hex2(s : String, at : Int32) -> Double {
  let a = s[at]
  let b = hex_digit(s[at + 1])
  let v = if @xml.is_js_space(a) || a == '+' || a == '-' {
    if b < 0 {
      return @double.not_a_number
    }
    if a == '-' {
      -b
    } else {
      b
    }
  } else if hex_digit(a) < 0 ||
    (a == '0' && (s[at + 1] == 'x' || s[at + 1] == 'X')) {
    return @double.not_a_number
  } else if b < 0 {
    hex_digit(a)
  } else {
    hex_digit(a) * 16 + b
  }
  v.to_double()
}

///|
/// Whether `s` starts with `prefix`.
fn starts_with(s : String, prefix : String) -> Bool {
  s.length() >= prefix.length() && @xml.units(s, 0, prefix.length()) == prefix
}

///|
/// `s.replace(old, new)` of JavaScript: the first `old` replaced.
fn replace_first(s : String, old : String, new : String) -> String {
  let n = old.length()
  for i = 0; i + n <= s.length(); i = i + 1 {
    if @xml.units(s, i, i + n) == old {
      return @xml.units(s, 0, i) + new + @xml.units(s, i + n, s.length())
    }
  }
  s
}

///|
/// JavaScript's `s.trim()`.
fn js_trim(s : String) -> String {
  let mut a = 0
  let mut b = s.length()
  while a < b && @xml.is_js_space(s[a]) {
    a += 1
  }
  while b > a && @xml.is_js_space(s[b - 1]) {
    b -= 1
  }
  if a == 0 && b == s.length() {
    s
  } else {
    @xml.units(s, a, b)
  }
}
