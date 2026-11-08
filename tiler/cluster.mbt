// Ported from @maplibre/geojson-vt 6.3.0 (src/cluster-tile-index.ts): MIT
// License, Copyright (c) 2025 MapLibre contributors, and ISC License,
// Copyright (c) 2024, Mapbox. See NOTICE.

///|
/// geojson-vt's cluster options (`SuperclusterOptions`, `map` and `reduce` aside): zooms
/// clustered on, the points a cluster needs, its `radius` in units of a tile `extent`
/// wide, and the kd-tree's `node_size`.
pub(all) struct ClusterOptions {
  min_zoom : Int32
  max_zoom : Int32
  min_points : Int32
  radius : Double
  extent : Int32
  node_size : Int32
  wrap : Bool
}

///|
pub fn ClusterOptions::default() -> ClusterOptions {
  {
    min_zoom: 0,
    max_zoom: 16,
    min_points: 2,
    radius: 40.0,
    extent: 512,
    node_size: 64,
    wrap: true,
  }
}

///|
/// geojson-vt's `map` and `reduce` as MapLibre makes them from `clusterProperties`:
/// `map` gives a point's (its table row's) value of each of `keys`, `reduce` merges a
/// point's or cluster's values (the second) into a cluster's (the first, in place).
pub(all) struct ClusterProperties {
  keys : Array[String]
  map : (Int32) -> Array[@geom.Prop]
  reduce : (Array[@geom.Prop], Array[@geom.Prop]) -> Unit
}

///|
/// The highest zoom clustered on: a cluster id keeps its zoom in five bits.
const MAX_CLUSTER_ZOOM : Int32 = 30

///|
/// Steps per world of the integer coordinates the trees hold.
const SCALE : Double = 1073741824.0

///|
const MAX_INTEGER : Double = 2147483647.0

///|
/// The per-item values in a tree's `data`, `STRIDE` apart: the last zoom it
/// was processed at, its point index or cluster id, its parent cluster id,
/// its point count and a cluster's properties (an index, -1 for none).
const OFFSET_ZOOM : Int32 = 0

///|
const OFFSET_ID : Int32 = 1

///|
const OFFSET_PARENT : Int32 = 2

///|
const OFFSET_NUM : Int32 = 3

///|
const OFFSET_PROP : Int32 = 4

///|
const STRIDE : Int32 = 5

///|
fn encode_coord(c : Double) -> Double {
  (c - 0.5) * SCALE
}

///|
fn decode_coord(v : Int32) -> Double {
  v.to_double() / SCALE + 0.5
}

///|
/// Whether a world coordinate fits the trees' integers (NaN does not).
fn fits_integer(c : Double) -> Bool {
  encode_coord(c).abs() < MAX_INTEGER
}

///|
fn clamp(v : Int32, lo : Int32, hi : Int32) -> Int32 {
  @cmp.maximum(lo, @cmp.minimum(v, hi))
}

///|
/// 2 to the power `z`, exactly.
fn pow2(z : Int32) -> Double {
  if z >= 0 {
    (1L << z).to_double()
  } else {
    1.0 / (1L << -z).to_double()
  }
}

///|
/// The points and clusters of one zoom: the tree over them, their
/// coordinates in insertion order and their `STRIDE` values.
priv struct ClusterTree {
  kd : KDBush
  coords : FixedArray[Int32]
  data : FixedArray[Int32]
  num_items : Int32
}

///|
/// A point (its table `row`, `count` 1) or a cluster (row -1, its id, point
/// count and `properties`' values), at `x` and `y` in tile units in a tile, else
/// longitude and latitude.
pub struct ClusterFeature {
  x : Double
  y : Double
  row : Int32
  cluster_id : Int32
  count : Int32
  props : Array[(String, @geom.Prop)]
}

///|
/// Groups the point features of a table into clusters at each zoom and cuts
/// tiles of them (geojson-vt's `ClusterTileIndex`).
pub struct ClusterIndex {
  priv options : ClusterOptions
  priv trees : Array[ClusterTree?]
  priv xs : Array[Double]
  priv ys : Array[Double]
  priv rows : Array[Int32]
  priv trig : Trig
  priv properties : ClusterProperties?
  priv props : Array[Array[@geom.Prop]]
  priv mut found : FixedArray[Int32]
  priv source : Source
}

///|
/// The `TilerOptions::default()` buffer as a share of its extent.
let default_wrap_buffer : Double = {
  let o = TilerOptions::default()
  o.buffer.to_double() / o.extent.to_double()
}

///|
/// Indexes the points of `table` (longitude and latitude; `feature_ends`, `promote_id` as for
/// `Tiler::new`) as geojson-vt with `cluster: true`, copying those within `wrap_buffer` (its
/// `buffer` / `extent`) across the antimeridian; each position of a MultiPoint is a point.
pub fn ClusterIndex::new(
  table : @geom.Table,
  options~ : ClusterOptions = ClusterOptions::default(),
  wrap_buffer~ : Double = default_wrap_buffer,
  trig~ : Trig = Trig::moonbit(),
  properties? : ClusterProperties,
  feature_ends? : Array[Int32],
  promote_id? : String,
) -> ClusterIndex {
  let options = {
    ..options,
    min_zoom: clamp(options.min_zoom, 0, MAX_CLUSTER_ZOOM),
    max_zoom: clamp(options.max_zoom, -1, MAX_CLUSTER_ZOOM),
  }
  let wrap = if options.wrap { Some(wrap_buffer) } else { None }
  let source = Source::new(
    table, feature_ends, promote_id, 0.0, false, wrap, trig,
  )
  let index : ClusterIndex = {
    options,
    trees: [],
    xs: [],
    ys: [],
    rows: [],
    trig,
    properties,
    props: [],
    found: FixedArray::make(0, 0),
    source,
  }
  if !source.features.is_empty() {
    index.initialize()
  }
  index
}

///|
/// geojson-vt's `updateData` and `ClusterTileIndex.updateIndex`: applies `diff`
/// and builds the trees again from the points. Returns whether anything changed.
pub fn ClusterIndex::update(self : ClusterIndex, diff : Diff) -> Bool {
  if self.source.apply(diff).is_empty() {
    return false
  }
  let src = self.source
  if src.may_compact() {
    src.compact(Array::make(src.table.length(), false)) |> ignore
  }
  self.trees.clear()
  self.xs.clear()
  self.ys.clear()
  self.rows.clear()
  self.props.clear()
  self.initialize()
  true
}

///|
/// geojson-vt's `initialize`: the trees over the points of the source's features.
fn ClusterIndex::initialize(self : ClusterIndex) -> Unit {
  for fr in self.source.features {
    let s = fr.s
    if s.kind[fr.i] != @core.GEOM_POINTS {
      continue
    }
    let r = @geom.start_of(s.ring_ends, @geom.start_of(s.part_ends, fr.i))
    for i in @geom.start_of(s.point_ends, r)..<s.point_ends[r] {
      let x = s.pts[i * 3]
      let y = s.pts[i * 3 + 1]
      if !self.options.wrap && !(x >= 0.0 && x <= 1.0 && y >= 0.0 && y <= 1.0) {
        continue
      }
      self.xs.push(x)
      self.ys.push(y)
      self.rows.push(s.row[fr.i])
    }
  }
  self.create_trees()
}

///|
/// geojson-vt's `createIndex`: a tree per zoom, from the points up.
fn ClusterIndex::create_trees(self : ClusterIndex) -> Unit {
  let o = self.options
  let n = self.xs.length()
  let not_processed = o.max_zoom + 1
  let coords = FixedArray::make(n * 2, 0)
  let data = FixedArray::make(n * STRIDE, 0)
  let mut num_items = 0
  for i in 0..<n {
    if !fits_integer(self.xs[i]) || !fits_integer(self.ys[i]) {
      continue
    }
    coords[num_items * 2] = js_round(encode_coord(self.xs[i]))
    coords[num_items * 2 + 1] = js_round(encode_coord(self.ys[i]))
    let k = num_items * STRIDE
    data[k + OFFSET_ZOOM] = not_processed
    data[k + OFFSET_ID] = i
    data[k + OFFSET_PARENT] = -1
    data[k + OFFSET_NUM] = 1
    data[k + OFFSET_PROP] = -1
    num_items += 1
  }
  for _ in 0..<(o.max_zoom + 2) {
    self.trees.push(None)
  }
  let mut tree = self.create_tree(coords, data, num_items)
  self.trees[o.max_zoom + 1] = Some(tree)
  let next_coords = FixedArray::make(num_items * 2, 0)
  let next_data = FixedArray::make(num_items * STRIDE, 0)
  for z = o.max_zoom; z >= o.min_zoom; z = z - 1 {
    let next = self.cluster(tree, z, next_coords, next_data)
    if !same_items(tree, next_data, next) {
      let c = FixedArray::make(next * 2, 0)
      FixedArray::unsafe_blit(c, 0, next_coords, 0, next * 2)
      let d = FixedArray::make(next * STRIDE, 0)
      FixedArray::unsafe_blit(d, 0, next_data, 0, next * STRIDE)
      tree = self.create_tree(c, d, next)
    }
    self.trees[z] = Some(tree)
  }
}

///|
fn ClusterIndex::create_tree(
  self : ClusterIndex,
  coords : FixedArray[Int32],
  data : FixedArray[Int32],
  num_items : Int32,
) -> ClusterTree {
  {
    kd: KDBush::new(coords, num_items, self.options.node_size, self.trig),
    coords,
    data,
    num_items,
  }
}

///|
/// Whether clustering left a tree's items as they were, in the same order
/// (geojson-vt's `isSameAsTree`).
fn same_items(
  tree : ClusterTree,
  next_data : FixedArray[Int32],
  next : Int32,
) -> Bool {
  if next != tree.num_items {
    return false
  }
  let mut k = OFFSET_ID
  while k < next * STRIDE {
    if next_data[k] != tree.data[k] {
      return false
    }
    k += STRIDE
  }
  true
}

///|
/// Clusters the items of `tree` at `zoom` into `next_coords` and
/// `next_data`; returns how many it wrote (geojson-vt's `cluster`).
fn ClusterIndex::cluster(
  self : ClusterIndex,
  tree : ClusterTree,
  zoom : Int32,
  next_coords : FixedArray[Int32],
  next_data : FixedArray[Int32],
) -> Int32 {
  let o = self.options
  let r = o.radius / (o.extent.to_double() * pow2(zoom)) * SCALE
  let not_processed = o.max_zoom + 1
  let coords = tree.coords
  let data = tree.data
  let neighbors = FixedArray::make(tree.num_items, 0)
  let mut next = 0
  for index in 0..<tree.num_items {
    let i = index * STRIDE
    if data[i + OFFSET_ZOOM] <= zoom {
      continue
    }
    data[i + OFFSET_ZOOM] = zoom
    let x = coords[index * 2]
    let y = coords[index * 2 + 1]
    let found = tree.kd.within_into(x.to_double(), y.to_double(), r, neighbors)
    let origin = data[i + OFFSET_NUM]
    let mut num_points = origin
    for n in 0..<found {
      let k = neighbors[n] * STRIDE
      if data[k + OFFSET_ZOOM] > zoom {
        num_points += data[k + OFFSET_NUM]
      }
    }
    if num_points > origin && num_points >= o.min_points {
      let mut wx = x.to_double() * origin.to_double()
      let mut wy = y.to_double() * origin.to_double()
      let id = (index << 5) + (zoom + 1) + self.xs.length()
      let mut merged : Array[@geom.Prop]? = None
      let mut prop_index = -1
      for n in 0..<found {
        let j = neighbors[n]
        let k = j * STRIDE
        if data[k + OFFSET_ZOOM] <= zoom {
          continue
        }
        data[k + OFFSET_ZOOM] = zoom
        let count = data[k + OFFSET_NUM].to_double()
        wx += coords[j * 2].to_double() * count
        wy += coords[j * 2 + 1].to_double() * count
        data[k + OFFSET_PARENT] = id
        if self.properties is Some(p) {
          let acc = match merged {
            Some(a) => a
            None => {
              let a = self.values(data, i).copy()
              prop_index = self.props.length()
              self.props.push(a)
              merged = Some(a)
              a
            }
          }
          (p.reduce)(acc, self.values(data, k))
        }
      }
      data[i + OFFSET_PARENT] = id
      next_coords[next * 2] = js_round(wx / num_points.to_double())
      next_coords[next * 2 + 1] = js_round(wy / num_points.to_double())
      let k = next * STRIDE
      next_data[k + OFFSET_ZOOM] = not_processed
      next_data[k + OFFSET_ID] = id
      next_data[k + OFFSET_PARENT] = -1
      next_data[k + OFFSET_NUM] = num_points
      next_data[k + OFFSET_PROP] = prop_index
      next += 1
    } else {
      next_coords[next * 2] = x
      next_coords[next * 2 + 1] = y
      FixedArray::unsafe_blit(next_data, next * STRIDE, data, i, STRIDE)
      next += 1
      if num_points > 1 {
        for n in 0..<found {
          let j = neighbors[n]
          let k = j * STRIDE
          if data[k + OFFSET_ZOOM] <= zoom {
            continue
          }
          data[k + OFFSET_ZOOM] = zoom
          next_coords[next * 2] = coords[j * 2]
          next_coords[next * 2 + 1] = coords[j * 2 + 1]
          FixedArray::unsafe_blit(next_data, next * STRIDE, data, k, STRIDE)
          next += 1
        }
      }
    }
  }
  next
}

///|
/// The values of an item for `reduce`: a cluster's own, a point's mapped (its
/// `map`; geojson-vt's private `map`).
fn ClusterIndex::values(
  self : ClusterIndex,
  data : FixedArray[Int32],
  i : Int32,
) -> Array[@geom.Prop] {
  if data[i + OFFSET_NUM] > 1 {
    return self.props[data[i + OFFSET_PROP]]
  }
  match self.properties {
    Some(p) => (p.map)(self.rows[data[i + OFFSET_ID]])
    None => []
  }
}

///|
/// A cluster's properties by key (none without `ClusterProperties`).
fn ClusterIndex::props_of(
  self : ClusterIndex,
  data : FixedArray[Int32],
  i : Int32,
) -> Array[(String, @geom.Prop)] {
  guard self.properties is Some(p) &&
    data[i + OFFSET_NUM] > 1 &&
    data[i + OFFSET_PROP] >= 0 else {
    return []
  }
  let values = self.props[data[i + OFFSET_PROP]]
  p.keys.mapi((k, key) => (key, values[k]))
}
