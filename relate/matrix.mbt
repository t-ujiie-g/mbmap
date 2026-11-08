///|
/// A DE-9IM matrix, JTS's `IntersectionMatrix`: entry (row, column) for the
/// interior (0), boundary (1) and exterior (2) of each geometry, the dimension of
/// their intersection (-1 for none).
pub struct Matrix {
  priv m : FixedArray[Int32]
}

///|
fn Matrix::new() -> Matrix {
  { m: FixedArray::make(9, -1), }
}

///|
fn Matrix::set(self : Matrix, row : Int32, col : Int32, value : Int32) -> Unit {
  self.m[3 * row + col] = value
}

///|
fn Matrix::set_at_least_if_valid(
  self : Matrix,
  row : Int32,
  col : Int32,
  value : Int32,
) -> Unit {
  if row >= 0 && col >= 0 && self.m[3 * row + col] < value {
    self.m[3 * row + col] = value
  }
}

///|
/// `Dimension.toDimensionValue` for the symbols this port writes.
fn dimension_value(c : Int32) -> Int32 {
  if c == '0'.to_int() {
    0
  } else if c == '1'.to_int() {
    1
  } else if c == '2'.to_int() {
    2
  } else if c == 'T'.to_int() {
    -2
  } else if c == '*'.to_int() {
    -3
  } else {
    -1
  }
}

///|
fn Matrix::set_at_least_pattern(self : Matrix, pattern : String) -> Unit {
  for i in 0..<9 {
    let v = dimension_value(pattern[i].to_int())
    if self.m[i] < v {
      self.m[i] = v
    }
  }
}

///|
/// Entry (`row`, `col`), rows and columns numbered interior 0, boundary 1,
/// exterior 2; -1 (F) out of range.
pub fn Matrix::get(self : Matrix, row : Int32, col : Int32) -> Int32 {
  if row < 0 || row > 2 || col < 0 || col > 2 {
    -1
  } else {
    self.m[3 * row + col]
  }
}

///|
/// The nine entries as JTS's `toString` writes them, e.g. "FF2F11212".
pub fn Matrix::to_string(self : Matrix) -> String {
  let sb = StringBuilder()
  for v in self.m {
    sb.write_char(
      match v {
        0 => '0'
        1 => '1'
        2 => '2'
        -2 => 'T'
        -3 => '*'
        _ => 'F'
      },
    )
  }
  sb.to_string()
}

///|
fn is_true(v : Int32) -> Bool {
  v >= 0 || v == -2
}

///|
/// Whether the matrix matches a pattern of nine symbols (T, F, *, 0, 1, 2),
/// as `IntersectionMatrix.matches`; false for a pattern of another length.
pub fn Matrix::matches(self : Matrix, pattern : String) -> Bool {
  if pattern.length() != 9 {
    return false
  }
  for i in 0..<9 {
    let v = self.m[i]
    let c = pattern[i].to_int()
    let ok = c == '*'.to_int() ||
      (c == 'T'.to_int() && is_true(v)) ||
      (c == 'F'.to_int() && v == -1) ||
      (c == '0'.to_int() && v == 0) ||
      (c == '1'.to_int() && v == 1) ||
      (c == '2'.to_int() && v == 2)
    if !ok {
      return false
    }
  }
  true
}

///|
/// `isIntersects`: the geometries share a point.
pub fn Matrix::is_intersects(self : Matrix) -> Bool {
  !self.is_disjoint()
}

///|
/// `isDisjoint`: FF*FF****.
pub fn Matrix::is_disjoint(self : Matrix) -> Bool {
  self.m[0] == -1 && self.m[1] == -1 && self.m[3] == -1 && self.m[4] == -1
}

///|
/// `isContains`: T*****FF*.
pub fn Matrix::is_contains(self : Matrix) -> Bool {
  is_true(self.m[0]) && self.m[6] == -1 && self.m[7] == -1
}

///|
/// `isWithin`: T*F**F***.
pub fn Matrix::is_within(self : Matrix) -> Bool {
  is_true(self.m[0]) && self.m[2] == -1 && self.m[5] == -1
}

///|
fn Matrix::has_point_in_common(self : Matrix) -> Bool {
  is_true(self.m[0]) ||
  is_true(self.m[1]) ||
  is_true(self.m[3]) ||
  is_true(self.m[4])
}

///|
/// `isCovers`: a point in common and nothing of the second outside the first.
pub fn Matrix::is_covers(self : Matrix) -> Bool {
  self.has_point_in_common() && self.m[6] == -1 && self.m[7] == -1
}

///|
/// `isCoveredBy`: a point in common and nothing of the first outside the second.
pub fn Matrix::is_covered_by(self : Matrix) -> Bool {
  self.has_point_in_common() && self.m[2] == -1 && self.m[5] == -1
}

///|
/// `isTouches` for geometries of dimensions `dim_a` and `dim_b`.
pub fn Matrix::is_touches(self : Matrix, dim_a : Int32, dim_b : Int32) -> Bool {
  if dim_a > dim_b {
    return self.is_touches(dim_b, dim_a)
  }
  if (dim_a == 2 && dim_b == 2) ||
    (dim_a == 1 && dim_b == 1) ||
    (dim_a == 1 && dim_b == 2) ||
    (dim_a == 0 && dim_b == 2) ||
    (dim_a == 0 && dim_b == 1) {
    return self.m[0] == -1 &&
      (is_true(self.m[1]) || is_true(self.m[3]) || is_true(self.m[4]))
  }
  false
}

///|
/// `isCrosses` for geometries of dimensions `dim_a` and `dim_b`.
pub fn Matrix::is_crosses(self : Matrix, dim_a : Int32, dim_b : Int32) -> Bool {
  if (dim_a == 0 && dim_b == 1) ||
    (dim_a == 0 && dim_b == 2) ||
    (dim_a == 1 && dim_b == 2) {
    return is_true(self.m[0]) && is_true(self.m[2])
  }
  if (dim_a == 1 && dim_b == 0) ||
    (dim_a == 2 && dim_b == 0) ||
    (dim_a == 2 && dim_b == 1) {
    return is_true(self.m[0]) && is_true(self.m[6])
  }
  if dim_a == 1 && dim_b == 1 {
    return self.m[0] == 0
  }
  false
}

///|
/// `isOverlaps` for geometries of dimensions `dim_a` and `dim_b`.
pub fn Matrix::is_overlaps(self : Matrix, dim_a : Int32, dim_b : Int32) -> Bool {
  if (dim_a == 0 && dim_b == 0) || (dim_a == 2 && dim_b == 2) {
    return is_true(self.m[0]) && is_true(self.m[2]) && is_true(self.m[6])
  }
  if dim_a == 1 && dim_b == 1 {
    return self.m[0] == 1 && is_true(self.m[2]) && is_true(self.m[6])
  }
  false
}

///|
/// `isEquals` for geometries of dimensions `dim_a` and `dim_b`.
pub fn Matrix::is_equals(self : Matrix, dim_a : Int32, dim_b : Int32) -> Bool {
  if dim_a != dim_b {
    return false
  }
  is_true(self.m[0]) &&
  self.m[2] == -1 &&
  self.m[5] == -1 &&
  self.m[6] == -1 &&
  self.m[7] == -1
}
