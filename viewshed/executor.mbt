// GDAL 3.13.3's alg/viewshed/viewshed_executor.cpp (MIT License, (c) 2024
// info@hobu.co; see NOTICE) on one thread: its up and down scans each start
// from the observer's line, so running them in turn gives the same values.

///|
/// `LineLimits`: the left side spans [left, left_min), the right side
/// [right_min, right).
priv struct Limits {
  mut left : Int32
  mut left_min : Int32
  mut right_min : Int32
  mut right : Int32
}

///|
/// `Lines`: the line being processed (heights relative to the observer), its
/// result, the previous line's horizon heights and the pitch mask.
priv struct Lines {
  cur : FixedArray[Double]
  result : FixedArray[Double]
  prev : FixedArray[Double]
  pitch_mask : FixedArray[Double]
}

///|
fn Lines::new(n : Int32) -> Lines {
  {
    cur: FixedArray::make(n, 0.0),
    result: FixedArray::make(n, 0.0),
    prev: FixedArray::make(n, 0.0),
    pitch_mask: FixedArray::make(n, @double.not_a_number),
  }
}

///|
/// `ViewshedExecutor` without the standard-deviation band. `nx` is relative to
/// the output window, `ny` to the input raster; input cell (x, y) is
/// `values[y * width + x - first]`.
priv struct Executor {
  trig : @core.Trig
  values : FixedArray[Double]
  width : Int32
  first : Int32
  x_start : Int32
  y_start : Int32
  y_stop : Int32
  xsize : Int32
  nx : Int32
  ny : Int32
  gt : FixedArray[Double]
  mode : ViewshedMode
  cell_mode : CellMode
  target_height : Double
  visible : Double
  invisible : Double
  out_of_range : Double
  observer_height : Double
  start_angle : Double
  end_angle : Double
  angle_masking : Bool
  low_pitch_masking : Bool
  high_pitch_masking : Bool
  low_tan : Double
  high_tan : Double
  test_angle : FixedArray[Double]
  height_adj : Double
  adj_high : Double
  squares : FixedArray[Double]
  min2 : Double
  max2 : Double
  mut z_observer : Double
  has_nodata : Bool
  nodata : Double
  mut found_nodata : Bool
  output : FixedArray[Double]
}

///|
/// `std::fill` over [from, to), kept inside the line (GDAL writes past it for
/// an observer outside the raster with a min distance).
fn fill(a : FixedArray[Double], from : Int32, to : Int32, v : Double) -> Unit {
  let lo = max_int(from, 0)
  let hi = min_int(to, a.length())
  for i in lo..<hi {
    a[i] = v
  }
}

///|
fn Executor::contains_x(self : Executor, x : Int32) -> Bool {
  x >= 0 && x < self.xsize
}

///|
fn Executor::clamp_x(self : Executor, x : Int32) -> Int32 {
  clamp_int(x, 0, self.xsize - 1)
}

///|
/// Height on the line from the observer at `n` cells given the one at `n - 1`.
fn height_line(n : Int32, za : Double) -> Double {
  za * n.to_double() / (n - 1).to_double()
}

///|
fn height_line3(n : Int32, zcur : Double, za : Double) -> Double {
  let n = n.abs()
  if n == 1 {
    zcur
  } else {
    height_line(n, za)
  }
}

///|
fn height_diagonal(i : Int32, j : Int32, za : Double, zb : Double) -> Double {
  fma(za, i.to_double(), zb * j.to_double()) / (i + j - 1).to_double()
}

///|
fn height_edge(i : Int32, j : Int32, za : Double, zb : Double) -> Double {
  fma(za, i.to_double(), zb * (j - i).to_double()) / (j - 1).to_double()
}

///|
/// The `Edge` height of `zcalc`.
fn edge(
  x : Int32,
  y : Int32,
  this_prev : Double,
  last : Double,
  last_prev : Double,
) -> Double {
  if x >= y {
    height_edge(y, x, last_prev, this_prev)
  } else {
    height_edge(x, y, last_prev, last)
  }
}

///|
/// `oZcalc`: `this_prev` is the cell toward the observer on this line, `last`
/// the cell above (or below) on the previous line, `last_prev` the diagonal.
fn Executor::zcalc(
  self : Executor,
  x : Int32,
  y : Int32,
  this_prev : Double,
  last : Double,
  last_prev : Double,
) -> Double {
  match self.cell_mode {
    Edge => edge(x, y, this_prev, last, last_prev)
    Diagonal => height_diagonal(x, y, this_prev, last)
    Min => {
      let e = edge(x, y, this_prev, last, last_prev)
      let d = height_diagonal(x, y, this_prev, last)
      if d < e {
        d
      } else {
        e
      }
    }
    Max => {
      let e = edge(x, y, this_prev, last, last_prev)
      let d = height_diagonal(x, y, this_prev, last)
      if e < d {
        d
      } else {
        e
      }
    }
  }
}

///|
/// `setOutputNormal`.
fn Executor::set_output(
  self : Executor,
  lines : Lines,
  pos : Int32,
  z : Double,
) -> Unit {
  let cur = lines.cur[pos]
  if !(self.mode is Normal) {
    let adjustment = z - cur
    if adjustment > 0.0 {
      lines.result[pos] = lines.result[pos] + adjustment
    }
  } else {
    let cell_height = cur + self.target_height
    lines.result[pos] = if cell_height < z {
      self.invisible
    } else {
      self.visible
    }
  }
  lines.cur[pos] = if cur < z { z } else { cur }
}

///|
/// `readLine`: the input row's cells in the window, and the result's start in
/// `Dem` (the DEM) and `Ground` (0) modes.
fn Executor::read_line(self : Executor, line : Int32, lines : Lines) -> Unit {
  let base = line * self.width + self.x_start - self.first
  for i in 0..<self.xsize {
    lines.cur[i] = self.values[base + i]
  }
  match self.mode {
    Dem => lines.cur.blit_to(lines.result, len=self.xsize)
    Ground => lines.result.fill(0.0)
    Normal => ()
  }
}

///|
/// `writeLine`, with the Float64 to Byte conversion of a `Normal` output.
fn Executor::write_line(
  self : Executor,
  line : Int32,
  result : FixedArray[Double],
) -> Unit {
  let base = (line - self.y_start) * self.xsize
  for i in 0..<self.xsize {
    let v = result[i]
    self.output[base + i] = if self.mode is Normal { to_byte(v) } else { v }
  }
}

///|
/// GDALCopyWord from Float64 to Byte: NaN to 0, else rounded half up and
/// clamped.
fn to_byte(v : Double) -> Double {
  if v.is_nan() {
    return 0.0
  }
  let r = v + 0.5
  if r < 0.0 {
    0.0
  } else if r > 255.0 {
    255.0
  } else {
    r.trunc()
  }
}

///|
fn Executor::check_nodata(self : Executor, v : Double) -> Unit {
  if !self.found_nodata && ((self.has_nodata && v == self.nodata) || v.is_nan()) {
    self.found_nodata = true
  }
}

///|
/// The squared distance `adjustHeight` finds to cell `px` (`off` from the
/// observer) on a line `line_x`, `line_y` away. A north-up raster's `dx` is the
/// same on every line, so the square and its error come from `squares`.
fn Executor::distance2(
  self : Executor,
  px : Int32,
  off : Int32,
  line_x : Double,
  line_y : Double,
) -> Double {
  let gt = self.gt
  if self.squares.length() == 0 {
    let dx = fma(gt[1], off.to_double(), line_x)
    let dy = fma(gt[4], off.to_double(), line_y)
    return fma(dx, dx, dy * dy)
  }
  // `gt[4]` is 0, so `dy` is `line_y`.
  let p = self.squares[2 * px]
  let c = line_y * line_y
  if fma_trivial(p, c) {
    p + c
  } else {
    fma_rest(p, self.squares[2 * px + 1], c)
  }
}

///|
/// `fma(height_adj, r2, z_observer)`, with `height_adj` split once.
fn Executor::curvature(self : Executor, r2 : Double) -> Double {
  let p = self.height_adj * r2
  if fma_trivial(p, self.z_observer) {
    p + self.z_observer
  } else {
    let al = self.height_adj - self.adj_high
    fma_rest(p, product_error(self.adj_high, al, r2, p), self.z_observer)
  }
}

///|
/// `squares` of a north-up raster (`gt[2]` and `gt[4]` 0, so `dx` does not
/// depend on the line): each output column's `dx * dx` and its exact error.
fn column_squares(
  gt : FixedArray[Double],
  nx : Int32,
  xsize : Int32,
) -> FixedArray[Double] {
  if gt[2] != 0.0 || gt[4] != 0.0 {
    return []
  }
  let out = FixedArray::make(2 * xsize, 0.0)
  for px in 0..<xsize {
    // `fma(gt[1], off, ±0)` is the product (its zero's sign is squared away).
    let dx = gt[1] * (px - nx).to_double()
    let p = dx * dx
    let dh = high_half(dx)
    out[2 * px] = p
    out[2 * px + 1] = product_error(dh, dx - dh, dx, p)
  }
  out
}

///|
/// `adjustHeight`: heights relative to the observer, lowered by the earth's
/// curvature, and the line's limits by distance.
fn Executor::adjust_height(
  self : Executor,
  y_offset : Int32,
  lines : Lines,
) -> Limits {
  let nx = self.nx
  let ll = { left: 0, left_min: nx + 1, right_min: nx + 1, right: self.xsize, }
  let x_start = self.clamp_x(nx)
  let cur = lines.cur
  let pitch = self.low_pitch_masking || self.high_pitch_masking
  if self.height_adj != 0.0 || pitch || self.max2 > 0.0 || self.min2 > 0.0 {
    let line_x = self.gt[2] * y_offset.to_double()
    let line_y = self.gt[5] * y_offset.to_double()
    let mut off = x_start - nx
    while off >= -nx {
      let px = nx + off
      let r2 = self.distance2(px, off, line_x, line_y)
      if r2 < self.min2 {
        ll.left_min -= 1
      } else if r2 > self.max2 {
        ll.left = off + nx + 1
        break
      }
      self.check_nodata(cur[px])
      cur[px] = cur[px] - self.curvature(r2)
      if pitch {
        self.calc_pitch_mask(cur[px], r2.sqrt(), lines.result[px], lines, px)
      }
      off -= 1
    }
    off = x_start - nx + 1
    while off < self.xsize - nx {
      let px = nx + off
      let r2 = self.distance2(px, off, line_x, line_y)
      if r2 < self.min2 {
        ll.right_min += 1
      } else if r2 > self.max2 {
        ll.right = off + nx
        break
      }
      self.check_nodata(cur[px])
      cur[px] = cur[px] - self.curvature(r2)
      if pitch {
        self.calc_pitch_mask(cur[px], r2.sqrt(), lines.result[px], lines, px)
      }
      off += 1
    }
  } else {
    for i in 0..<self.xsize {
      self.check_nodata(cur[i])
      cur[i] = cur[i] - self.z_observer
    }
  }
  ll
}

///|
/// `calcPitchMask`: NaN leaves the cell, infinity makes it out of range, any
/// other value replaces it.
fn Executor::calc_pitch_mask(
  self : Executor,
  z : Double,
  dist : Double,
  result : Double,
  lines : Lines,
  pos : Int32,
) -> Unit {
  if self.low_pitch_masking {
    let adjustment = dist * self.low_tan - z
    if adjustment > 0.0 {
      lines.pitch_mask[pos] = if self.mode is Normal {
        @double.infinity
      } else {
        adjustment + result
      }
      return
    }
  }
  if self.high_pitch_masking && z > dist * self.high_tan {
    lines.pitch_mask[pos] = @double.infinity
  }
}

///|
fn Executor::apply_pitch_mask(self : Executor, lines : Lines) -> Unit {
  for i in 0..<lines.result.length() {
    let m = lines.pitch_mask[i]
    if m.is_nan() {
      continue
    }
    lines.result[i] = if m.is_inf() { self.out_of_range } else { m }
  }
}

///|
/// `processFirstLine`: the observer's row (or the nearest one in the window).
fn Executor::process_first_line(self : Executor, lines : Lines) -> Unit {
  let nx = self.nx
  let line = clamp_int(self.ny, self.y_start, self.y_stop - 1)
  let y_offset = line - self.ny
  self.read_line(line, lines)
  self.z_observer = self.observer_height
  if self.contains_x(nx) {
    self.z_observer += lines.cur[nx]
  }
  let ll = self.adjust_height(y_offset, lines)
  if self.contains_x(nx) {
    if ll.left_min != ll.right_min {
      lines.result[nx] = self.out_of_range
    } else if self.mode is Normal {
      lines.result[nx] = self.visible
    }
  }
  // GDAL's `Window::containsY` tests y against xStart (0 here).
  if !(self.ny >= 0 && self.ny < self.y_stop) {
    self.first_line_top_or_bottom(ll, lines)
  } else {
    self.first_line_left(ll, lines)
    self.first_line_right(ll, lines)
  }
  lines.cur.blit_to(lines.prev, len=self.xsize)
  if self.low_pitch_masking || self.high_pitch_masking {
    self.apply_pitch_mask(lines)
  }
  self.write_line(line, lines.result)
}

///|
/// `processFirstLineTopOrBottom`: an observer above or below the raster sees
/// every cell of the nearest row in range.
fn Executor::first_line_top_or_bottom(
  self : Executor,
  ll : Limits,
  lines : Lines,
) -> Unit {
  for i in ll.left..<ll.right {
    if self.mode is Normal {
      lines.result[i] = self.visible
    } else {
      self.set_output(lines, i, lines.cur[i])
    }
  }
  fill(lines.result, 0, ll.left, self.out_of_range)
  fill(lines.result, ll.right, self.xsize, self.out_of_range)
}

///|
fn Executor::first_line_left(
  self : Executor,
  ll : Limits,
  lines : Lines,
) -> Unit {
  let nx = self.nx
  let i_end = ll.left - 1
  let mut i_start = nx - 1
  if i_end >= i_start {
    self.mask_line_left(lines.result, ll, self.ny)
    return
  }
  i_start = self.clamp_x(i_start)
  if i_start + 1 == nx || i_start + 1 == self.xsize {
    if self.mode is Normal {
      lines.result[i_start] = self.visible
    } else {
      self.set_output(lines, i_start, lines.cur[i_start])
    }
    i_start -= 1
  }
  let mut i = i_start
  while i > i_end {
    let z = height_line((i - nx).abs(), lines.cur[i + 1])
    self.set_output(lines, i, z)
    i -= 1
  }
  self.mask_line_left(lines.result, ll, self.ny)
}

///|
fn Executor::first_line_right(
  self : Executor,
  ll : Limits,
  lines : Lines,
) -> Unit {
  let nx = self.nx
  let mut i_start = nx + 1
  let i_end = ll.right
  if i_start >= i_end {
    self.mask_line_right(lines.result, ll, self.ny)
    return
  }
  i_start = self.clamp_x(i_start)
  if i_start - 1 == nx || i_start == 0 {
    if self.mode is Normal {
      lines.result[i_start] = self.visible
    } else {
      self.set_output(lines, i_start, lines.cur[i_start])
    }
    i_start += 1
  }
  for i in i_start..<i_end {
    let z = height_line((i - nx).abs(), lines.cur[i - 1])
    self.set_output(lines, i, z)
  }
  self.mask_line_right(lines.result, ll, self.ny)
}

///|
/// `processLineLeft`.
fn Executor::line_left(
  self : Executor,
  y_offset : Int32,
  ll : Limits,
  lines : Lines,
) -> Unit {
  let nx = self.nx
  let mut i_start = nx - 1
  let i_end = ll.left - 1
  let line = self.ny + y_offset
  if i_start <= i_end {
    self.mask_line_left(lines.result, ll, line)
    return
  }
  i_start = self.clamp_x(i_start)
  if i_start == self.xsize - 1 {
    if self.mode is Normal {
      lines.result[i_start] = self.visible
    } else {
      self.set_output(lines, i_start, lines.cur[i_start])
    }
    i_start -= 1
  }
  let dy = y_offset.abs()
  let cur = lines.cur
  let prev = lines.prev
  let mut i = i_start
  while i > i_end {
    let dx = (i - nx).abs()
    let z = if dx == dy {
      height_line3(dy, cur[i], prev[i + 1])
    } else {
      self.zcalc(dx, dy, cur[i + 1], prev[i], prev[i + 1])
    }
    self.set_output(lines, i, z)
    i -= 1
  }
  self.mask_line_left(lines.result, ll, line)
}

///|
/// `processLineRight`.
fn Executor::line_right(
  self : Executor,
  y_offset : Int32,
  ll : Limits,
  lines : Lines,
) -> Unit {
  let nx = self.nx
  let mut i_start = nx + 1
  let i_end = ll.right
  let line = self.ny + y_offset
  if i_start >= i_end {
    self.mask_line_right(lines.result, ll, line)
    return
  }
  i_start = self.clamp_x(i_start)
  if i_start == 0 {
    if self.mode is Normal {
      lines.result[0] = self.visible
    } else {
      self.set_output(lines, 0, lines.cur[0])
    }
    i_start += 1
  }
  let dy = y_offset.abs()
  let cur = lines.cur
  let prev = lines.prev
  for i in i_start..<i_end {
    let dx = (i - nx).abs()
    let z = if dx == dy {
      height_line3(dy, cur[i], prev[i - 1])
    } else {
      self.zcalc(dx, dy, cur[i - 1], prev[i], prev[i - 1])
    }
    self.set_output(lines, i, z)
  }
  self.mask_line_right(lines.result, ll, line)
}

///|
/// `maskAngleLeft`: true when every cell left of the observer was masked.
fn Executor::mask_angle_left(
  self : Executor,
  result : FixedArray[Double],
  line : Int32,
) -> Bool {
  if !self.angle_masking {
    return false
  }
  let nx = self.nx
  let ny = self.ny
  let oor = self.out_of_range
  let in_quadrant = fn(x : Int32) {
    if x < 0 || x >= nx {
      INVALID_ISECT
    } else {
      x
    }
  }
  if line != ny {
    let mut s = in_quadrant(
      h_intersect_row(self.trig, self.start_angle, nx, ny, line),
    )
    let mut e = in_quadrant(
      h_intersect_row(self.trig, self.end_angle, nx, ny, line),
    )
    if s == INVALID_ISECT && e == INVALID_ISECT {
      let probe = if line < ny {
        self.test_angle[2]
      } else {
        self.test_angle[3]
      }
      if !ray_between(self.start_angle, self.end_angle, probe) {
        fill(result, 0, nx, oor)
        return true
      }
      return false
    }
    if line > ny {
      let t = s
      s = e
      e = t
    }
    if s == INVALID_ISECT {
      s = 0
    }
    if e == INVALID_ISECT {
      e = nx - 1
    }
    if s <= e {
      fill(result, 0, s, oor)
      fill(result, e + 1, nx, oor)
    } else {
      fill(result, e + 1, s, oor)
    }
  } else if !ray_between(self.start_angle, self.end_angle, PI) {
    fill(result, 0, nx, oor)
    return true
  }
  false
}

///|
/// `maskAngleRight`: true when every cell right of the observer was masked.
fn Executor::mask_angle_right(
  self : Executor,
  result : FixedArray[Double],
  line : Int32,
) -> Bool {
  if !self.angle_masking {
    return false
  }
  let nx = self.nx
  let ny = self.ny
  let len = result.length()
  let oor = self.out_of_range
  let in_quadrant = fn(x : Int32) {
    if x <= nx || x >= len {
      INVALID_ISECT
    } else {
      x
    }
  }
  if line != ny {
    let mut s = in_quadrant(
      h_intersect_row(self.trig, self.start_angle, nx, ny, line),
    )
    let mut e = in_quadrant(
      h_intersect_row(self.trig, self.end_angle, nx, ny, line),
    )
    if s == INVALID_ISECT && e == INVALID_ISECT {
      let probe = if line < ny {
        self.test_angle[1]
      } else {
        self.test_angle[4]
      }
      if !ray_between(self.start_angle, self.end_angle, probe) {
        fill(result, nx + 1, len, oor)
        return true
      }
      return false
    }
    if line > ny {
      let t = s
      s = e
      e = t
    }
    if e == INVALID_ISECT {
      e = len - 1
    }
    if s == INVALID_ISECT {
      s = nx + 1
    }
    if s <= e {
      fill(result, nx + 1, s, oor)
      fill(result, e + 1, len, oor)
    } else {
      fill(result, e + 1, s, oor)
    }
  } else if !ray_between(self.start_angle, self.end_angle, 0.0) {
    fill(result, nx + 1, len, oor)
    return true
  }
  false
}

///|
fn Executor::mask_line_left(
  self : Executor,
  result : FixedArray[Double],
  ll : Limits,
  line : Int32,
) -> Unit {
  if self.mask_angle_left(result, line) {
    return
  }
  fill(result, 0, ll.left, self.out_of_range)
  if ll.left_min < self.nx {
    fill(result, ll.left_min, self.nx, self.out_of_range)
  }
}

///|
fn Executor::mask_line_right(
  self : Executor,
  result : FixedArray[Double],
  ll : Limits,
  line : Int32,
) -> Unit {
  if self.mask_angle_right(result, line) {
    return
  }
  fill(result, self.nx + 1, ll.right_min, self.out_of_range)
  if ll.right <= result.length() {
    fill(result, ll.right, result.length(), self.out_of_range)
  }
}

///|
/// `maskInitial`: true when the observer's column on this line is masked.
fn Executor::mask_initial(
  self : Executor,
  result : FixedArray[Double],
  ll : Limits,
  line : Int32,
) -> Bool {
  if ll.left >= ll.right || ll.left_min != ll.right_min {
    result[self.nx] = self.out_of_range
    return true
  }
  if !self.angle_masking {
    return false
  }
  let up = 3.0 * PI / 2.0
  if (
      line < self.ny && !ray_between(self.start_angle, self.end_angle, PI / 2.0)
    ) ||
    (line > self.ny && !ray_between(self.start_angle, self.end_angle, up)) {
    result[self.nx] = self.out_of_range
    return true
  }
  false
}

///|
/// `processLine`: a line above or below the observer's.
fn Executor::process_line(self : Executor, line : Int32, lines : Lines) -> Unit {
  let y_offset = line - self.ny
  self.read_line(line, lines)
  let ll = self.adjust_height(y_offset, lines)
  let nx = self.nx
  if self.contains_x(nx) && !self.mask_initial(lines.result, ll, line) {
    let z = height_line3(y_offset.abs(), lines.cur[nx], lines.prev[nx])
    self.set_output(lines, nx, z)
  }
  self.line_left(y_offset, ll, lines)
  self.line_right(y_offset, ll, lines)
  lines.cur.blit_to(lines.prev, len=self.xsize)
  if self.low_pitch_masking || self.high_pitch_masking {
    self.apply_pitch_mask(lines)
  }
  self.write_line(line, lines.result)
}

///|
/// `calcTestAngles`: rays to the middle of each quadrant's top or bottom.
fn Executor::calc_test_angles(self : Executor) -> Unit {
  let nx = self.nx
  let ny = self.ny
  let xstop = self.xsize
  let atan2 = self.trig.atan2
  let ta = self.test_angle
  ta[1] = atan2((ny + 1).to_double(), (xstop - nx).to_double() / 2.0)
  ta[2] = atan2((ny + 1).to_double(), (-(nx + 1)).to_double() / 2.0)
  ta[3] = atan2(
    (-(self.y_stop - ny)).to_double(),
    (-(nx + 1)).to_double() / 2.0,
  )
  ta[4] = atan2(
    (-(self.y_stop - ny)).to_double(),
    (xstop - nx).to_double() / 2.0,
  )
  for i in 1..<=4 {
    if ta[i] < 0.0 {
      ta[i] += 2.0 * PI
    }
  }
}

///|
/// `ViewshedExecutor::run`, the two scans one after the other.
fn Executor::run(self : Executor) -> Unit {
  if self.angle_masking {
    self.calc_test_angles()
  }
  let first = Lines::new(self.xsize)
  self.process_first_line(first)
  let y0 = clamp_int(self.ny, self.y_start, self.y_stop - 1)
  let pitch = self.low_pitch_masking || self.high_pitch_masking
  let up = Lines::new(self.xsize)
  first.prev.blit_to(up.prev, len=self.xsize)
  let mut line = y0 - 1
  while line >= self.y_start {
    self.process_line(line, up)
    if pitch {
      up.pitch_mask.fill(@double.not_a_number)
    }
    line -= 1
  }
  let down = Lines::new(self.xsize)
  first.prev.blit_to(down.prev, len=self.xsize)
  for l in (y0 + 1)..<self.y_stop {
    self.process_line(l, down)
    if pitch {
      down.pitch_mask.fill(@double.not_a_number)
    }
  }
}
