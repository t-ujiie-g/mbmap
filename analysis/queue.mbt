// Ported from flatqueue 3.1.0: ISC License, Copyright (c) 2025, Volodymyr
// Agafonkin. See NOTICE.

///|
/// flatqueue: a binary min-heap of ids by priority.
priv struct Queue {
  mut ids : FixedArray[Int32]
  mut values : FixedArray[Double]
  mut length : Int32
}

///|
fn Queue::new() -> Queue {
  {
    ids: FixedArray::make(64, 0),
    values: FixedArray::make(64, 0.0),
    length: 0,
  }
}

///|
fn Queue::push(self : Queue, id : Int32, priority : Double) -> Unit {
  if self.length == self.ids.length() {
    let ids = FixedArray::make(self.length * 2, 0)
    let values = FixedArray::make(self.length * 2, 0.0)
    for i in 0..<self.length {
      ids[i] = self.ids[i]
      values[i] = self.values[i]
    }
    self.ids = ids
    self.values = values
  }
  let ids = self.ids
  let values = self.values
  let mut pos = self.length
  self.length += 1
  while pos > 0 {
    let parent = (pos - 1) >> 1
    let pv = values[parent]
    if priority >= pv {
      break
    }
    ids[pos] = ids[parent]
    values[pos] = pv
    pos = parent
  }
  ids[pos] = id
  values[pos] = priority
}

///|
fn Queue::pop(self : Queue) -> Unit {
  if self.length == 0 {
    return
  }
  self.length -= 1
  let last = self.length
  let ids = self.ids
  let values = self.values
  if last > 0 {
    let id = ids[last]
    let value = values[last]
    let mut pos = 0
    let half = last >> 1
    while pos < half {
      let left = (pos << 1) + 1
      let right = left + 1
      let child = if right < last && values[right] < values[left] {
        right
      } else {
        left
      }
      if values[child] >= value {
        break
      }
      ids[pos] = ids[child]
      values[pos] = values[child]
      pos = child
    }
    ids[pos] = id
    values[pos] = value
  }
}
