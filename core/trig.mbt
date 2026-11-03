///|
/// Elementary functions: MoonBit's (`Trig::moonbit`), or a wasm host's `Math`,
/// which computes as the JavaScript libraries mbmap follows and keeps `@math`
/// out of the module.
pub(all) struct Trig {
  sin : (Double) -> Double
  cos : (Double) -> Double
  tan : (Double) -> Double
  asin : (Double) -> Double
  acos : (Double) -> Double
  atan : (Double) -> Double
  atan2 : (Double, Double) -> Double
  exp : (Double) -> Double
  ln : (Double) -> Double
  pow : (Double, Double) -> Double
  cbrt : (Double) -> Double
  atanh : (Double) -> Double
}

///|
pub fn Trig::moonbit() -> Trig {
  {
    sin: @math.sin,
    cos: @math.cos,
    tan: @math.tan,
    asin: @math.asin,
    acos: @math.acos,
    atan: @math.atan,
    atan2: @math.atan2,
    exp: @math.exp,
    ln: @math.ln,
    pow: @math.pow,
    cbrt: @math.cbrt,
    atanh: @math.atanh,
  }
}

///|
pub fn Trig::sin(self : Trig, x : Double) -> Double {
  (self.sin)(x)
}

///|
pub fn Trig::cos(self : Trig, x : Double) -> Double {
  (self.cos)(x)
}

///|
pub fn Trig::tan(self : Trig, x : Double) -> Double {
  (self.tan)(x)
}

///|
pub fn Trig::asin(self : Trig, x : Double) -> Double {
  (self.asin)(x)
}

///|
pub fn Trig::acos(self : Trig, x : Double) -> Double {
  (self.acos)(x)
}

///|
pub fn Trig::atan(self : Trig, x : Double) -> Double {
  (self.atan)(x)
}

///|
pub fn Trig::atan2(self : Trig, y : Double, x : Double) -> Double {
  (self.atan2)(y, x)
}

///|
pub fn Trig::exp(self : Trig, x : Double) -> Double {
  (self.exp)(x)
}

///|
pub fn Trig::ln(self : Trig, x : Double) -> Double {
  (self.ln)(x)
}

///|
pub fn Trig::pow(self : Trig, x : Double, y : Double) -> Double {
  (self.pow)(x, y)
}

///|
pub fn Trig::cbrt(self : Trig, x : Double) -> Double {
  (self.cbrt)(x)
}

///|
pub fn Trig::atanh(self : Trig, x : Double) -> Double {
  (self.atanh)(x)
}
