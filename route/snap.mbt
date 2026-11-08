///|
/// The most (segment, grid cell) entries `snap_lines` makes.
pub const MAX_SNAP_CELLS : Int32 = 8_000_000

///|
/// The most grid cells and distances `snap_lines` looks at.
pub const MAX_SNAP_TESTS : Int64 = 200_000_000L

///|
/// Meters per degree of latitude on Turf's sphere.
const METERS_PER_DEGREE : Double = @core.EARTH_RADIUS * @core.PI / 180.0

///|
fn min2(a : Double, b : Double) -> Double {
  if b < a {
    b
  } else {
    a
  }
}

///|
fn max2(a : Double, b : Double) -> Double {
  if b > a {
    b
  } else {
    a
  }
}

///|
/// Where the segment from `(ax, ay)` to `(bx, by)` comes nearest to
/// `(px, py)`: its parameter and the squared distance in degrees of latitude,
/// longitudes scaled by `c`, the cosine of `py` (an equirectangular plane).
fn nearest_on(
  px : Double,
  py : Double,
  c : Double,
  ax : Double,
  ay : Double,
  bx : Double,
  by : Double,
) -> (Double, Double) {
  let ux = (ax - px) * c
  let uy = ay - py
  let vx = (bx - ax) * c
  let vy = by - ay
  let len2 = vx * vx + vy * vy
  let t = if len2 > 0.0 {
    max2(0.0, min2(1.0, -(ux * vx + uy * vy) / len2))
  } else {
    0.0
  }
  let dx = ux + t * vx
  let dy = uy + t * vy
  (t, dx * dx + dy * dy)
}

///|
/// A uniform grid of cells `size` degrees wide, each listing items in a chain
/// (`next`), over the box from `lo` to `hi` the data fills.
priv struct Grid {
  size : Double
  heads : PairIndex
  item : Array[Int32]
  next : Array[Int32]
  lo : (Double, Double)
  hi : (Double, Double)
  max_tests : Int64
}

///|
fn Grid::cell(self : Grid, v : Double) -> Int64 {
  (v / self.size).floor().to_int64()
}

///|
fn Grid::add(self : Grid, cx : Int64, cy : Int64, item : Int32) -> Unit {
  self.item.push(item)
  self.next.push(self.heads.get(cx, cy))
  self.heads.set(cx, cy, self.item.length() - 1)
}

///|
/// Calls `f` on the items of the cells within `r` degrees of latitude of
/// `(x, y)` at cosine `c`, counting cells and items in `tests`; false once
/// `tests` passes `max_tests`.
fn Grid::near(
  self : Grid,
  x : Double,
  y : Double,
  r : Double,
  c : Double,
  tests : Ref[Int64],
  f : (Int32) -> Unit,
) -> Bool {
  let rx = r / max2(c, 1.0e-12)
  let x0 = self.cell(max2(x - rx, self.lo.0))
  let x1 = self.cell(min2(x + rx, self.hi.0))
  let y0 = self.cell(max2(y - r, self.lo.1))
  let y1 = self.cell(min2(y + r, self.hi.1))
  for cx = x0; cx <= x1; cx = cx + 1L {
    for cy = y0; cy <= y1; cy = cy + 1L {
      tests.val += 1L
      let mut e = self.heads.get(cx, cy)
      while e >= 0 {
        tests.val += 1L
        f(self.item[e])
        e = self.next[e]
      }
      if tests.val > self.max_tests {
        return false
      }
    }
  }
  true
}

///|
/// The lines (ranges of points in `coords`) noded within `snap` meters as
/// AGENTS.md "Routing" describes; None for coordinates that are not finite or
/// past `MAX_SNAP_CELLS` or `MAX_SNAP_TESTS`.
pub fn snap_lines(
  coords : Array[Double],
  lines : Array[(Int32, Int32)],
  snap : Double,
  trig~ : @core.Trig = @core.Trig::moonbit(),
) -> (Array[Double], Array[(Int32, Int32)])? {
  snap_within(coords, lines, snap, trig, MAX_SNAP_CELLS, MAX_SNAP_TESTS)
}

///|
fn snap_within(
  coords : Array[Double],
  lines : Array[(Int32, Int32)],
  snap : Double,
  trig : @core.Trig,
  max_cells : Int32,
  max_tests : Int64,
) -> (Array[Double], Array[(Int32, Int32)])? {
  guard snap > 0.0 && snap.is_finite() else { return Some((coords, lines)) }
  let n = coords.length() / 2
  let mut minx = @double.infinity
  let mut miny = @double.infinity
  let mut maxx = @double.neg_infinity
  let mut maxy = @double.neg_infinity
  let mut extent = 0.0
  let mut segments = 0
  for line in lines {
    for i in line.0..<line.1 {
      let x = coords[i * 2]
      let y = coords[i * 2 + 1]
      guard x.is_finite() && y.is_finite() else { return None }
      minx = min2(minx, x)
      maxx = max2(maxx, x)
      miny = min2(miny, y)
      maxy = max2(maxy, y)
      if i > line.0 {
        extent += max2(
          (x - coords[i * 2 - 2]).abs(),
          (y - coords[i * 2 - 1]).abs(),
        )
        segments += 1
      }
    }
  }
  let r = snap / METERS_PER_DEGREE
  let r2 = r * r
  let size = max2(
    r,
    if segments > 0 {
      extent / segments.to_double()
    } else {
      r
    },
  )
  let grid = (item : Int32) => {
    let g : Grid = {
      size,
      heads: PairIndex::new(item),
      item: [],
      next: [],
      lo: (minx, miny),
      hi: (maxx, maxy),
      max_tests,
    }
    g
  }
  // Along each line from its start, in meters; `line_of` each point.
  let along = FixedArray::make(n, 0.0)
  let line_of = FixedArray::make(n, -1)
  for l, line in lines {
    for i in line.0..<line.1 {
      line_of[i] = l
      if i > line.0 {
        along[i] = along[i - 1] +
          distance(
            trig,
            coords[i * 2 - 2],
            coords[i * 2 - 1],
            coords[i * 2],
            coords[i * 2 + 1],
          ) *
          1000.0
      }
    }
  }
  let tests = Ref(0L)
  // Ends (2l and 2l + 1 of line l) join the earliest group within `snap`,
  // which stands at its first end.
  let ends = lines.length() * 2
  let rep = FixedArray::make(ends, -1)
  let reps = grid(ends)
  let rep_x : Array[Double] = []
  let rep_y : Array[Double] = []
  let first_end : Array[Int32] = []
  let next_end = FixedArray::make(ends, -1)
  for e in 0..<ends {
    let (i0, i1) = lines[e / 2]
    if i1 - i0 < 2 {
      continue
    }
    let p = if e % 2 == 0 { i0 } else { i1 - 1 }
    let x = coords[p * 2]
    let y = coords[p * 2 + 1]
    let c = trig.cos(y * (@core.PI / 180.0))
    let short = along[i1 - 1] <= 2.0 * snap
    let mut best = -1
    let mut best_d = r2
    let ok = reps.near(x, y, r, c, tests, g => {
      if short && e % 2 == 1 && g == rep[e - 1] {
        return
      }
      let dx = (rep_x[g] - x) * c
      let dy = rep_y[g] - y
      let d = dx * dx + dy * dy
      if d < best_d || (d == best_d && (best < 0 || g < best)) {
        best = g
        best_d = d
      }
    })
    guard ok else { return None }
    if best >= 0 {
      rep[e] = best
      next_end[e] = first_end[best]
      first_end[best] = e
    } else {
      rep[e] = rep_x.length()
      reps.add(reps.cell(x), reps.cell(y), rep_x.length())
      rep_x.push(x)
      rep_y.push(y)
      first_end.push(e)
    }
  }
  // Segments by their first point, in every cell their bounding strip meets.
  let segs = grid(segments)
  for line in lines {
    for i in line.0..<(line.1 - 1) {
      let ax = coords[i * 2]
      let ay = coords[i * 2 + 1]
      let bx = coords[i * 2 + 2]
      let by = coords[i * 2 + 3]
      let x0 = min2(ax, bx)
      let x1 = max2(ax, bx)
      let slack = size * 1.0e-9
      for cx = segs.cell(x0); cx <= segs.cell(x1); cx = cx + 1L {
        let lo = max2(x0, cx.to_double() * size)
        let hi = min2(x1, (cx + 1L).to_double() * size)
        let (ylo, yhi) = if x1 > x0 {
          let y_lo = ay + (lo - ax) / (bx - ax) * (by - ay)
          let y_hi = ay + (hi - ax) / (bx - ax) * (by - ay)
          (min2(y_lo, y_hi), max2(y_lo, y_hi))
        } else {
          (min2(ay, by), max2(ay, by))
        }
        for cy = segs.cell(ylo - slack)
            cy <= segs.cell(yhi + slack)
            cy = cy + 1L {
          if segs.item.length() >= max_cells {
            return None
          }
          segs.add(cx, cy, i)
        }
      }
    }
  }
  // Each group to the nearest segment of another line, or of its own away
  // from its end.
  let at_x = FixedArray::from_array(rep_x)
  let at_y = FixedArray::from_array(rep_y)
  let first_insert = FixedArray::make(n, -1)
  let insert_t : Array[Double] = []
  let insert_rep : Array[Int32] = []
  let next_insert : Array[Int32] = []
  let follow = FixedArray::make(rep_x.length(), -1)
  for g in 0..<rep_x.length() {
    let x = rep_x[g]
    let y = rep_y[g]
    let c = trig.cos(y * (@core.PI / 180.0))
    let mut best = -1
    let mut best_d = r2
    let mut best_t = 0.0
    let ok = segs.near(x, y, r, c, tests, s => {
      let l = line_of[s]
      let mut e = first_end[g]
      while e >= 0 {
        let gap = if e % 2 == 0 {
          along[s]
        } else {
          along[lines[l].1 - 1] - along[s + 1]
        }
        if e / 2 == l && gap <= 2.0 * snap {
          return
        }
        e = next_end[e]
      }
      let (t, d) = nearest_on(
        x,
        y,
        c,
        coords[s * 2],
        coords[s * 2 + 1],
        coords[s * 2 + 2],
        coords[s * 2 + 3],
      )
      if d < best_d || (d == best_d && (best < 0 || s < best)) {
        best = s
        best_d = d
        best_t = t
      }
    })
    guard ok else { return None }
    guard best >= 0 else { continue }
    let s = best
    let (i0, i1) = lines[line_of[s]]
    if best_t <= 0.0 && s == i0 {
      follow[g] = rep[line_of[s] * 2]
    } else if best_t >= 1.0 && s + 2 == i1 {
      follow[g] = rep[line_of[s] * 2 + 1]
    } else if best_t <= 0.0 {
      at_x[g] = coords[s * 2]
      at_y[g] = coords[s * 2 + 1]
    } else if best_t >= 1.0 {
      at_x[g] = coords[s * 2 + 2]
      at_y[g] = coords[s * 2 + 3]
    } else {
      at_x[g] = coords[s * 2] + best_t * (coords[s * 2 + 2] - coords[s * 2])
      at_y[g] = coords[s * 2 + 1] +
        best_t * (coords[s * 2 + 3] - coords[s * 2 + 1])
      let mut prev = -1
      let mut k = first_insert[s]
      while k >= 0 && insert_t[k] <= best_t {
        prev = k
        k = next_insert[k]
      }
      insert_t.push(best_t)
      insert_rep.push(g)
      next_insert.push(k)
      if prev >= 0 {
        next_insert[prev] = insert_rep.length() - 1
      } else {
        first_insert[s] = insert_rep.length() - 1
      }
    }
  }
  // A group snapped to another's end goes where that one goes; in a cycle
  // the group met again stays.
  let done = FixedArray::make(rep_x.length(), false)
  for g in 0..<rep_x.length() {
    let path = []
    let mut h = g
    while !done[h] && follow[h] >= 0 && follow[h] != h {
      done[h] = true
      path.push(h)
      h = follow[h]
    }
    done[h] = true
    for p in path {
      at_x[p] = at_x[h]
      at_y[p] = at_y[h]
    }
  }
  let out : Array[Double] = Array(
    capacity=coords.length() + insert_rep.length() * 2,
  )
  let ranges : Array[(Int32, Int32)] = Array(capacity=lines.length())
  for l, line in lines {
    let start = out.length() / 2
    for i in line.0..<line.1 {
      let e = if i == line.0 {
        2 * l
      } else if i == line.1 - 1 {
        2 * l + 1
      } else {
        -1
      }
      if e >= 0 && rep[e] >= 0 {
        out.push(at_x[rep[e]])
        out.push(at_y[rep[e]])
      } else {
        out.push(coords[i * 2])
        out.push(coords[i * 2 + 1])
      }
      let mut k = first_insert[i]
      while k >= 0 {
        out.push(at_x[insert_rep[k]])
        out.push(at_y[insert_rep[k]])
        k = next_insert[k]
      }
    }
    ranges.push((start, out.length() / 2))
  }
  Some((out, ranges))
}
