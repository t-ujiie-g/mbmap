///|
/// The most pairs `relate_pairs` writes.
pub const MAX_RELATE_PAIRS : Int32 = 10_000_000

///|
/// The most candidate pairs (boxes meeting) `relate_pairs` tests.
pub const MAX_RELATE_CANDIDATES : Int32 = 10_000_000

///|
/// The most points `relate_pairs` reads over all the pairs it tests.
pub const MAX_RELATE_TESTED_POINTS : Int32 = 1_000_000_000

///|
/// Makes room for `len` input bytes and returns where JS should write them,
/// or -1 if `len` is too large.
#export_name("prepare_input")
pub fn prepare_input(len : Int32) -> Int32 {
  @wasmio.prepare_input(len, @wasmio.MAX_INPUT_BYTES)
}

///|
/// Where the last call's output starts.
#export_name("output_addr")
pub fn output_addr() -> Int32 {
  @wasmio.output_addr()
}

///|
/// The two tables of the last call that read them, and the second's index once
/// built. Datasets never change, so the worker reuses them for the same pair.
priv struct Kept {
  a : @geom.Table
  b : @geom.Table
  mut index : @analysis.Index?
}

///|
let kept : Ref[Kept?] = Ref(None)

///|
/// The input's two tables (the first `len_a` bytes, then the rest), kept for
/// later calls; with `len_a` -1, the tables the last call kept.
fn tables(len_a : Int32) -> Kept? {
  if len_a == -1 {
    return kept.val
  }
  kept.val = None
  let input = @wasmio.input_bytes()
  @wasmio.clear_input()
  guard len_a >= 0 &&
    len_a <= input.length() &&
    @geom.Table::from_bytes(input[:len_a]) is Some(a) &&
    @geom.Table::from_bytes(input[len_a:]) is Some(b) else {
    return None
  }
  let k = { a, b, index: None, }
  kept.val = Some(k)
  Some(k)
}

///|
fn Kept::index(self : Kept) -> @analysis.Index {
  match self.index {
    Some(i) => i
    None => {
      let i = @analysis.Index::of_table(self.b)
      self.index = Some(i)
      i
    }
  }
}

///|
/// Drops the tables the last call kept.
#export_name("forget_tables")
pub fn forget_tables() -> Unit {
  kept.val = None
}

///|
/// The predicates `relate_pairs` takes by code, in JTS's names.
let predicates : FixedArray[String] = [
  "intersects", "contains", "within", "covers", "coveredBy", "touches", "crosses",
  "overlaps", "equals",
]

///|
/// A DE-9IM pattern packed three bits a cell, first cell lowest: 0 F, 1 0, 2 1,
/// 3 2, 4 T, 5 `*`; None for another code.
fn unpack_pattern(packed : Int32) -> String? {
  let chars = ['F', '0', '1', '2', 'T', '*']
  let out = StringBuilder()
  for k in 0..<9 {
    let c = (packed >> (k * 3)) & 7
    if c >= chars.length() {
      return None
    }
    out.write_char(chars[c])
  }
  Some(out.to_string())
}

///|
/// Pairs (rows of the `tables`) whose boxes meet and that hold predicate `code`
/// (an index of `predicates`) or, with `code` -1, match `pattern`
/// (`unpack_pattern`); writes them as i32s and returns their count.
#export_name("relate_pairs")
pub fn relate_pairs(len_a : Int32, code : Int32, pattern : Int32) -> Int32 {
  guard tables(len_a) is Some(k) else {
    return @wasmio.fail_with("malformed tables")
  }
  let pattern = if code == -1 {
    guard unpack_pattern(pattern) is Some(p) else {
      return @wasmio.fail_with("invalid DE-9IM pattern")
    }
    Some(p)
  } else if code < 0 || code >= predicates.length() {
    return @wasmio.fail_with("unknown predicate \{code}")
  } else {
    None
  }
  match pairs(k.a, k.b, code, pattern, index=k.index()) {
    Ok(out) => @wasmio.write_i32s(out[:])
    Err(why) => @wasmio.fail_with(why)
  }
}

///|
/// `relate_pairs`' pairs of `a` and `b`, or why there are none.
fn pairs(
  a : @geom.Table,
  b : @geom.Table,
  code : Int32,
  pattern : String?,
  index~ : @analysis.Index = @analysis.Index::of_table(b),
  max_candidates~ : Int32 = MAX_RELATE_CANDIDATES,
  max_points~ : Int32 = MAX_RELATE_TESTED_POINTS,
) -> Result[Array[Int32], String] {
  let out : Array[Int32] = []
  let found : Array[Int32] = []
  let mut candidates = 0L
  let mut points = 0L
  for i in 0..<a.length() {
    let (x0, y0, x1, y1) = @analysis.bbox(a, i)
    found.clear()
    index.search(x0, y0, x1, y1, found)
    found.sort()
    candidates += found.length().to_int64()
    if candidates > max_candidates.to_int64() {
      return Err("more than \{max_candidates} pairs of features to test")
    }
    for j in found {
      if !@relate.within_limit(a, i, b, j) {
        return Err(too_many_points)
      }
      points += @relate.pair_points(a, i, b, j).to_int64()
      if points > max_points.to_int64() {
        return Err("more than \{max_points} points to test in pairs")
      }
      let holds = match pattern {
        Some(p) =>
          match @relate.relate_checked(a, i, b, j) {
            Some(m) => m.matches(p)
            None => return Err(unrelated(i, j))
          }
        None => @relate.predicate(a, i, b, j, predicates[code])
      }
      if holds {
        if out.length() >= MAX_RELATE_PAIRS * 2 {
          return Err("more than \{MAX_RELATE_PAIRS} pairs")
        }
        out.push(i)
        out.push(j)
      }
    }
  }
  Ok(out)
}

///|
/// Why a pair JTS would throw on (invalid geometry) has no matrix.
fn unrelated(i : Int32, j : Int32) -> String {
  "features \{i} and \{j} are invalid where they meet (JTS throws a topology error)"
}

///|
let too_many_points = "a pair of features has more than \{@relate.MAX_RELATE_POINTS} points"

///|
/// Writes the DE-9IM matrix of row `i` of the first table and row `j` of the
/// second as JTS writes it ("FF2F11212", 9 ASCII bytes) and returns its length,
/// or minus an error's. The tables are read as `tables` reads them.
#export_name("relate_matrix")
pub fn relate_matrix(len_a : Int32, i : Int32, j : Int32) -> Int32 {
  guard tables(len_a) is Some({ a, b, .. }) else {
    return @wasmio.fail_with("malformed tables")
  }
  guard i >= 0 && i < a.length() && j >= 0 && j < b.length() else {
    return @wasmio.fail_with("no feature \{i} or \{j}")
  }
  if !@relate.within_limit(a, i, b, j) {
    return @wasmio.fail_with(too_many_points)
  }
  match @relate.relate_checked(a, i, b, j) {
    Some(m) => {
      let s = m.to_string()
      let bytes = FixedArray::make(9, b'\x00')
      for k in 0..<9 {
        bytes[k] = s[k].to_int().to_byte()
      }
      @wasmio.write_bytes(Bytes::from_array(bytes)[:])
    }
    None => @wasmio.fail_with(unrelated(i, j))
  }
}
