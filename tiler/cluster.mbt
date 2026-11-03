// Ported from @maplibre/geojson-vt 6.3.0 (src/cluster-tile-index.ts): MIT
// License, Copyright (c) 2025 MapLibre contributors, and ISC License,
// Copyright (c) 2024, Mapbox. See NOTICE.

///|
/// geojson-vt's cluster options (`SuperclusterOptions`; no `map`/`reduce`):
/// zooms clustered on, the points a cluster needs, its `radius` in units of
/// a tile `extent` wide, and the kd-tree's `node_size`.
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
/// The highest zoom clustered on: a cluster id keeps its zoom in five bits.
const MAX_CLUSTER_ZOOM : Int32 = 30

///|
/// Steps per world of the integer coordinates the trees hold.
const SCALE : Double = 1073741824.0

///|
const MAX_INTEGER : Double = 2147483647.0

///|
/// The per-item values in a tree's `data`, `STRIDE` apart: the last zoom it
/// was processed at, its point index or cluster id, its parent cluster id
/// and its point count.
const OFFSET_ZOOM : Int32 = 0

///|
const OFFSET_ID : Int32 = 1

///|
const OFFSET_PARENT : Int32 = 2

///|
const OFFSET_NUM : Int32 = 3

///|
const STRIDE : Int32 = 4

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
/// A point (its table `row`, `count` 1) or a cluster (row -1, its id and point
/// count), at `x` and `y` in tile units in a tile, else longitude and latitude.
pub struct ClusterFeature {
  x : Double
  y : Double
  row : Int32
  cluster_id : Int32
  count : Int32
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
}

///|
/// Indexes the points of `table` (longitude and latitude) as geojson-vt with
/// `cluster: true`, copying across the antimeridian those within `wrap_buffer`
/// (its `buffer` / `extent`) of it; each position of a MultiPoint is a point.
pub fn ClusterIndex::new(
  table : @geom.Table,
  options~ : ClusterOptions = ClusterOptions::default(),
  wrap_buffer~ : Double = 64.0 / 4096.0,
  trig~ : Trig = Trig::moonbit(),
) -> ClusterIndex {
  let options = {
    ..options,
    min_zoom: clamp(options.min_zoom, 0, MAX_CLUSTER_ZOOM),
    max_zoom: clamp(options.max_zoom, -1, MAX_CLUSTER_ZOOM),
  }
  let index : ClusterIndex = {
    options,
    trees: [],
    xs: [],
    ys: [],
    rows: [],
    trig,
  }
  let mut set = convert(table, 0.0, trig)
  if options.wrap {
    set = wrap(set, wrap_buffer)
  }
  if set.is_empty() {
    return index
  }
  for fr in set {
    let s = fr.s
    if s.kind[fr.i] != 1 {
      continue
    }
    let r = start(s.ring_ends, start(s.part_ends, fr.i))
    for i in start(s.point_ends, r)..<s.point_ends[r] {
      let x = s.pts[i * 3]
      let y = s.pts[i * 3 + 1]
      if !options.wrap && !(x >= 0.0 && x <= 1.0 && y >= 0.0 && y <= 1.0) {
        continue
      }
      index.xs.push(x)
      index.ys.push(y)
      index.rows.push(s.row[fr.i])
    }
  }
  index.create_trees()
  index
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
      }
      data[i + OFFSET_PARENT] = id
      next_coords[next * 2] = js_round(wx / num_points.to_double())
      next_coords[next * 2 + 1] = js_round(wy / num_points.to_double())
      let k = next * STRIDE
      next_data[k + OFFSET_ZOOM] = not_processed
      next_data[k + OFFSET_ID] = id
      next_data[k + OFFSET_PARENT] = -1
      next_data[k + OFFSET_NUM] = num_points
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
/// The tree a zoom draws from (geojson-vt's `limitZoom`).
fn ClusterIndex::tree_at(self : ClusterIndex, z : Int32) -> ClusterTree? {
  let o = self.options
  let z = @cmp.maximum(o.min_zoom, @cmp.minimum(z, o.max_zoom + 1))
  if z >= 0 && z < self.trees.length() {
    self.trees[z]
  } else {
    None
  }
}

///|
/// Tile (z, x, y): the clusters and points within the cluster radius of it,
/// in tile units of `extent`; None past zoom 24 or where there are no trees
/// (geojson-vt's `getTile`).
pub fn ClusterIndex::tile(
  self : ClusterIndex,
  z : Int32,
  x : Int32,
  y : Int32,
) -> Array[ClusterFeature]? {
  if z < 0 || z > 24 {
    return None
  }
  guard self.tree_at(z) is Some(tree) else { return None }
  let o = self.options
  let z2 = pow2(z)
  let xd = x.to_double()
  let yd = y.to_double()
  if !o.wrap && (xd < 0.0 || xd >= z2 || yd < 0.0 || yd >= z2) {
    return None
  }
  let p = o.radius / o.extent.to_double()
  let top = encode_coord((yd - p) / z2)
  let bottom = encode_coord((yd + 1.0 + p) / z2)
  let out = []
  let left = encode_coord((xd - p) / z2)
  let right = encode_coord((xd + 1.0 + p) / z2)
  self.add_tile_features(
    out,
    tree.kd.range(left, top, right, bottom),
    tree,
    xd,
    yd,
    z2,
  )
  if o.wrap && xd == 0.0 {
    let ids = tree.kd.range(
      encode_coord(1.0 - p / z2),
      top,
      encode_coord(1.0),
      bottom,
    )
    self.add_tile_features(out, ids, tree, z2, yd, z2)
  }
  if o.wrap && xd == z2 - 1.0 {
    let ids = tree.kd.range(
      encode_coord(0.0),
      top,
      encode_coord(p / z2),
      bottom,
    )
    self.add_tile_features(out, ids, tree, -1.0, yd, z2)
  }
  Some(out)
}

///|
fn ClusterIndex::add_tile_features(
  self : ClusterIndex,
  out : Array[ClusterFeature],
  ids : Array[Int32],
  tree : ClusterTree,
  x : Double,
  y : Double,
  z2 : Double,
) -> Unit {
  let e = self.options.extent.to_double()
  for i in ids {
    let k = i * STRIDE
    let (px, py, row, cluster_id) = if tree.data[k + OFFSET_NUM] > 1 {
      (
        decode_coord(tree.coords[i * 2]),
        decode_coord(tree.coords[i * 2 + 1]),
        -1,
        tree.data[k + OFFSET_ID],
      )
    } else {
      let p = tree.data[k + OFFSET_ID]
      (self.xs[p], self.ys[p], self.rows[p], -1)
    }
    out.push({
      x: js_round(e * (px * z2 - x)).to_double(),
      y: js_round(e * (py * z2 - y)).to_double(),
      row,
      cluster_id,
      count: tree.data[k + OFFSET_NUM],
    })
  }
}

///|
/// The zoom at which cluster `id` breaks apart (geojson-vt's
/// `getClusterExpansionZoom`, which does not check the id either).
pub fn ClusterIndex::expansion_zoom(self : ClusterIndex, id : Int32) -> Int32 {
  ((id.to_int64() - self.xs.length().to_int64()) % 32L).to_int()
}

///|
/// The clusters and points that cluster `id` is made of, one zoom down; None
/// if there is no such cluster (geojson-vt's `getChildren`).
pub fn ClusterIndex::children(
  self : ClusterIndex,
  id : Int32,
) -> Array[ClusterFeature]? {
  let origin = (id - self.xs.length()) >> 5
  let zoom = self.expansion_zoom(id)
  guard zoom >= 0 &&
    zoom < self.trees.length() &&
    self.trees[zoom] is Some(tree) &&
    origin >= 0 &&
    origin < tree.num_items else {
    return None
  }
  let o = self.options
  let r = o.radius / (o.extent.to_double() * pow2(zoom - 1)) * SCALE
  let found = FixedArray::make(tree.num_items, 0)
  let n = tree.kd.within_into(
    tree.coords[origin * 2].to_double(),
    tree.coords[origin * 2 + 1].to_double(),
    r,
    found,
  )
  let children = []
  for j in 0..<n {
    let c = found[j]
    let k = c * STRIDE
    if tree.data[k + OFFSET_PARENT] != id {
      continue
    }
    if tree.data[k + OFFSET_NUM] > 1 {
      children.push(
        self.lng_lat(
          decode_coord(tree.coords[c * 2]),
          decode_coord(tree.coords[c * 2 + 1]),
          -1,
          tree.data[k + OFFSET_ID],
          tree.data[k + OFFSET_NUM],
        ),
      )
    } else {
      let p = tree.data[k + OFFSET_ID]
      children.push(self.lng_lat(self.xs[p], self.ys[p], self.rows[p], -1, 1))
    }
  }
  if children.is_empty() {
    None
  } else {
    Some(children)
  }
}

///|
/// A feature at world (x, y), unprojected to longitude and latitude.
fn ClusterIndex::lng_lat(
  self : ClusterIndex,
  x : Double,
  y : Double,
  row : Int32,
  cluster_id : Int32,
  count : Int32,
) -> ClusterFeature {
  let y2 = (180.0 - y * 360.0) * @math.PI / 180.0
  {
    x: (x - 0.5) * 360.0,
    y: 360.0 * self.trig.atan(self.trig.exp(y2)) / @math.PI - 90.0,
    row,
    cluster_id,
    count,
  }
}

///|
/// Up to `limit` of the points in cluster `id` after skipping `offset` of
/// them (geojson-vt's `getLeaves`: a `limit` of 0 means 10, a negative one
/// no limit); None if there is no such cluster.
pub fn ClusterIndex::leaves(
  self : ClusterIndex,
  id : Int32,
  limit~ : Int32 = 10,
  offset~ : Int32 = 0,
) -> Array[ClusterFeature]? {
  let limit = if limit == 0 { 10 } else { limit }
  let out = []
  self.append_leaves(out, id, limit, offset, 0).map(_ => out)
}

///|
/// geojson-vt's `appendLeaves`: the points skipped so far, or None if a
/// cluster on the way does not exist.
fn ClusterIndex::append_leaves(
  self : ClusterIndex,
  out : Array[ClusterFeature],
  id : Int32,
  limit : Int32,
  offset : Int32,
  skipped : Int32,
) -> Int32? {
  guard self.children(id) is Some(children) else { return None }
  let mut skipped = skipped
  for child in children {
    if child.row < 0 {
      if skipped + child.count <= offset {
        skipped += child.count
      } else {
        guard self.append_leaves(out, child.cluster_id, limit, offset, skipped)
          is Some(s) else {
          return None
        }
        skipped = s
      }
    } else if skipped < offset {
      skipped += 1
    } else {
      out.push(child)
    }
    if out.length() == limit {
      break
    }
  }
  Some(skipped)
}

///|
/// geojson-vt's `point_count_abbreviated`: the count below 1000, else
/// thousands to one decimal ("1.5k") and, from 10000, whole ("12k").
pub fn abbreviated_count(count : Int32) -> @geom.Prop {
  if count >= 10000 {
    Str("\{js_round(count.to_double() / 1000.0)}k")
  } else if count >= 1000 {
    let r = js_round(count.to_double() / 100.0)
    if r % 10 == 0 {
      Str("\{r / 10}k")
    } else {
      Str("\{r / 10}.\{r % 10}k")
    }
  } else {
    Num(count.to_double())
  }
}
