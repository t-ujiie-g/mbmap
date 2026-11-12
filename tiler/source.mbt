// Ported from @maplibre/geojson-vt 6.3.0 (src/difference.ts and the updateable
// parts of src/geojsonvt.ts and src/convert.ts): MIT License, Copyright (c)
// 2025 MapLibre contributors, and ISC License, Copyright (c) 2024, Mapbox. See NOTICE.

///|
/// An updateable geojson-vt index's `source` (`features`, whose table rows hold properties and ids)
/// and `unlocated` (by `id_key`, at a row; -1 once located). Changed features get new rows without
/// geometry, which nothing reads once converted; `compacted` is the rows after the last compaction.
priv struct Source {
  table : @geom.Table
  mut features : Array[FRef]
  mut unlocated : Map[String, Int32]
  promote_id : String?
  sq_tolerance : Double
  metrics : Bool
  wrap : Double?
  trig : Trig
  mut compacted : Int32
  mut epoch : Int32
}

///|
/// An id as a key that tells ids apart as a JavaScript `Map` does: `-0` is 0,
/// an absent id is not `null`, `1` is not `"1"`.
fn id_key(k : @geom.Prop?) -> String {
  match k {
    None => ""
    Some(Null) => "l"
    Some(Bool(b)) => if b { "t" } else { "f" }
    Some(Num(n)) => {
      let bits = (if n == 0.0 { 0.0 } else { n }).reinterpret_as_int64()
      let chars = Array::make(17, 'n')
      for i in 0..<16 {
        chars[i + 1] = (0x61 + ((bits >> (i * 4)).to_int() & 15)).unsafe_to_char()
      }
      String::from_array(chars)
    }
    Some(Str(s)) => "s" + s
  }
}

///|
/// Whether geojson-vt keeps features without coordinates under this id
/// (`id == null` does not).
fn kept_key(k : @geom.Prop?) -> Bool {
  !(k is (None | Some(Null)))
}

///|
/// Converts `table` (its features ending at `feature_ends`, a row each by
/// default) and wraps the result when `wrap` gives the buffer.
fn Source::new(
  table : @geom.Table,
  feature_ends : Array[Int32]?,
  promote_id : String?,
  sq_tolerance : Double,
  metrics : Bool,
  wrap : Double?,
  trig : Trig,
) -> Source {
  let src : Source = {
    table,
    features: [],
    unlocated: Map([]),
    promote_id,
    sq_tolerance,
    metrics,
    wrap,
    trig,
    compacted: table.length(),
    epoch: 0,
  }
  if promote_id is Some(_) {
    for row in 0..<table.length() {
      table.ids[row] = key_of(table, row, promote_id)
    }
  }
  let converted = convert(table, sq_tolerance, trig, metrics~)
  let located = Array::make(table.length(), false)
  for f in converted {
    located[f.row()] = true
  }
  let ends = match feature_ends {
    Some(e) => e
    None => Array::makei(table.length(), r => r + 1)
  }
  for f, end in ends {
    let start = @geom.start_of(ends, f)
    guard start < end && kept_key(table.ids[start]) else { continue }
    let mut row = start
    for r in start..<end {
      if located[r] {
        row = -1
      }
    }
    src.unlocated[id_key(table.ids[start])] = row
  }
  src.features = src.wrapped(converted)
  src
}

///|
/// The id geojson-vt's `getFeatureId` gives row `row` of `table`.
fn key_of(
  table : @geom.Table,
  row : Int32,
  promote_id : String?,
) -> @geom.Prop? {
  match promote_id {
    Some(k) => table.column(k).bind(c => c.values[row])
    None => table.ids[row]
  }
}

///|
fn Source::wrapped(self : Source, set : Array[FRef]) -> Array[FRef] {
  match self.wrap {
    Some(buffer) => wrap(set, buffer, metrics=self.metrics)
    None => set
  }
}

///|
/// The key of feature `f`: geojson-vt's `createFeature` makes an absent id `null`.
fn Source::key(self : Source, f : FRef) -> String {
  match self.table.ids[f.row()] {
    None => id_key(Some(Null))
    id => id_key(id)
  }
}

///|
/// The row of the feature without coordinates under `k`, if any.
fn Source::unlocated_row(self : Source, k : String) -> Int32? {
  match self.unlocated.get(k) {
    Some(row) if row >= 0 => Some(row)
    _ => None
  }
}

///|
/// The properties of row `r` of `table`, in column order.
fn properties_of(
  table : @geom.Table,
  r : Int32,
) -> Array[(String, @geom.Prop?)] {
  let out = []
  for c in table.columns {
    if c.values[r] is Some(_) {
      out.push((c.name, c.values[r]))
    }
  }
  out
}

///|
/// A new row holding row `row`'s id with `u`'s property changes
/// (geojson-vt's `applyPropertyUpdates`: removing all of them ignores the rest).
fn Source::updated_row(self : Source, row : Int32, u : FeatureDiff) -> Int32 {
  let props = []
  if !u.remove_all_properties {
    for c in self.table.columns {
      if c.values[row] is Some(v) && !has(u.remove_properties, c.name) {
        props.push((c.name, Some(v)))
      }
    }
    for p in u.add_properties {
      props.push(p)
    }
  }
  self.table.push_row(self.table.ids[row], props)
}

///|
fn has(keys : Array[String], key : String) -> Bool {
  for k in keys {
    if k == key {
      return true
    }
  }
  false
}

///|
fn append(to : Array[FRef], from : Array[FRef]) -> Unit {
  for f in from {
    to.push(f)
  }
}

///|
/// geojson-vt's `hasPropertyChanges`.
fn has_property_changes(u : FeatureDiff) -> Bool {
  u.remove_all_properties ||
  u.remove_properties.length() > 0 ||
  u.add_properties.length() > 0
}

///|
/// Converts rows `from` to `to` of `table` into `out`, tracking the feature they
/// make up in `unlocated` under `key` (geojson-vt's `convertFeature`); every
/// feature gets the row `row_of` gives.
fn Source::convert_feature(
  self : Source,
  store : Store,
  out : Array[FRef],
  table : @geom.Table,
  from : Int32,
  to : Int32,
  key : @geom.Prop?,
  row_of : (Int32) -> Int32,
) -> Unit {
  let count = out.length()
  convert_into(
    store,
    out,
    table,
    from,
    to,
    self.sq_tolerance,
    self.trig,
    metrics=self.metrics,
    row_of~,
  )
  if kept_key(key) {
    self.unlocated[id_key(key)] = if out.length() > count {
      -1
    } else {
      row_of(from)
    }
  }
}

///|
/// geojson-vt's `convertNewGeometry`: the features of new geometry `rows` of
/// `diff`'s table, with row `row`'s properties and id `key`.
fn Source::new_geometry(
  self : Source,
  diff : Diff,
  rows : (Int32, Int32),
  key : @geom.Prop?,
  row : Int32,
) -> Array[FRef] {
  let out = []
  let fixed = (_ : Int32) => row
  self.convert_feature(
    Store::new(),
    out,
    diff.table,
    rows.0,
    rows.1,
    key,
    fixed,
  )
  self.wrapped(out)
}

///|
/// Dedups `keys` as a JavaScript `Map` built from them: each key at its first
/// place, with the index of its last.
fn last_by_key(keys : Array[String]) -> Array[(String, Int32)] {
  let at : Map[String, Int32] = Map([])
  let out = []
  for i, k in keys {
    match at.get(k) {
      Some(j) => out[j] = (k, i)
      None => {
        at[k] = out.length()
        out.push((k, i))
      }
    }
  }
  out
}

///|
/// The keys as a set (each mapped to 0).
fn key_set(keys : Array[(String, Int32)]) -> Map[String, Int32] {
  let set = Map([])
  for k in keys {
    set[k.0] = 0
  }
  set
}

///|
/// geojson-vt's `applySourceDiff`: applies `diff` to the features and returns
/// those it affected, old and new, to invalidate tiles by.
fn Source::apply(self : Source, diff : Diff) -> Array[FRef] {
  let keys = []
  for id in diff.remove {
    keys.push(id_key(id))
  }
  let removing = last_by_key(keys)
  keys.clear()
  for f in 0..<diff.add.length() {
    let row = @geom.start_of(diff.add, f)
    keys.push(id_key(key_of(diff.table, row, self.promote_id)))
  }
  let adding = last_by_key(keys)
  keys.clear()
  for u in diff.update {
    keys.push(id_key(u.id))
  }
  let update = last_by_key(keys)
  let mut source = self.features
  let affected = []
  if diff.remove_all {
    append(affected, source)
    source = []
    self.unlocated = Map([])
  }
  if removing.length() > 0 || adding.length() > 0 {
    let gone = key_set(removing)
    for k in removing {
      if self.unlocated.contains(k.0) {
        self.unlocated[k.0] = -1
      }
    }
    for a in adding {
      gone[a.0] = 0
    }
    let kept = []
    for f in source {
      if gone.contains(self.key(f)) {
        affected.push(f)
      } else {
        kept.push(f)
      }
    }
    source = kept
    if adding.length() > 0 {
      let store = Store::new()
      let added = []
      for a in adding {
        let f = a.1
        let from = @geom.start_of(diff.add, f)
        let to = diff.add[f]
        let base = self.table.length()
        for r in from..<to {
          let props = properties_of(diff.table, r)
          self.table.push_row(key_of(diff.table, r, self.promote_id), props)
          |> ignore
        }
        self.convert_feature(
          store,
          added,
          diff.table,
          from,
          to,
          self.table.ids[base],
          r => base + r - from,
        )
      }
      for f in self.wrapped(added) {
        affected.push(f)
        source.push(f)
      }
    }
  }
  if update.length() > 0 {
    // Each key updated: 0, or one more than its group of old features.
    let updating = key_set(update)
    let groups : Array[Array[FRef]] = []
    let kept = []
    for f in source {
      let k = self.key(f)
      match updating.get(k) {
        Some(0) => {
          updating[k] = groups.length() + 1
          groups.push([f])
        }
        Some(g) => groups[g - 1].push(f)
        None => kept.push(f)
      }
    }
    for entry in update {
      let (k, i) = entry
      let u = diff.update[i]
      let updated = match updating.get(k) {
        Some(g) if g > 0 => {
          let olds = groups[g - 1]
          append(affected, olds)
          self.updated_features(olds, u, diff)
        }
        _ =>
          match self.unlocated_row(k) {
            Some(row) => self.updated_unlocated(k, row, u, diff)
            None => continue
          }
      }
      append(affected, updated)
      append(kept, updated)
    }
    source = kept
  }
  self.features = source
  affected
}

///|
/// geojson-vt's `getUpdatedFeatures`: a new geometry converted with the first
/// feature's (updated) properties, or the features with updated properties. Those
/// take new rows in place: whatever else holds them is in tiles the update drops.
fn Source::updated_features(
  self : Source,
  olds : Array[FRef],
  u : FeatureDiff,
  diff : Diff,
) -> Array[FRef] {
  let change_props = has_property_changes(u)
  if u.geometry is Some(rows) {
    let row = olds[0].row()
    let props_row = if change_props { self.updated_row(row, u) } else { row }
    return self.new_geometry(diff, rows, self.table.ids[row], props_row)
  }
  if !change_props {
    return olds
  }
  // Each old row and its new one (a GeometryCollection's features share one).
  let rows = []
  for f in olds {
    let row = f.row()
    let mut new_row = -1
    for i in 0..<(rows.length() / 2) {
      if rows[i * 2] == row {
        new_row = rows[i * 2 + 1]
      }
    }
    if new_row < 0 {
      new_row = self.updated_row(row, u)
      rows.push(row)
      rows.push(new_row)
    }
    f.s.row[f.i] = new_row
  }
  olds
}

///|
/// geojson-vt's `getUpdatedUnlocatedFeatures`: none unless the new geometry has
/// coordinates; the property changes apply either way.
fn Source::updated_unlocated(
  self : Source,
  k : String,
  row : Int32,
  u : FeatureDiff,
  diff : Diff,
) -> Array[FRef] {
  let row = if has_property_changes(u) { self.updated_row(row, u) } else { row }
  match u.geometry {
    None => {
      self.unlocated[k] = row
      []
    }
    Some(rows) => self.new_geometry(diff, rows, self.table.ids[row], row)
  }
}

///|
/// Whether enough rows were added since the last compaction to look for dead ones.
fn Source::may_compact(self : Source) -> Bool {
  self.table.length() >= 2 * self.compacted + 1024
}

///|
/// Drops the rows no longer referenced when they outnumber the rest (`live` marks those referenced besides
/// the features' and unlocated ones); the rows kept lose their geometry. Renumbers the features' (`renumber`
/// does the rest); returns the old-to-new row map if it compacted.
fn Source::compact(self : Source, live : Array[Bool]) -> Array[Int32]? {
  let t = self.table
  let n = t.length()
  for f in self.features {
    live[f.row()] = true
  }
  for _, row in self.unlocated {
    if row >= 0 {
      live[row] = true
    }
  }
  let map = Array::make(n, -1)
  let mut count = 0
  for row in 0..<n {
    if live[row] {
      map[row] = count
      count += 1
    }
  }
  self.compacted = count
  if n - count <= count {
    return None
  }
  for row in 0..<n {
    let to = map[row]
    if to >= 0 {
      t.ids[to] = t.ids[row]
      for c in t.columns {
        c.values[to] = c.values[row]
      }
    }
  }
  t.kinds.truncate(count)
  t.part_ends.truncate(count)
  for row in 0..<count {
    t.kinds[row] = NoGeometry
    t.part_ends[row] = 0
  }
  t.ring_ends.clear()
  t.point_ends.clear()
  t.coords.clear()
  t.ids.truncate(count)
  for c in t.columns {
    c.values.truncate(count)
  }
  let renumbered = []
  for k, row in self.unlocated {
    if row >= 0 {
      renumbered.push((k, map[row]))
    }
  }
  for e in renumbered {
    self.unlocated[e.0] = e.1
  }
  self.epoch += 1
  self.renumber(self.features, map)
  Some(map)
}

///|
/// Renumbers the rows of the stores `set` reaches by `map`, each store once a compaction.
fn Source::renumber(
  self : Source,
  set : Array[FRef],
  map : Array[Int32],
) -> Unit {
  for f in set {
    let s = f.s
    if s.epoch == self.epoch {
      continue
    }
    s.epoch = self.epoch
    for i, row in s.row {
      s.row[i] = if row >= 0 { map[row] } else { -1 }
    }
  }
}
