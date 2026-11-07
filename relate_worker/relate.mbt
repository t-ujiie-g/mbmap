///|
/// The most pairs `relate_pairs` writes.
const MAX_RELATE_PAIRS = 10_000_000

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
/// The input's two tables: the first `len_a` bytes, then the rest.
fn tables(len_a : Int32) -> (@geom.Table, @geom.Table)? {
  let input = @wasmio.input_bytes()
  @wasmio.clear_input()
  guard len_a >= 0 &&
    len_a <= input.length() &&
    @geom.Table::from_bytes(input[:len_a]) is Some(a) &&
    @geom.Table::from_bytes(input[len_a:]) is Some(b) else {
    return None
  }
  Some((a, b))
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
/// Pairs (row of the first table, row of the second) whose boxes meet and that
/// hold predicate `code` (an index of `predicates`) or, with `code` -1, match
/// `pattern` (`unpack_pattern`); writes them as i32s and returns their count.
#export_name("relate_pairs")
pub fn relate_pairs(len_a : Int32, code : Int32, pattern : Int32) -> Int32 {
  guard tables(len_a) is Some((a, b)) else {
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
  let index = @analysis.Index::of_table(b)
  let out : Array[Int32] = []
  let found : Array[Int32] = []
  for i in 0..<a.length() {
    let (x0, y0, x1, y1) = @analysis.bbox(a, i)
    found.clear()
    index.search(x0, y0, x1, y1, found)
    found.sort()
    for j in found {
      if !@relate.within_limit(a, i, b, j) {
        return @wasmio.fail_with(too_many_points)
      }
      let holds = match pattern {
        Some(p) =>
          match @relate.relate_checked(a, i, b, j) {
            Some(m) => m.matches(p)
            None => return @wasmio.fail_with(unrelated(i, j))
          }
        None => @relate.predicate(a, i, b, j, predicates[code])
      }
      if holds {
        if out.length() >= MAX_RELATE_PAIRS * 2 {
          return @wasmio.fail_with("more than \{MAX_RELATE_PAIRS} pairs")
        }
        out.push(i)
        out.push(j)
      }
    }
  }
  @wasmio.write_i32s(out[:])
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
/// or minus an error's.
#export_name("relate_matrix")
pub fn relate_matrix(len_a : Int32, i : Int32, j : Int32) -> Int32 {
  guard tables(len_a) is Some((a, b)) else {
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
