// Ported from @tmcw/togeojson 7.1.3: BSD 2-Clause License, Copyright (c) 2019 Tom MacWright,
// Mapbox. See NOTICE.

///|
/// togeojson's `fixColor`: a KML `aabbggrr` color as `#rrggbb` and an opacity,
/// a 3- or 6-digit one as it is (after a `#`), anything else nothing.
fn color(p : Props, value : String, prefix : String) -> Unit {
  let key = if prefix == "stroke" || prefix == "fill" {
    prefix
  } else {
    prefix + "-color"
  }
  let v = if value.length() > 0 && value[0] == '#' {
    @xml.units(value, 1, value.length())
  } else {
    value
  }
  if v.length() == 6 || v.length() == 3 {
    p.set(key, Str("#" + v))
  } else if v.length() == 8 {
    p.set(prefix + "-opacity", Num(parse_hex2(v, 0) / 255.0))
    p.set(
      key,
      Str("#" + @xml.units(v, 6, 8) + @xml.units(v, 4, 6) + @xml.units(v, 2, 4)),
    )
  }
}

///|
/// `getColor`: the color of the first `color` under `node`.
fn Reader::color_of(
  self : Reader,
  p : Props,
  node : Int32,
  prefix : String,
) -> Unit {
  if self.doc.first(node, "color") is Some(c) {
    color(p, self.doc.text(c), prefix)
  }
}

///|
/// `numericProperty`: `num1(node, tag)` as `key` unless NaN.
fn Reader::numeric(
  self : Reader,
  p : Props,
  node : Int32,
  tag : String,
  key : String,
) -> Unit {
  let v = self.num1(node, tag)
  if !v.is_nan() {
    p.set(key, Num(v))
  }
}

///|
/// `extractIconHref`: the first `Icon`'s `href` as `icon`.
fn Reader::icon_href(self : Reader, p : Props, node : Int32) -> Unit {
  if self.doc.first(node, "Icon") is Some(icon) {
    let href = self.val(icon, "href")
    if href != "" {
      p.set("icon", Str(href))
    }
  }
}

///|
/// `extractStyle`: the first `PolyStyle`, `LineStyle`, `LabelStyle` and
/// `IconStyle` under `node`, as togeojson's simplestyle-like properties.
fn Reader::style(self : Reader, node : Int32) -> Props {
  let d = self.doc
  let p = Props::new()
  if d.first(node, "PolyStyle") is Some(poly) {
    self.color_of(p, poly, "fill")
    if self.val(poly, "fill") == "0" {
      p.set("fill-opacity", Num(0.0))
    }
    if self.val(poly, "outline") == "0" {
      p.set("stroke-opacity", Num(0.0))
    }
  }
  if d.first(node, "LineStyle") is Some(line) {
    self.color_of(p, line, "stroke")
    self.numeric(p, line, "width", "stroke-width")
  }
  if d.first(node, "LabelStyle") is Some(label) {
    self.color_of(p, label, "label")
    self.numeric(p, label, "scale", "label-scale")
  }
  if d.first(node, "IconStyle") is Some(icon) {
    self.color_of(p, icon, "icon")
    self.numeric(p, icon, "scale", "icon-scale")
    self.numeric(p, icon, "heading", "icon-heading")
    if d.first(icon, "hotSpot") is Some(hot) {
      let left = parse_float(d.attribute(hot, "x").unwrap_or(""), self.number)
      let top = parse_float(d.attribute(hot, "y").unwrap_or(""), self.number)
      if !left.is_nan() && !top.is_nan() {
        p.set(
          "icon-offset",
          Str(json_array([self.json_number(left), self.json_number(top)], 0, 2)),
        )
        p.set(
          "icon-offset-units",
          Str(
            json_array(
              [
                json_string(d.attribute(hot, "xunits").unwrap_or("")),
                json_string(d.attribute(hot, "yunits").unwrap_or("")),
              ],
              0,
              2,
            ),
          ),
        )
      }
    }
    self.icon_href(p, icon)
  }
  p
}

///|
/// `normalizeId`: `#` put in front unless there.
fn normalize_id(id : String) -> String {
  if id.length() > 0 && id[0] == '#' {
    id
  } else {
    "#" + id
  }
}

///|
/// `buildStyleMap`: every `Style` by its id (or its `CascadingStyle` parent's),
/// then every `StyleMap` as the style its first `styleUrl` names. Ids map to
/// style numbers; style `k`'s properties are `styles.items` from `ends[k - 1]`
/// to `ends[k]`.
fn Reader::style_map(
  self : Reader,
  ids : Lookup,
  styles : Props,
  ends : Array[Int32],
) -> Unit {
  let d = self.doc
  for s in d.elements(0, "Style") {
    let mut id = d.attribute(s, "id").unwrap_or("")
    if id == "" &&
      d.parent(s) is Some(parent) &&
      d.local_name(parent) == "CascadingStyle" {
      id = d.attribute(parent, "kml:id").unwrap_or("")
      if id == "" {
        id = d.attribute(parent, "id").unwrap_or("")
      }
    }
    ids.set(normalize_id(id), ends.length())
    for item in self.style(s).items {
      styles.items.push(item)
    }
    ends.push(styles.items.length())
  }
  for m in d.elements(0, "StyleMap") {
    let url = self.val(m, "styleUrl")
    let style = if url != "" { ids.get(normalize_id(url)) } else { -1 }
    if style >= 0 {
      ids.set(normalize_id(d.attribute(m, "id").unwrap_or("")), style)
    }
  }
}

///|
/// `extractCascadedStyle`: the first `styleUrl` and the style it names.
fn Reader::cascaded_style(
  self : Reader,
  p : Props,
  node : Int32,
  ids : Lookup,
  styles : Props,
  ends : Array[Int32],
) -> Unit {
  let url = self.val(node, "styleUrl")
  if url != "" {
    let url = normalize_id(url)
    p.set("styleUrl", Str(url))
    let style = ids.get(url)
    if style >= 0 {
      for i in @geom.start_of(ends, style)..<ends[style] {
        p.set(styles.items[i].0, styles.items[i].1)
      }
    }
  }
}
