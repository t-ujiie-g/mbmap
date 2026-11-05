///|
fn csv(
  text : String,
  options~ : @formats.CsvOptions = @formats.CsvOptions::new(),
) -> @geom.Table raise {
  @formats.read_csv(@utf8.encode(text)[:], options)
}

///|
fn csv_error(text : String, options : @formats.CsvOptions) -> String {
  try @formats.read_csv(@utf8.encode(text)[:], options) catch {
    e => e.message()
  } noraise {
    _ => "read"
  }
}

///|
/// Column `name`'s values.
fn values(t : @geom.Table, name : String) -> Array[@geom.Prop?] {
  match t.column(name) {
    Some(c) => c.values
    None => []
  }
}

///|
test "CSV fields are typed as papaparse's dynamicTyping types them" {
  let t = csv(
    "a,b,c,d,e,f,g,h,i,j,k,l,m,n\n007,1e3,NaN,,-0,1.,.5,TRUE,True,\" 12 \",9007199254740993,1e400,+1,0x10\n\"1\",\u{a0}2\u{3000},false,FALSE,1e-400,\"x\"\"\",-.5E+1,2020-01-01T00:00:00Z,true,\t3\n",
  )
  assert_eq(t.length(), 2)
  let row = (i : Int32) => t.columns.map(c => c.values[i])
  assert_eq(row(0), [
    Some(Num(7)),
    Some(Num(1000)),
    Some(Str("NaN")),
    Some(Null),
    Some(Num(-0.0)),
    Some(Num(1)),
    Some(Num(0.5)),
    Some(Bool(true)),
    Some(Str("True")),
    Some(Num(12)),
    Some(Str("9007199254740993")),
    Some(Str("1e400")),
    Some(Str("+1")),
    Some(Str("0x10")),
  ])
  assert_eq(row(1), [
    Some(Num(1)),
    Some(Num(2)),
    Some(Bool(false)),
    Some(Bool(false)),
    Some(Num(0)),
    Some(Str("x\"")),
    Some(Num(-5)),
    Some(Str("2020-01-01T00:00:00Z")),
    Some(Bool(true)),
    Some(Num(3)),
    None,
    None,
    None,
    None,
  ])
  // -0 keeps its sign.
  guard row(0)[4] is Some(Num(z)) else { fail("no number") }
  assert_eq(1.0 / z, -@double.infinity)
}

///|
test "without dynamic typing every field stays a string" {
  let t = csv(
    "a,b,lat,lon\n1,,35.5,139.25\n",
    options=@formats.CsvOptions::new(dynamic_typing=false),
  )
  assert_eq(t.columns.map(c => c.values[0]), [
    Some(Str("1")),
    Some(Str("")),
    Some(Str("35.5")),
    Some(Str("139.25")),
  ])
  assert_eq(t.coords, [139.25, 35.5])
}

///|
test "RFC 4180 quoting, line ends and a BOM" {
  let t = csv(
    "\u{feff}name,note\r\n\"a \"\"b\"\"\",\"line 1\nline 2\"\r\n\"c\"  ,d\rx,\"\"\n\"e\",\"f\"",
  )
  assert_eq(t.columns.map(c => c.name), ["name", "note"])
  assert_eq(values(t, "name"), [
    Some(Str("a \"b\"")),
    Some(Str("c")),
    Some(Str("x")),
    Some(Str("e")),
  ])
  assert_eq(values(t, "note"), [
    Some(Str("line 1\nline 2")),
    Some(Str("d")),
    Some(Null),
    Some(Str("f")),
  ])
}

///|
test "empty lines are skipped, extra fields dropped, missing ones absent" {
  let t = csv("\n\na,b\n1,2,3,4\n\n5\n \n")
  assert_eq(values(t, "a"), [Some(Num(1)), Some(Num(5)), Some(Str(" "))])
  assert_eq(values(t, "b"), [Some(Num(2)), None, None])
  assert_eq(t.columns.length(), 2)
}

///|
test "repeated header names are made unique as papaparse makes them" {
  let t = csv("a,a,a_1,a\n1,2,3,4\n")
  assert_eq(t.columns.map(c => c.name), ["a", "a_2", "a_1", "a_3"])
}

///|
test "the delimiter is guessed as papaparse guesses it, or given" {
  assert_eq(csv("a\tb\n1\t2\n").columns.map(c => c.name), ["a", "b"])
  assert_eq(csv("a;b\n1;2\n").columns.map(c => c.name), ["a", "b"])
  assert_eq(csv("a|b\n1|2\n").columns.map(c => c.name), ["a", "b"])
  // Commas vary between rows, semicolons do not.
  assert_eq(csv("a;b,c\n1;2\n3;4,5,6\n").columns.map(c => c.name), ["a", "b,c"])
  // One column: no delimiter averages two fields, so ','.
  assert_eq(csv("a;b\n").columns.length(), 0)
  assert_eq(csv("a;b\n1\n").columns.map(c => c.name), ["a;b"])
  let t = csv(
    "a,b;c\n1,2;3\n",
    options=@formats.CsvOptions::new(delimiter=';'.to_int()),
  )
  assert_eq(t.columns.map(c => c.name), ["a,b", "c"])
}

///|
test "without a header columns are named by position" {
  let t = csv("1,2\n3,4,5\n", options=@formats.CsvOptions::new(header=false))
  assert_eq(t.columns.map(c => c.name), ["0", "1", "2"])
  assert_eq(values(t, "2"), [None, Some(Num(5))])
}

///|
test "points come from latitude and longitude columns found by name" {
  let t = csv("name,Lat,LONGITUDE\na,35.5,139.25\nb,,139\nc,91x,1\n")
  assert_eq(t.kinds, [Point, NoGeometry, NoGeometry])
  assert_eq(t.coords, [139.25, 35.5])
  assert_eq(values(t, "Lat"), [Some(Num(35.5)), Some(Null), Some(Str("91x"))])
  let jp = csv("名前,緯度,経度\n東京駅,35.6812,139.7671\n")
  assert_eq(jp.coords, [139.7671, 35.6812])
  let xy = csv("x,y,lng\n1,2,3\n")
  assert_eq(xy.coords, [3.0, 2.0])
}

///|
test "a geometry column of WKT or hexadecimal WKB is found and left out of the properties" {
  let t = csv(
    "id,WKT\n1,\n2,POINT (1 2)\n3,\"GEOMETRYCOLLECTION (POINT (3 4), LINESTRING (0 0, 1 1))\"\n4,nope\n5,0101000000000000000000F03F0000000000000040\n",
  )
  assert_eq(t.kinds, [NoGeometry, Point, Point, LineString, NoGeometry, Point])
  assert_eq(t.columns.map(c => c.name), ["id"])
  assert_eq(values(t, "id"), [
    Some(Num(1)),
    Some(Num(2)),
    Some(Num(3)),
    Some(Num(3)),
    Some(Num(4)),
    Some(Num(5)),
  ])
  assert_eq(t.coords, [1.0, 2.0, 3.0, 4.0, 0.0, 0.0, 1.0, 1.0, 1.0, 2.0])
}

///|
test "a geometry-named column whose first value is no geometry is a property" {
  let t = csv("geometry,lat,lon\nround,1,2\nPOINT (5 6),3,4\n")
  assert_eq(t.coords, [2.0, 1.0, 4.0, 3.0])
  assert_eq(values(t, "geometry"), [
    Some(Str("round")),
    Some(Str("POINT (5 6)")),
  ])
}

///|
test "options name the geometry columns" {
  let t = csv(
    "a,b,shape\n1,2,POINT (7 8)\n",
    options=@formats.CsvOptions::new(latitude="a", longitude="b"),
  )
  assert_eq(t.coords, [2.0, 1.0])
  let g = csv(
    "a,b,shape\n1,2,POINT (7 8)\n",
    options=@formats.CsvOptions::new(geometry="shape"),
  )
  assert_eq(g.coords, [7.0, 8.0])
  assert_eq(
    csv_error("a,b\n1,2\n", @formats.CsvOptions::new(geometry="c")),
    "malformed CSV at 0: no column named \"c\"",
  )
  assert_eq(
    csv_error("a,b\n1,2\n", @formats.CsvOptions::new(latitude="a")),
    "malformed CSV at 0: latitude and longitude go together",
  )
}

///|
test "malformed CSV is refused" {
  let options = @formats.CsvOptions::new()
  assert_eq(
    csv_error("a,b\n\"x,1\n", options),
    "malformed CSV at 4: unterminated quoted field",
  )
  assert_eq(
    csv_error("a,b\n\"x\"y,1\n", options),
    "malformed CSV at 6: unexpected text after a quoted field",
  )
  assert_eq(
    csv_error("a\n\"x\"  ", options),
    "malformed CSV at 4: unexpected text after a quoted field",
  )
  assert_eq(
    csv_error("a\n1\n", @formats.CsvOptions::new(delimiter='"'.to_int())),
    "malformed CSV at 0: invalid delimiter",
  )
  assert_eq(
    csv_error("a\n1\n", @formats.CsvOptions::new(delimiter=300)),
    "malformed CSV at 0: invalid delimiter",
  )
  assert_eq(
    csv_error(",".repeat(@formats.MAX_CSV_COLUMNS) + "\n", options),
    "malformed CSV at 4096: more than 4096 fields in a row",
  )
}

///|
test "empty CSV input makes an empty table" {
  assert_eq(csv("").length(), 0)
  assert_eq(csv("\u{feff}").length(), 0)
}

///|
test "CSV geometry cells give their rows' SRIDs" {
  let srids = []
  let text = @utf8.encode(
    "geom,lat,lon\nSRID=6677;POINT (1 2),,\n0101000020110F0000000000000000F03F0000000000000040,,\nPOINT (5 6),,\n",
  )
  let t = @formats.read_csv(text[:], @formats.CsvOptions::new(), srids~)
  assert_eq(t.length(), 3)
  assert_eq(srids, [6677, 3857, 0])
  let latlon = []
  @formats.read_csv(
    b"lat,lon\n1,2\n"[:],
    @formats.CsvOptions::new(),
    srids=latlon,
  )
  |> ignore
  assert_eq(latlon, [0])
}
