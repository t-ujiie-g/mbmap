///|
/// A straight (not premultiplied) RGBA color with components in [0, 1].
pub(all) struct Color {
  r : Double
  g : Double
  b : Double
  a : Double
} derive(Debug, Eq)

///|
fn hex_digit(c : UInt16) -> Int32 {
  match c {
    '0'..<='9' => c.to_int() - '0'.to_int()
    'a'..<='f' => c.to_int() - 'a'.to_int() + 10
    'A'..<='F' => c.to_int() - 'A'.to_int() + 10
    _ => -1
  }
}

///|
/// Parses `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, `rgb(r, g, b)`,
/// `rgba(r, g, b, a)` and the names `black`, `white` and `transparent`.
pub fn parse_color(s : String) -> Color? {
  let s = s.trim().to_owned().to_lower()
  match s {
    "black" => return Some({ r: 0.0, g: 0.0, b: 0.0, a: 1.0, })
    "white" => return Some({ r: 1.0, g: 1.0, b: 1.0, a: 1.0, })
    "transparent" => return Some({ r: 0.0, g: 0.0, b: 0.0, a: 0.0, })
    _ => ()
  }
  if s.has_prefix("#") {
    parse_hex(s)
  } else if s.has_prefix("rgb") {
    parse_rgb(s)
  } else {
    None
  }
}

///|
fn parse_hex(s : String) -> Color? {
  let digits = []
  for i in 1..<s.length() {
    let d = hex_digit(s[i])
    if d < 0 {
      return None
    }
    digits.push(d)
  }
  let channel = (i : Int32, long : Bool) => {
    if long {
      (digits[i * 2] * 16 + digits[i * 2 + 1]).to_double() / 255.0
    } else {
      (digits[i] * 17).to_double() / 255.0
    }
  }
  match digits.length() {
    3 | 4 as n => {
      let a = if n == 4 { channel(3, false) } else { 1.0 }
      Some({
        r: channel(0, false),
        g: channel(1, false),
        b: channel(2, false),
        a,
      })
    }
    6 | 8 as n => {
      let a = if n == 8 { channel(3, true) } else { 1.0 }
      Some({ r: channel(0, true), g: channel(1, true), b: channel(2, true), a, })
    }
    _ => None
  }
}

///|
fn parse_rgb(s : String) -> Color? {
  let open = s.find("(")
  guard open is Some(open) && s.has_suffix(")") else { return None }
  let name = s[:open].to_owned()
  let parts = s[open + 1:s.length() - 1]
    .split(",")
    .map(p => p.trim().to_owned())
    .collect()
  let expected = if name == "rgba" { 4 } else if name == "rgb" { 3 } else { -1 }
  if parts.length() != expected {
    return None
  }
  let nums = []
  for p in parts {
    nums.push(@string.parse_double(p) catch { _ => return None })
  }
  let a = if expected == 4 { nums[3] } else { 1.0 }
  for i in 0..<3 {
    if nums[i] < 0.0 || nums[i] > 255.0 {
      return None
    }
  }
  if a < 0.0 || a > 1.0 {
    return None
  }
  Some({ r: nums[0] / 255.0, g: nums[1] / 255.0, b: nums[2] / 255.0, a, })
}
