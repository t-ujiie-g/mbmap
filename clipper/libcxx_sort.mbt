// Port of libc++'s std::sort (LLVM 21, __algorithm/sort.h), Apache 2.0 with
// LLVM Exceptions; see NOTICE. Ties in Clipper2's intersection list must come
// out in the order the C++ library gives them.

///|
fn[T] swap_at(a : Array[T], i : Int32, j : Int32) -> Unit {
  let t = a[i]
  a[i] = a[j]
  a[j] = t
}

///|
fn[T] sort3(
  a : Array[T],
  x : Int32,
  y : Int32,
  z : Int32,
  c : (T, T) -> Bool,
) -> Unit {
  if !c(a[y], a[x]) {
    if !c(a[z], a[y]) {
      return
    }
    swap_at(a, y, z)
    if c(a[y], a[x]) {
      swap_at(a, x, y)
    }
    return
  }
  if c(a[z], a[y]) {
    swap_at(a, x, z)
    return
  }
  swap_at(a, x, y)
  if c(a[z], a[y]) {
    swap_at(a, y, z)
  }
}

///|
fn[T] sort4(
  a : Array[T],
  x1 : Int32,
  x2 : Int32,
  x3 : Int32,
  x4 : Int32,
  c : (T, T) -> Bool,
) -> Unit {
  sort3(a, x1, x2, x3, c)
  if c(a[x4], a[x3]) {
    swap_at(a, x3, x4)
    if c(a[x3], a[x2]) {
      swap_at(a, x2, x3)
      if c(a[x2], a[x1]) {
        swap_at(a, x1, x2)
      }
    }
  }
}

///|
fn[T] sort5(
  a : Array[T],
  x1 : Int32,
  x2 : Int32,
  x3 : Int32,
  x4 : Int32,
  x5 : Int32,
  c : (T, T) -> Bool,
) -> Unit {
  sort4(a, x1, x2, x3, x4, c)
  if c(a[x5], a[x4]) {
    swap_at(a, x4, x5)
    if c(a[x4], a[x3]) {
      swap_at(a, x3, x4)
      if c(a[x3], a[x2]) {
        swap_at(a, x2, x3)
        if c(a[x2], a[x1]) {
          swap_at(a, x1, x2)
        }
      }
    }
  }
}

///|
fn[T] insertion_sort(
  a : Array[T],
  first : Int32,
  last : Int32,
  c : (T, T) -> Bool,
) -> Unit {
  if first == last {
    return
  }
  for i in (first + 1)..<last {
    let mut j = i - 1
    if c(a[i], a[j]) {
      let t = a[i]
      let mut k = j
      j = i
      while true {
        a[j] = a[k]
        j = k
        if j == first {
          break
        }
        k -= 1
        if !c(t, a[k]) {
          break
        }
      }
      a[j] = t
    }
  }
}

///|
/// Insertion sort relying on an element no greater than the range just before
/// `first`.
fn[T] insertion_sort_unguarded(
  a : Array[T],
  first : Int32,
  last : Int32,
  c : (T, T) -> Bool,
) -> Unit {
  if first == last {
    return
  }
  for i in (first + 1)..<last {
    let mut j = i - 1
    if c(a[i], a[j]) {
      let t = a[i]
      let mut k = j
      j = i
      while true {
        a[j] = a[k]
        j = k
        k -= 1
        if !c(t, a[k]) {
          break
        }
      }
      a[j] = t
    }
  }
}

///|
/// Insertion sort that gives up after 8 moves; whether it finished.
fn[T] insertion_sort_incomplete(
  a : Array[T],
  first : Int32,
  last : Int32,
  c : (T, T) -> Bool,
) -> Bool {
  match last - first {
    0 | 1 => return true
    2 => {
      if c(a[last - 1], a[first]) {
        swap_at(a, first, last - 1)
      }
      return true
    }
    3 => {
      sort3(a, first, first + 1, last - 1, c)
      return true
    }
    4 => {
      sort4(a, first, first + 1, first + 2, last - 1, c)
      return true
    }
    5 => {
      sort5(a, first, first + 1, first + 2, first + 3, last - 1, c)
      return true
    }
    _ => ()
  }
  let mut j = first + 2
  sort3(a, first, first + 1, j, c)
  let mut count = 0
  let mut i = j + 1
  while i != last {
    if c(a[i], a[j]) {
      let t = a[i]
      let mut k = j
      j = i
      while true {
        a[j] = a[k]
        j = k
        if j == first {
          break
        }
        k -= 1
        if !c(t, a[k]) {
          break
        }
      }
      a[j] = t
      count += 1
      if count == 8 {
        return i + 1 == last
      }
    }
    j = i
    i += 1
  }
  true
}

///|
/// Partitions around the pivot at `first`, equal elements to its right: the
/// pivot's place and whether the range was already partitioned.
fn[T] partition_with_equals_on_right(
  a : Array[T],
  first : Int32,
  last : Int32,
  c : (T, T) -> Bool,
) -> (Int32, Bool) {
  let begin = first
  let pivot = a[first]
  let mut first = first
  let mut last = last
  while true {
    first += 1
    if !c(a[first], pivot) {
      break
    }
  }
  if begin == first - 1 {
    while first < last {
      last -= 1
      if c(a[last], pivot) {
        break
      }
    }
  } else {
    while true {
      last -= 1
      if c(a[last], pivot) {
        break
      }
    }
  }
  let already_partitioned = first >= last
  while first < last {
    swap_at(a, first, last)
    while true {
      first += 1
      if !c(a[first], pivot) {
        break
      }
    }
    while true {
      last -= 1
      if c(a[last], pivot) {
        break
      }
    }
  }
  let pivot_pos = first - 1
  if begin != pivot_pos {
    a[begin] = a[pivot_pos]
  }
  a[pivot_pos] = pivot
  (pivot_pos, already_partitioned)
}

///|
/// Partitions around the pivot at `first`, equal elements to its left: the
/// start of the elements greater than the pivot.
fn[T] partition_with_equals_on_left(
  a : Array[T],
  first : Int32,
  last : Int32,
  c : (T, T) -> Bool,
) -> Int32 {
  let begin = first
  let pivot = a[first]
  let mut first = first
  let mut last = last
  if c(pivot, a[last - 1]) {
    while true {
      first += 1
      if c(pivot, a[first]) {
        break
      }
    }
  } else {
    first += 1
    while first < last && !c(pivot, a[first]) {
      first += 1
    }
  }
  if first < last {
    while true {
      last -= 1
      if !c(pivot, a[last]) {
        break
      }
    }
  }
  while first < last {
    swap_at(a, first, last)
    while true {
      first += 1
      if c(pivot, a[first]) {
        break
      }
    }
    while true {
      last -= 1
      if !c(pivot, a[last]) {
        break
      }
    }
  }
  let pivot_pos = first - 1
  if begin != pivot_pos {
    a[begin] = a[pivot_pos]
  }
  a[pivot_pos] = pivot
  first
}

///|
fn[T] introsort(
  a : Array[T],
  first : Int32,
  last : Int32,
  c : (T, T) -> Bool,
  depth : Int32,
  leftmost : Bool,
) -> Unit {
  let mut first = first
  let mut last = last
  let mut depth = depth
  let mut leftmost = leftmost
  while true {
    let len = last - first
    match len {
      0 | 1 => return
      2 => {
        if c(a[last - 1], a[first]) {
          swap_at(a, first, last - 1)
        }
        return
      }
      3 => {
        sort3(a, first, first + 1, last - 1, c)
        return
      }
      4 => {
        sort4(a, first, first + 1, first + 2, last - 1, c)
        return
      }
      5 => {
        sort5(a, first, first + 1, first + 2, first + 3, last - 1, c)
        return
      }
      _ => ()
    }
    if len < 24 {
      if leftmost {
        insertion_sort(a, first, last, c)
      } else {
        insertion_sort_unguarded(a, first, last, c)
      }
      return
    }
    if depth == 0 {
      // libc++ falls back to heap sort here (only past 2 log2(n) levels).
      let part = a[first:last].to_owned()
      stable_sort(part, c)
      for i, v in part {
        a[first + i] = v
      }
      return
    }
    depth -= 1
    let half = len / 2
    if len > 128 {
      sort3(a, first, first + half, last - 1, c)
      sort3(a, first + 1, first + (half - 1), last - 2, c)
      sort3(a, first + 2, first + (half + 1), last - 3, c)
      sort3(a, first + (half - 1), first + half, first + (half + 1), c)
      swap_at(a, first, first + half)
    } else {
      sort3(a, first + half, first, last - 1, c)
    }
    if !leftmost && !c(a[first - 1], a[first]) {
      first = partition_with_equals_on_left(a, first, last, c)
      continue
    }
    let (i, partitioned) = partition_with_equals_on_right(a, first, last, c)
    if partitioned {
      let fs = insertion_sort_incomplete(a, first, i, c)
      if insertion_sort_incomplete(a, i + 1, last, c) {
        if fs {
          return
        }
        last = i
        continue
      } else if fs {
        first = i + 1
        continue
      }
    }
    introsort(a, first, i, c, depth, leftmost)
    leftmost = false
    first = i + 1
  }
}

///|
/// Sorts `a` by `less` as libc++'s std::sort does (not stable).
fn[T] libcxx_sort(a : Array[T], less : (T, T) -> Bool) -> Unit {
  let n = a.length()
  if n < 2 {
    return
  }
  let mut log2 = 0
  while 1 << (log2 + 1) <= n {
    log2 += 1
  }
  introsort(a, 0, n, less, 2 * log2, true)
}
