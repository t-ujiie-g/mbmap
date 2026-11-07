///|
/// Ticks as JavaScript prints them, None as "throws".
fn ticks_text(start : Double, stop : Double, count : Double) -> String {
  match ticks(start, stop, count, Trig::moonbit()) {
    Some(t) if t.length() > 12 =>
      "\{t.length()} \{t[0].to_string()} \{t[t.length() - 1].to_string()}"
    Some(t) => t.map(x => x.to_string()).join(" ")
    None => "throws"
  }
}

///|
test "ticks as d3-array gives them" {
  assert_eq(
    ticks_text(0.0, 1.0, 10.0),
    "0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1",
  )
  assert_eq(ticks_text(5.0e-324, 0.0123456, 20.0), "24 0.0005 0.012")
  assert_eq(ticks_text(5.0e-324, 0.0, 20.0), "")
  assert_eq(ticks_text(5.0e-324, @double.not_a_number, 20.0), "")
  assert_eq(ticks_text(1.0, 0.0, 5.0), "1 0.8 0.6 0.4 0.2 0")
  assert_eq(ticks_text(5.0e-324, 5.0e-324, 3.0), "5e-324")
  assert_eq(ticks_text(5.0e-324, 1.0e-320, 20.0), "throws")
  assert_eq(ticks_text(0.0, 1.0e23, 7.0), "0 2e+22 4e+22 6e+22 8e+22 1e+23")
  assert_eq(ticks_text(-3.3, 7.7, 1.0), "0")
  assert_eq(ticks_text(2.0, 2.5, 0.7), "2")
  assert_eq(ticks_text(0.0, 1.0e300, 1000.0), "1001 0 1e+300")
  assert_eq(ticks_text(0.0, 1.0, 0.0), "")
  assert_eq(ticks_text(0.0, 1.0e300, 20000.0), "throws")
}

///|
test "log10 as V8's Math.log10" {
  let trig = Trig::moonbit()
  assert_eq(log10(1.0e23, trig), 23.0)
  assert_eq(log10(9.999999999999999e22, trig), 23.0)
  assert_eq(log10(0.001, trig), -3.0)
  assert_eq(log10(1.0e-5, trig), -5.0)
  assert_eq(log10(2.0e-308, trig), -307.69897000433605)
  assert_eq(log10(5.0e-324, trig), -323.3062153431158)
  assert_eq(log10(1000.0, trig), 3.0)
  assert_eq(log10(0.30000000000000004, trig), -0.5228787452803375)
  assert_eq(log10(123.456, trig), 2.0915122016277716)
  assert_eq(log10(1.0, trig), 0.0)
  assert_eq(log10(0.0, trig), @double.neg_infinity)
  assert_true(log10(-1.0, trig).is_nan())
  assert_eq(log10(@double.infinity, trig), @double.infinity)
}

///|
test "js_round as Math.round" {
  assert_eq(js_round(2.5), 3.0)
  assert_eq(js_round(-2.5), -2.0)
  assert_eq(1.0 / js_round(-0.4), @double.neg_infinity)
  assert_eq(js_round(0.49999999999999994), 0.0)
  assert_eq(js_round(1.5), 2.0)
  assert_eq(js_round(-1.5), -1.0)
  assert_eq(js_round(4503599627370495.5), 4503599627370496.0)
  assert_true(js_round(@double.not_a_number).is_nan())
}

///|
test "max_of skips NaN as d3-array's max" {
  let f = Float::from_double
  assert_eq(max_of([f(1.0), f(@double.not_a_number), f(3.5), f(-2.0)]), 3.5)
  assert_true(max_of([f(@double.not_a_number)]).is_nan())
  assert_true(max_of([]).is_nan())
}
