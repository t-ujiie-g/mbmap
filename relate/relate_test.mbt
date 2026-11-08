///|
type Geom = (@geom.GeomKind, Array[Array[Array[(Double, Double)]]])

///|
/// A one-row table of `g`: parts of rings of x, y pairs.
fn row(g : Geom) -> @geom.Table {
  let b = @geom.TableBuilder::new()
  for part in g.1 {
    for ring in part {
      for p in ring {
        b.point(p.0, p.1)
      }
      b.end_ring()
    }
    b.end_part()
  }
  b.end_feature(g.0)
  b.finish()
}

///|
let predicate_names : Array[String] = [
  "intersects", "disjoint", "contains", "within", "covers", "coveredBy", "touches",
  "crosses", "overlaps", "equals",
]

///|
/// Checks `relate_checked` against JSTS 2.12.1's `relate(a, b).toString()`
/// ("throws" where JSTS throws) and `predicate` against its Geometry methods,
/// `preds` in `predicate_names` order (x where JSTS throws).
fn check_case(
  name : String,
  ga : Geom,
  gb : Geom,
  im : String,
  preds : String,
) -> Unit raise {
  let a = row(ga)
  let b = row(gb)
  match @relate.relate_checked(a, 0, b, 0) {
    Some(m) => {
      assert_eq((name, m.to_string()), (name, im))
      assert_eq((name, @relate.relate(a, 0, b, 0).to_string()), (name, im))
    }
    None => assert_eq((name, "throws"), (name, im))
  }
  for k, p in predicate_names {
    let want = preds[k]
    if want != 'x' {
      assert_eq(
        (name, p, @relate.predicate(a, 0, b, 0, p)),
        (name, p, want == '1'),
      )
    }
  }
}

///|
/// Hand-written cases: name, a, b, JSTS's matrix, JSTS's predicates.
let cases : Array[(String, Geom, Geom, String, String)] = [
  (
    "point/point equal",
    (Point, [[[(1.0, 1.0)]]]),
    (Point, [[[(1.0, 1.0)]]]),
    "0FFFFFFF2",
    "1011110001",
  ),
  (
    "point/point apart",
    (Point, [[[(1.0, 1.0)]]]),
    (Point, [[[(2.0, 1.0)]]]),
    "FF0FFF0F2",
    "0100000000",
  ),
  (
    "point/line interior",
    (Point, [[[(1.0, 1.0)]]]),
    (LineString, [[[(0.0, 0.0), (2.0, 2.0)]]]),
    "0FFFFF102",
    "1001010000",
  ),
  (
    "point/line vertex",
    (Point, [[[(1.0, 1.0)]]]),
    (LineString, [[[(0.0, 0.0), (1.0, 1.0), (2.0, 0.0)]]]),
    "0FFFFF102",
    "1001010000",
  ),
  (
    "point/line endpoint",
    (Point, [[[(0.0, 0.0)]]]),
    (LineString, [[[(0.0, 0.0), (2.0, 2.0)]]]),
    "F0FFFF102",
    "1000011000",
  ),
  (
    "point/line off",
    (Point, [[[(1.0, 0.0)]]]),
    (LineString, [[[(0.0, 0.0), (2.0, 2.0)]]]),
    "FF0FFF102",
    "0100000000",
  ),
  (
    "point/closed line",
    (Point, [[[(0.0, 0.0)]]]),
    (LineString, [[[(0.0, 0.0), (2.0, 0.0), (2.0, 2.0), (0.0, 0.0)]]]),
    "0FFFFF1F2",
    "1001010000",
  ),
  (
    "point/polygon inside",
    (Point, [[[(1.0, 1.0)]]]),
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)]]]),
    "0FFFFF212",
    "1001010000",
  ),
  (
    "point/polygon edge",
    (Point, [[[(2.0, 0.0)]]]),
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)]]]),
    "F0FFFF212",
    "1000011000",
  ),
  (
    "point/polygon vertex",
    (Point, [[[(4.0, 4.0)]]]),
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)]]]),
    "F0FFFF212",
    "1000011000",
  ),
  (
    "point/polygon hole",
    (Point, [[[(2.0, 2.0)]]]),
    (
      Polygon,
      [
        [
          [(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)],
          [(1.0, 1.0), (3.0, 1.0), (3.0, 3.0), (1.0, 3.0), (1.0, 1.0)],
        ],
      ],
    ),
    "FF0FFF212",
    "0100000000",
  ),
  (
    "point/polygon hole edge",
    (Point, [[[(1.0, 2.0)]]]),
    (
      Polygon,
      [
        [
          [(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)],
          [(1.0, 1.0), (3.0, 1.0), (3.0, 3.0), (1.0, 3.0), (1.0, 1.0)],
        ],
      ],
    ),
    "F0FFFF212",
    "1000011000",
  ),
  (
    "point/polygon outside",
    (Point, [[[(5.0, 5.0)]]]),
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)]]]),
    "FF0FFF212",
    "0100000000",
  ),
  (
    "point/polygon outside in envelope",
    (Point, [[[(3.0, 0.5)]]]),
    (Polygon, [[[(0.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)]]]),
    "FF0FFF212",
    "0100000000",
  ),
  (
    "polygon/point",
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)]]]),
    (Point, [[[(1.0, 1.0)]]]),
    "0F2FF1FF2",
    "1010100000",
  ),
  (
    "triangle/point",
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (0.0, 4.0), (0.0, 0.0)]]]),
    (Point, [[[(1.0, 1.0)]]]),
    "0F2FF1FF2",
    "1010100000",
  ),
  (
    "line/line cross",
    (LineString, [[[(0.0, 0.0), (2.0, 2.0)]]]),
    (LineString, [[[(0.0, 2.0), (2.0, 0.0)]]]),
    "0F1FF0102",
    "1000000100",
  ),
  (
    "line/line touch at end",
    (LineString, [[[(0.0, 0.0), (1.0, 1.0)]]]),
    (LineString, [[[(1.0, 1.0), (2.0, 0.0)]]]),
    "FF1F00102",
    "1000001000",
  ),
  (
    "line/line end on interior",
    (LineString, [[[(0.0, 0.0), (2.0, 2.0)]]]),
    (LineString, [[[(1.0, 1.0), (2.0, 0.0)]]]),
    "F01FF0102",
    "1000001000",
  ),
  (
    "line/line collinear overlap",
    (LineString, [[[(0.0, 0.0), (2.0, 0.0)]]]),
    (LineString, [[[(1.0, 0.0), (3.0, 0.0)]]]),
    "1010F0102",
    "1000000010",
  ),
  (
    "line/line identical",
    (LineString, [[[(0.0, 0.0), (1.0, 1.0), (2.0, 0.0)]]]),
    (LineString, [[[(0.0, 0.0), (1.0, 1.0), (2.0, 0.0)]]]),
    "1FFF0FFF2",
    "1011110001",
  ),
  (
    "line/line reversed",
    (LineString, [[[(0.0, 0.0), (1.0, 1.0), (2.0, 0.0)]]]),
    (LineString, [[[(2.0, 0.0), (1.0, 1.0), (0.0, 0.0)]]]),
    "1FFF0FFF2",
    "1011110001",
  ),
  (
    "line/line contained",
    (LineString, [[[(0.0, 0.0), (4.0, 0.0)]]]),
    (LineString, [[[(1.0, 0.0), (2.0, 0.0)]]]),
    "101FF0FF2",
    "1010100000",
  ),
  (
    "line/line disjoint",
    (LineString, [[[(0.0, 0.0), (1.0, 0.0)]]]),
    (LineString, [[[(0.0, 1.0), (1.0, 1.0)]]]),
    "FF1FF0102",
    "0100000000",
  ),
  (
    "line/line disjoint envelopes overlap",
    (LineString, [[[(0.0, 0.0), (2.0, 2.0)]]]),
    (LineString, [[[(2.0, 0.0), (1.5, 0.5)]]]),
    "FF1FF0102",
    "0100000000",
  ),
  (
    "closed line/line",
    (
      LineString,
      [[[(0.0, 0.0), (2.0, 0.0), (2.0, 2.0), (0.0, 2.0), (0.0, 0.0)]]],
    ),
    (LineString, [[[(0.0, 0.0), (1.0, -1.0)]]]),
    "F01FFF102",
    "1000001000",
  ),
  (
    "closed line/closed line",
    (
      LineString,
      [[[(0.0, 0.0), (2.0, 0.0), (2.0, 2.0), (0.0, 2.0), (0.0, 0.0)]]],
    ),
    (
      LineString,
      [[[(1.0, 1.0), (3.0, 1.0), (3.0, 3.0), (1.0, 3.0), (1.0, 1.0)]]],
    ),
    "0F1FFF1F2",
    "1000000100",
  ),
  (
    "line/polygon inside",
    (LineString, [[[(1.0, 1.0), (2.0, 2.0)]]]),
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)]]]),
    "1FF0FF212",
    "1001010000",
  ),
  (
    "line/polygon crossing",
    (LineString, [[[(1.0, 1.0), (5.0, 5.0)]]]),
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)]]]),
    "1010F0212",
    "1000000100",
  ),
  (
    "line/polygon along edge",
    (LineString, [[[(0.0, 0.0), (4.0, 0.0)]]]),
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)]]]),
    "F1FF0F212",
    "1000011000",
  ),
  (
    "line/polygon part of edge",
    (LineString, [[[(1.0, 0.0), (2.0, 0.0)]]]),
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)]]]),
    "F1FF0F212",
    "1000011000",
  ),
  (
    "line/polygon touching vertex",
    (LineString, [[[(4.0, 4.0), (5.0, 6.0)]]]),
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)]]]),
    "FF1F00212",
    "1000001000",
  ),
  (
    "line/polygon through",
    (LineString, [[[(-1.0, 2.0), (5.0, 2.0)]]]),
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)]]]),
    "101FF0212",
    "1000000100",
  ),
  (
    "line/polygon in hole",
    (LineString, [[[(1.5, 1.5), (2.5, 2.5)]]]),
    (
      Polygon,
      [
        [
          [(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)],
          [(1.0, 1.0), (3.0, 1.0), (3.0, 3.0), (1.0, 3.0), (1.0, 1.0)],
        ],
      ],
    ),
    "FF1FF0212",
    "0100000000",
  ),
  (
    "polygon/line crossing",
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)]]]),
    (LineString, [[[(1.0, 1.0), (5.0, 5.0)]]]),
    "1020F1102",
    "1000000100",
  ),
  (
    "triangle/line inside",
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (0.0, 4.0), (0.0, 0.0)]]]),
    (LineString, [[[(1.0, 1.0), (0.5, 0.5)]]]),
    "102FF1FF2",
    "1010100000",
  ),
  (
    "polygon/polygon disjoint",
    (Polygon, [[[(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0), (0.0, 0.0)]]]),
    (Polygon, [[[(2.0, 2.0), (3.0, 2.0), (3.0, 3.0), (2.0, 3.0), (2.0, 2.0)]]]),
    "FF2FF1212",
    "0100000000",
  ),
  (
    "polygon/polygon touching edge",
    (Polygon, [[[(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0), (0.0, 0.0)]]]),
    (Polygon, [[[(1.0, 0.0), (2.0, 0.0), (2.0, 1.0), (1.0, 1.0), (1.0, 0.0)]]]),
    "FF2F11212",
    "1000001000",
  ),
  (
    "polygon/polygon touching corner",
    (Polygon, [[[(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0), (0.0, 0.0)]]]),
    (Polygon, [[[(1.0, 1.0), (2.0, 1.0), (2.0, 2.0), (1.0, 2.0), (1.0, 1.0)]]]),
    "FF2F01212",
    "1000001000",
  ),
  (
    "polygon/polygon overlapping",
    (Polygon, [[[(0.0, 0.0), (2.0, 0.0), (2.0, 2.0), (0.0, 2.0), (0.0, 0.0)]]]),
    (Polygon, [[[(1.0, 1.0), (3.0, 1.0), (3.0, 3.0), (1.0, 3.0), (1.0, 1.0)]]]),
    "212101212",
    "1000000010",
  ),
  (
    "polygon/polygon containing",
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)]]]),
    (Polygon, [[[(1.0, 1.0), (2.0, 1.0), (2.0, 2.0), (1.0, 2.0), (1.0, 1.0)]]]),
    "212FF1FF2",
    "1010100000",
  ),
  (
    "polygon/polygon contained touching",
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)]]]),
    (Polygon, [[[(0.0, 0.0), (2.0, 0.0), (2.0, 2.0), (0.0, 2.0), (0.0, 0.0)]]]),
    "212F11FF2",
    "1010100000",
  ),
  (
    "polygon/polygon equal",
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)]]]),
    (Polygon, [[[(0.0, 0.0), (0.0, 4.0), (4.0, 4.0), (4.0, 0.0), (0.0, 0.0)]]]),
    "2FFF1FFF2",
    "1011110001",
  ),
  (
    "polygon/polygon equal other start",
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)]]]),
    (Polygon, [[[(4.0, 4.0), (0.0, 4.0), (0.0, 0.0), (4.0, 0.0), (4.0, 4.0)]]]),
    "2FFF1FFF2",
    "1011110001",
  ),
  (
    "triangles equal",
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (0.0, 4.0), (0.0, 0.0)]]]),
    (Polygon, [[[(4.0, 0.0), (0.0, 4.0), (0.0, 0.0), (4.0, 0.0)]]]),
    "2FFF1FFF2",
    "1011110001",
  ),
  (
    "polygon in hole",
    (
      Polygon,
      [
        [
          [(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)],
          [(1.0, 1.0), (3.0, 1.0), (3.0, 3.0), (1.0, 3.0), (1.0, 1.0)],
        ],
      ],
    ),
    (Polygon, [[[(1.5, 1.5), (2.5, 1.5), (2.5, 2.5), (1.5, 2.5), (1.5, 1.5)]]]),
    "FF2FF1212",
    "0100000000",
  ),
  (
    "polygon filling hole",
    (
      Polygon,
      [
        [
          [(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)],
          [(1.0, 1.0), (3.0, 1.0), (3.0, 3.0), (1.0, 3.0), (1.0, 1.0)],
        ],
      ],
    ),
    (Polygon, [[[(1.0, 1.0), (3.0, 1.0), (3.0, 3.0), (1.0, 3.0), (1.0, 1.0)]]]),
    "FF2F112F2",
    "1000001000",
  ),
  (
    "polygon over hole",
    (
      Polygon,
      [
        [
          [(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)],
          [(1.0, 1.0), (3.0, 1.0), (3.0, 3.0), (1.0, 3.0), (1.0, 1.0)],
        ],
      ],
    ),
    (Polygon, [[[(0.5, 0.5), (3.5, 0.5), (3.5, 3.5), (0.5, 3.5), (0.5, 0.5)]]]),
    "2121F12F2",
    "1000000010",
  ),
  (
    "triangle/triangle overlapping",
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (2.0, 3.0), (0.0, 0.0)]]]),
    (Polygon, [[[(0.0, 2.0), (4.0, 2.0), (2.0, -1.0), (0.0, 2.0)]]]),
    "212101212",
    "1000000010",
  ),
  (
    "triangle/rectangle",
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (2.0, 3.0), (0.0, 0.0)]]]),
    (Polygon, [[[(1.0, 0.0), (3.0, 0.0), (3.0, 1.0), (1.0, 1.0), (1.0, 0.0)]]]),
    "212F11FF2",
    "1010100000",
  ),
  (
    "rectangle/triangle",
    (Polygon, [[[(1.0, 0.0), (3.0, 0.0), (3.0, 1.0), (1.0, 1.0), (1.0, 0.0)]]]),
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (2.0, 3.0), (0.0, 0.0)]]]),
    "2FF11F212",
    "1001010000",
  ),
  (
    "multipolygon/polygon",
    (
      MultiPolygon,
      [
        [[(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0), (0.0, 0.0)]],
        [[(2.0, 0.0), (3.0, 0.0), (3.0, 1.0), (2.0, 1.0), (2.0, 0.0)]],
      ],
    ),
    (Polygon, [[[(0.5, 0.5), (2.5, 0.5), (2.5, 2.0), (0.5, 2.0), (0.5, 0.5)]]]),
    "212101212",
    "1000000010",
  ),
  (
    "multipolygon touching parts/polygon",
    (
      MultiPolygon,
      [
        [[(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0), (0.0, 0.0)]],
        [[(1.0, 1.0), (2.0, 1.0), (2.0, 2.0), (1.0, 2.0), (1.0, 1.0)]],
      ],
    ),
    (Polygon, [[[(0.0, 0.0), (2.0, 0.0), (2.0, 2.0), (0.0, 2.0), (0.0, 0.0)]]]),
    "2FF11F212",
    "1001010000",
  ),
  (
    "multipolygon/multipolygon",
    (
      MultiPolygon,
      [
        [[(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0), (0.0, 0.0)]],
        [[(2.0, 0.0), (3.0, 0.0), (3.0, 1.0), (2.0, 1.0), (2.0, 0.0)]],
      ],
    ),
    (
      MultiPolygon,
      [
        [[(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0), (0.0, 0.0)]],
        [[(5.0, 5.0), (6.0, 5.0), (6.0, 6.0), (5.0, 5.0)]],
      ],
    ),
    "2F2F11212",
    "1000000010",
  ),
  (
    "multipolygon equal",
    (
      MultiPolygon,
      [
        [[(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0), (0.0, 0.0)]],
        [[(2.0, 0.0), (3.0, 0.0), (3.0, 1.0), (2.0, 1.0), (2.0, 0.0)]],
      ],
    ),
    (
      MultiPolygon,
      [
        [[(2.0, 0.0), (3.0, 0.0), (3.0, 1.0), (2.0, 1.0), (2.0, 0.0)]],
        [[(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0), (0.0, 0.0)]],
      ],
    ),
    "2FFF1FFF2",
    "1011110001",
  ),
  (
    "multipoint/polygon",
    (MultiPoint, [[[(1.0, 1.0), (5.0, 5.0)]]]),
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)]]]),
    "0F0FFF212",
    "1000000100",
  ),
  (
    "multipoint/polygon all inside",
    (MultiPoint, [[[(1.0, 1.0), (2.0, 2.0), (4.0, 0.0)]]]),
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)]]]),
    "00FFFF212",
    "1001010000",
  ),
  (
    "multipoint/line",
    (MultiPoint, [[[(0.0, 0.0), (1.0, 1.0)]]]),
    (LineString, [[[(0.0, 0.0), (2.0, 2.0)]]]),
    "00FFFF102",
    "1001010000",
  ),
  (
    "multipoint/multipoint",
    (MultiPoint, [[[(0.0, 0.0), (1.0, 1.0)]]]),
    (MultiPoint, [[[(1.0, 1.0), (2.0, 2.0)]]]),
    "0F0FFF0F2",
    "1000000010",
  ),
  (
    "multiline/polygon",
    (MultiLineString, [[[(0.0, 0.0), (1.0, 1.0)]], [[(5.0, 5.0), (6.0, 6.0)]]]),
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)]]]),
    "1F1000212",
    "1000000100",
  ),
  (
    "multiline shared end/point",
    (MultiLineString, [[[(0.0, 0.0), (1.0, 1.0)]], [[(1.0, 1.0), (2.0, 0.0)]]]),
    (Point, [[[(1.0, 1.0)]]]),
    "0F1FF0FF2",
    "1010100000",
  ),
  (
    "multiline three ends/point",
    (
      MultiLineString,
      [
        [[(0.0, 0.0), (1.0, 1.0)]],
        [[(1.0, 1.0), (2.0, 0.0)]],
        [[(1.0, 1.0), (1.0, 2.0)]],
      ],
    ),
    (Point, [[[(1.0, 1.0)]]]),
    "FF10F0FF2",
    "1000101000",
  ),
  (
    "multiline/line",
    (MultiLineString, [[[(0.0, 0.0), (1.0, 1.0)]], [[(1.0, 1.0), (2.0, 0.0)]]]),
    (LineString, [[[(0.0, 0.0), (1.0, 1.0), (2.0, 0.0)]]]),
    "1FFF0FFF2",
    "1011110001",
  ),
  (
    "empty/point",
    (NoGeometry, []),
    (Point, [[[(1.0, 1.0)]]]),
    "FFFFFF0F2",
    "0100000000",
  ),
  (
    "point/empty",
    (Point, [[[(1.0, 1.0)]]]),
    (NoGeometry, []),
    "FF0FFFFF2",
    "0100000000",
  ),
  ("empty/empty", (NoGeometry, []), (NoGeometry, []), "FFFFFFFF2", "0100000000"),
  (
    "polygon/empty",
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)]]]),
    (NoGeometry, []),
    "FF2FF1FF2",
    "0100000000",
  ),
  (
    "line/empty",
    (LineString, [[[(0.0, 0.0), (1.0, 1.0)]]]),
    (NoGeometry, []),
    "FF1FF0FF2",
    "0100000000",
  ),
  (
    "bowtie/point",
    (Polygon, [[[(0.0, 0.0), (2.0, 2.0), (2.0, 0.0), (0.0, 2.0), (0.0, 0.0)]]]),
    (Point, [[[(0.5, 1.0)]]]),
    "0F2FF1FF2",
    "1010100000",
  ),
  (
    "bowtie/polygon",
    (Polygon, [[[(0.0, 0.0), (2.0, 2.0), (2.0, 0.0), (0.0, 2.0), (0.0, 0.0)]]]),
    (Polygon, [[[(0.0, 0.0), (2.0, 0.0), (2.0, 2.0), (0.0, 2.0), (0.0, 0.0)]]]),
    "21211F212",
    "1001010010",
  ),
  (
    "bowtie/line",
    (Polygon, [[[(0.0, 0.0), (2.0, 2.0), (2.0, 0.0), (0.0, 2.0), (0.0, 0.0)]]]),
    (LineString, [[[(-1.0, 1.0), (3.0, 1.0)]]]),
    "1F20F1102",
    "1000000100",
  ),
  (
    "duplicate points/polygon",
    (
      Polygon,
      [
        [
          [
            (0.0, 0.0),
            (4.0, 0.0),
            (4.0, 0.0),
            (4.0, 4.0),
            (0.0, 4.0),
            (0.0, 4.0),
            (0.0, 0.0),
          ],
        ],
      ],
    ),
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)]]]),
    "2FFF1FFF2",
    "1011110001",
  ),
  (
    "zero-length line/point",
    (LineString, [[[(1.0, 1.0), (1.0, 1.0)]]]),
    (Point, [[[(1.0, 1.0)]]]),
    "0FFFFFFF2",
    "1011110000",
  ),
  (
    "zero-length segment/line",
    (LineString, [[[(0.0, 0.0), (1.0, 1.0), (1.0, 1.0), (2.0, 2.0)]]]),
    (LineString, [[[(0.0, 2.0), (2.0, 0.0)]]]),
    "0F1FF0102",
    "1000000100",
  ),
  (
    "self-crossing line/point",
    (LineString, [[[(0.0, 0.0), (2.0, 2.0), (2.0, 0.0), (0.0, 2.0)]]]),
    (Point, [[[(1.0, 1.0)]]]),
    "0F1FF0FF2",
    "1010100000",
  ),
  (
    "self-crossing line/line",
    (LineString, [[[(0.0, 0.0), (2.0, 2.0), (2.0, 0.0), (0.0, 2.0)]]]),
    (LineString, [[[(0.0, 0.0), (2.0, 2.0)]]]),
    "101F00FF2",
    "1010100000",
  ),
  (
    "collapsed polygon/line",
    (Polygon, [[[(0.0, 0.0), (2.0, 0.0), (0.0, 0.0), (0.0, 0.0)]]]),
    (LineString, [[[(0.0, 0.0), (2.0, 0.0)]]]),
    "FFF10FFF2",
    "1000101000",
  ),
  (
    "overlapping multipolygon/point",
    (
      MultiPolygon,
      [
        [[(0.0, 0.0), (2.0, 0.0), (2.0, 2.0), (0.0, 2.0), (0.0, 0.0)]],
        [[(1.0, 1.0), (3.0, 1.0), (3.0, 3.0), (1.0, 3.0), (1.0, 1.0)]],
      ],
    ),
    (Point, [[[(1.5, 1.5)]]]),
    "throws",
    "xxx0x0xxx0",
  ),
  (
    "overlapping multipolygon/polygon",
    (
      MultiPolygon,
      [
        [[(0.0, 0.0), (2.0, 0.0), (2.0, 2.0), (0.0, 2.0), (0.0, 0.0)]],
        [[(1.0, 1.0), (3.0, 1.0), (3.0, 3.0), (1.0, 3.0), (1.0, 1.0)]],
      ],
    ),
    (Polygon, [[[(0.0, 0.0), (3.0, 0.0), (3.0, 3.0), (0.0, 3.0), (0.0, 0.0)]]]),
    "throws",
    "10x1x1xxxx",
  ),
  (
    "hole outside shell/point",
    (
      Polygon,
      [
        [
          [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0), (0.0, 0.0)],
          [(2.0, 2.0), (3.0, 2.0), (3.0, 3.0), (2.0, 3.0), (2.0, 2.0)],
        ],
      ],
    ),
    (Point, [[[(2.5, 2.5)]]]),
    "FF2FF10F2",
    "0100000000",
  ),
  (
    "fractional crossing",
    (LineString, [[[(0.1, 0.2), (3.7, 2.9)]]]),
    (LineString, [[[(0.3, 2.8), (3.1, 0.05)]]]),
    "0F1FF0102",
    "1000000100",
  ),
  (
    "near-collinear",
    (LineString, [[[(0.0, 0.0), (10.0, 10.000000000000002)]]]),
    (LineString, [[[(5.0, 5.0), (20.0, 20.0)]]]),
    "FF1FF0102",
    "0100000000",
  ),
  (
    "geographic polygons",
    (
      Polygon,
      [
        [
          [
            (139.69, 35.68),
            (139.76, 35.68),
            (139.76, 35.71),
            (139.69, 35.71),
            (139.69, 35.68),
          ],
        ],
      ],
    ),
    (
      Polygon,
      [[[(139.7, 35.69), (139.8, 35.66), (139.75, 35.75), (139.7, 35.69)]]],
    ),
    "212101212",
    "1000000010",
  ),
  (
    "line touching polygon from inside",
    (LineString, [[[(2.0, 2.0), (4.0, 2.0)]]]),
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)]]]),
    "1FF00F212",
    "1001010000",
  ),
  (
    "line closing on polygon",
    (LineString, [[[(0.0, 0.0), (2.0, 2.0), (4.0, 0.0)]]]),
    (Polygon, [[[(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)]]]),
    "1FFF0F212",
    "1001010000",
  ),
]

///|
test "relate, relate_checked and predicate match JSTS on hand-written cases" {
  for c in cases {
    check_case(c.0, c.1, c.2, c.3, c.4)
  }
}

///|
/// Per case: JSTS's dimensions, its IntersectionMatrix methods (isIntersects,
/// isDisjoint, isContains, isWithin, isCovers, isCoveredBy, isTouches,
/// isCrosses, isOverlaps, isEquals) and `matches` of `patterns`.
let methods : Array[(String, Int32, Int32, String, String)] = [
  ("point/point equal", 0, 0, "1011110001", "10101000"),
  ("point/point apart", 0, 0, "0100000000", "01000000"),
  ("point/line interior", 0, 1, "1001010000", "00101000"),
  ("point/line vertex", 0, 1, "1001010000", "00101000"),
  ("point/line endpoint", 0, 1, "1000011000", "00010000"),
  ("point/line off", 0, 1, "0100000000", "01000000"),
  ("point/closed line", 0, 1, "1001010000", "00101000"),
  ("point/polygon inside", 0, 2, "1001010000", "00101000"),
  ("point/polygon edge", 0, 2, "1000011000", "00010000"),
  ("point/polygon vertex", 0, 2, "1000011000", "00010000"),
  ("point/polygon hole", 0, 2, "0100000000", "01000000"),
  ("point/polygon hole edge", 0, 2, "1000011000", "00010000"),
  ("point/polygon outside", 0, 2, "0100000000", "01000000"),
  ("point/polygon outside in envelope", 0, 2, "0100000000", "01000000"),
  ("polygon/point", 2, 0, "1010100000", "00101000"),
  ("triangle/point", 2, 0, "1010100000", "00101000"),
  ("line/line cross", 1, 1, "1000000100", "00101000"),
  ("line/line touch at end", 1, 1, "1000001000", "00000001"),
  ("line/line end on interior", 1, 1, "1000001000", "00010000"),
  ("line/line collinear overlap", 1, 1, "1000000010", "00110100"),
  ("line/line identical", 1, 1, "1011110001", "10100001"),
  ("line/line reversed", 1, 1, "1011110001", "10100001"),
  ("line/line contained", 1, 1, "1010100000", "00110000"),
  ("line/line disjoint", 1, 1, "0100000000", "01000000"),
  ("line/line disjoint envelopes overlap", 1, 1, "0100000000", "01000000"),
  ("closed line/line", 1, 1, "1000001000", "00010000"),
  ("closed line/closed line", 1, 1, "1000000100", "00101000"),
  ("line/polygon inside", 1, 2, "1001010000", "00100000"),
  ("line/polygon crossing", 1, 2, "1000000100", "00110100"),
  ("line/polygon along edge", 1, 2, "1000011000", "00010001"),
  ("line/polygon part of edge", 1, 2, "1000011000", "00010001"),
  ("line/polygon touching vertex", 1, 2, "1000001000", "00000001"),
  ("line/polygon through", 1, 2, "1000000100", "00110100"),
  ("line/polygon in hole", 1, 2, "0100000000", "01000000"),
  ("polygon/line crossing", 2, 1, "1000000100", "00110100"),
  ("triangle/line inside", 2, 1, "1010100000", "00110000"),
  ("polygon/polygon disjoint", 2, 2, "0100000000", "01000000"),
  ("polygon/polygon touching edge", 2, 2, "1000001000", "00000001"),
  ("polygon/polygon touching corner", 2, 2, "1000001000", "00000001"),
  ("polygon/polygon overlapping", 2, 2, "1000000010", "00110011"),
  ("polygon/polygon containing", 2, 2, "1010100000", "00110000"),
  ("polygon/polygon contained touching", 2, 2, "1010100000", "00110001"),
  ("polygon/polygon equal", 2, 2, "1011110001", "10100001"),
  ("polygon/polygon equal other start", 2, 2, "1011110001", "10100001"),
  ("triangles equal", 2, 2, "1011110001", "10100001"),
  ("polygon in hole", 2, 2, "0100000000", "01000000"),
  ("polygon filling hole", 2, 2, "1000001000", "00000001"),
  ("polygon over hole", 2, 2, "1000000010", "00110000"),
  ("triangle/triangle overlapping", 2, 2, "1000000010", "00110011"),
  ("triangle/rectangle", 2, 2, "1010100000", "00110001"),
  ("rectangle/triangle", 2, 2, "1001010000", "00100001"),
  ("multipolygon/polygon", 2, 2, "1000000010", "00110011"),
  ("multipolygon touching parts/polygon", 2, 2, "1001010000", "00100001"),
  ("multipolygon/multipolygon", 2, 2, "1000000010", "00100001"),
  ("multipolygon equal", 2, 2, "1011110001", "10100001"),
  ("multipoint/polygon", 0, 2, "1000000100", "00101000"),
  ("multipoint/polygon all inside", 0, 2, "1001010000", "00111000"),
  ("multipoint/line", 0, 1, "1001010000", "00111000"),
  ("multipoint/multipoint", 0, 0, "1000000010", "00101000"),
  ("multiline/polygon", 1, 2, "1000000100", "00100101"),
  ("multiline shared end/point", 1, 0, "1010100000", "00101000"),
  ("multiline three ends/point", 1, 0, "1000101000", "00000000"),
  ("multiline/line", 1, 1, "1011110001", "10100001"),
  ("empty/point", -1, 0, "0100000000", "01000000"),
  ("point/empty", 0, -1, "0100000000", "01000000"),
  ("empty/empty", -1, -1, "0100000000", "01000000"),
  ("polygon/empty", 2, -1, "0100000000", "01000000"),
  ("line/empty", 1, -1, "0100000000", "01000000"),
  ("bowtie/point", 2, 0, "1010100000", "00101000"),
  ("bowtie/polygon", 2, 2, "1000000010", "00110001"),
  ("bowtie/line", 2, 1, "1000000100", "00100100"),
  ("duplicate points/polygon", 2, 2, "1011110001", "10100001"),
  ("zero-length line/point", 1, 0, "1011110000", "10101000"),
  ("zero-length segment/line", 1, 1, "1000000100", "00101000"),
  ("self-crossing line/point", 1, 0, "1010100000", "00101000"),
  ("self-crossing line/line", 1, 1, "1010100000", "00110001"),
  ("collapsed polygon/line", 2, 1, "1000111000", "00000001"),
  ("hole outside shell/point", 2, 0, "0100000000", "01000000"),
  ("fractional crossing", 1, 1, "1000000100", "00101000"),
  ("near-collinear", 1, 1, "0100000000", "01000000"),
  ("geographic polygons", 2, 2, "1000000010", "00110011"),
  ("line touching polygon from inside", 1, 2, "1001010000", "00100001"),
  ("line closing on polygon", 1, 2, "1001010000", "00100001"),
]

///|
let patterns : Array[String] = [
  "T*F**FFF*", "FF*FF****", "T********", "*T*******", "0********", "1*T***T**", "212101212",
  "****T****",
]

///|
test "dimension and the matrix predicates match JSTS" {
  for m in methods {
    let (name, dim_a, dim_b, want, want_matches) = m
    guard cases.iter().find_first(c => c.0 == name) is Some(c) else {
      fail("no case \{name}")
    }
    let a = row(c.1)
    let b = row(c.2)
    assert_eq(
      (name, @relate.dimension(a, 0), @relate.dimension(b, 0)),
      (name, dim_a, dim_b),
    )
    let im = @relate.relate(a, 0, b, 0)
    let got = [
      im.is_intersects(),
      im.is_disjoint(),
      im.is_contains(),
      im.is_within(),
      im.is_covers(),
      im.is_covered_by(),
      im.is_touches(dim_a, dim_b),
      im.is_crosses(dim_a, dim_b),
      im.is_overlaps(dim_a, dim_b),
      im.is_equals(dim_a, dim_b),
    ]
    for k, g in got {
      assert_eq((name, k, g), (name, k, want[k] == '1'))
    }
    for k, p in patterns {
      assert_eq((name, p, im.matches(p)), (name, p, want_matches[k] == '1'))
    }
  }
}

///|
test "get reads entries by interior, boundary and exterior" {
  let a = row(
    (Polygon, [[[(0.0, 0.0), (2.0, 0.0), (2.0, 2.0), (0.0, 2.0), (0.0, 0.0)]]]),
  )
  let b = row((LineString, [[[(1.0, 1.0), (3.0, 1.0)]]]))
  let im = @relate.relate(a, 0, b, 0)
  assert_eq(im.to_string(), "1020F1102")
  assert_eq([im.get(0, 0), im.get(0, 1), im.get(0, 2)], [1, 0, 2])
  assert_eq([im.get(1, 0), im.get(1, 1), im.get(2, 1)], [0, -1, 0])
  assert_eq([im.get(-1, 0), im.get(0, 3), im.get(3, 3)], [-1, -1, -1])
}

///|
test "matches refuses patterns that are not nine symbols" {
  let a = row((Point, [[[(1.0, 1.0)]]]))
  let im = @relate.relate(a, 0, a, 0)
  assert_eq(im.to_string(), "0FFFFFFF2")
  assert_true(im.matches("0FFFFFFF2"))
  assert_true(im.matches("T*F**F***"))
  assert_false(im.matches("0FFFFFFF"))
  assert_false(im.matches("0FFFFFFF2*"))
  assert_false(im.matches(""))
  assert_false(im.matches("0FFFFFFFX"))
}

///|
test "dimension is -1 for empty rows and rows out of range" {
  let b = @geom.TableBuilder::new()
  b.end_feature(Polygon)
  b.point(0.0, 0.0)
  b.point(1.0, 1.0)
  b.end_ring()
  b.end_part()
  b.end_feature(MultiLineString)
  let t = b.finish()
  assert_eq(@relate.dimension(t, 0), -1)
  assert_eq(@relate.dimension(t, 1), 1)
  assert_eq(@relate.dimension(t, 2), -1)
  assert_eq(@relate.dimension(t, -1), -1)
}

///|
test "rows out of range relate as empty geometries" {
  let a = row((Point, [[[(1.0, 1.0)]]]))
  assert_eq(@relate.relate(a, 0, a, 5).to_string(), "FF0FFFFF2")
  assert_eq(@relate.relate(a, -1, a, 5).to_string(), "FFFFFFFF2")
  assert_false(@relate.predicate(a, 0, a, 5, "intersects"))
  assert_true(@relate.predicate(a, 0, a, 5, "disjoint"))
}

///|
test "predicate is false for unknown names" {
  let a = row((Point, [[[(1.0, 1.0)]]]))
  assert_true(@relate.predicate(a, 0, a, 0, "equals"))
  assert_false(@relate.predicate(a, 0, a, 0, "equalsExact"))
  assert_false(@relate.predicate(a, 0, a, 0, ""))
}

///|
test "relate_checked and within_limit refuse rows over MAX_RELATE_POINTS together" {
  let b = @geom.TableBuilder::new()
  for k in 0..<(@relate.MAX_RELATE_POINTS / 2 + 1) {
    b.point(k.to_double(), 0.0)
  }
  b.end_ring()
  b.end_part()
  b.end_feature(MultiPoint)
  b.point(0.0, 1.0)
  b.end_ring()
  b.end_part()
  b.end_feature(Point)
  let t = b.finish()
  assert_true(@relate.relate_checked(t, 0, t, 0) is None)
  assert_true(@relate.relate_checked(t, 0, t, 1) is Some(_))
  assert_true(@relate.relate_checked(t, 1, t, 1) is Some(_))
  assert_false(@relate.within_limit(t, 0, t, 0))
  assert_true(@relate.within_limit(t, 0, t, 1))
  let half = @relate.MAX_RELATE_POINTS / 2 + 1
  assert_eq(@relate.pair_points(t, 0, t, 1), half + 1)
  assert_eq(@relate.pair_points(t, 1, t, 9), 1)
}

///|
test "relate_checked is None where JSTS throws on invalid polygons" {
  let a = row(
    (
      MultiPolygon,
      [
        [[(0.0, 0.0), (2.0, 0.0), (2.0, 2.0), (0.0, 2.0), (0.0, 0.0)]],
        [[(1.0, 1.0), (3.0, 1.0), (3.0, 3.0), (1.0, 3.0), (1.0, 1.0)]],
      ],
    ),
  )
  let b = row(
    (Polygon, [[[(0.0, 0.0), (3.0, 0.0), (3.0, 3.0), (0.0, 3.0), (0.0, 0.0)]]]),
  )
  assert_true(@relate.relate_checked(a, 0, b, 0) is None)
  // relate still answers.
  assert_eq(@relate.relate(a, 0, b, 0).get(2, 2), 2)
}

///|
test "malformed rows terminate: NaN, infinities, short and open rings" {
  let nan = 0.0 / 0.0
  let inf = 1.0 / 0.0
  let geoms : Array[Geom] = [
    (Point, [[[(nan, 0.0)]]]),
    (Point, [[[(inf, inf)]]]),
    (LineString, [[[(0.0, 0.0), (nan, nan), (nan, nan), (1.0, 1.0)]]]),
    (LineString, [[[(-inf, 0.0), (inf, 0.0)]]]),
    (LineString, [[[(1.0, 1.0)]]]),
    (LineString, [[[(1.0, 1.0), (1.0, 1.0), (1.0, 1.0)]]]),
    (MultiPoint, [[[(0.0, 0.0), (nan, 1.0), (1.0, 1.0)]]]),
    (Polygon, [[[(0.0, 0.0), (2.0, 0.0), (0.0, 0.0)]]]),
    (Polygon, [[[(0.0, 0.0), (2.0, 0.0), (2.0, 2.0), (0.0, 2.0)]]]),
    (Polygon, [[[(0.0, 0.0), (nan, 0.0), (2.0, 2.0), (0.0, 2.0), (0.0, 0.0)]]]),
    (Polygon, [[[(0.0, 0.0), (inf, 0.0), (inf, inf), (0.0, inf), (0.0, 0.0)]]]),
    (
      Polygon,
      [
        [
          [(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0), (0.0, 0.0)],
          [(1.0, 1.0)],
          [(5.0, 5.0), (6.0, 5.0), (6.0, 6.0), (5.0, 5.0)],
        ],
      ],
    ),
    (
      MultiPolygon,
      [
        [[(0.0, 0.0), (2.0, 2.0), (2.0, 0.0), (0.0, 2.0), (0.0, 0.0)]],
        [[(1.0, 1.0)]],
      ],
    ),
  ]
  for ga in geoms {
    for gb in geoms {
      let a = row(ga)
      let b = row(gb)
      let im = @relate.relate(a, 0, b, 0)
      assert_eq(im.to_string().length(), 9)
      let _ = @relate.relate_checked(a, 0, b, 0)
      for p in predicate_names {
        let _ = @relate.predicate(a, 0, b, 0, p)
      }
    }
  }
}

///|
test "a table whose offsets disagree is read within bounds" {
  let t = row((Polygon, [[[(0.0, 0.0), (2.0, 0.0), (2.0, 2.0), (0.0, 0.0)]]]))
  t.point_ends[0] = 99
  t.part_ends.push(7)
  t.kinds.push(MultiPolygon)
  assert_eq(@relate.relate(t, 0, t, 1).get(2, 2), 2)
  assert_eq(@relate.dimension(t, 1), -1)
}
