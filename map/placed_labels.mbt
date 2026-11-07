///|
/// The labels shown at the last placement, for tests, a line each: layer id, tile z, x, y, feature, anchor
/// x, y (8192 units), variable anchor code (or -1), text and icon shown (1, 0), the text's layout (0-2: left,
/// center, right; -1 with one), their boxes (CSS px) and, along lines, each glyph's screen x:y:angle.
pub fn Map::placed_labels(self : Map) -> String {
  let out = StringBuilder()
  for _, draws in self.drawn {
    for d in draws {
      for m in d.meshes {
        guard m.labels is Some(s) && s.round == self.placement_round else {
          continue
        }
        for i in 0..<s.count {
          let icon = match s.icon {
            Some(ic) => ic.shown[i]
            None => false
          }
          guard s.shown[i] || icon else { continue }
          let row = i * LABEL_FLOATS
          let code = if s.anchor[i] >= 0 {
            s.anchors[s.anchor[i] * 3].to_int()
          } else {
            -1
          }
          let b = s.boxes
          out.write_string(
            "\{self.style.layers[m.layer].id},\{d.id.z},\{d.id.x},\{d.id.y},\{f32_at(s.labels, row + LABEL_FEATURE).to_int()},",
          )
          let ax = f32_at(s.labels, row).to_int()
          let ay = f32_at(s.labels, row + LABEL_Y).to_int()
          let flag = (v : Bool) => if v { 1 } else { 0 }
          let layout = if s.shown[i] &&
            f32_at(s.labels, row + LABEL_LAYOUTS) > 1.0 {
            s.variant[i]
          } else {
            -1
          }
          out.write_string(
            "\{ax},\{ay},\{code},\{flag(s.shown[i])},\{flag(icon)},\{layout}",
          )
          for k in 0..<BOX_FLOATS {
            out.write_string(",\{b[i * BOX_FLOATS + k]}")
          }
          // Along lines, each glyph's place on screen and angle.
          if s.line is Some(l) {
            let q0 = quad_at(s.labels, row + LABEL_FIRST)
            let n = quad_at(s.labels, row + LABEL_COUNT)
            out.write_string(",")
            for k in 0..<n {
              let g = (q0 + k) * 3
              let (cx, cy, _, cw) = d.at.matrix.apply(
                l.glyphs[g],
                l.glyphs[g + 1],
                0.0,
                1.0,
              )
              let sx = screen_x(cx, cw, self.transform.width)
              let sy = screen_y(cy, cw, self.transform.height)
              out.write_string("\{sx}:\{sy}:\{l.glyphs[g + 2]} ")
            }
          }
          out.write_string("\n")
        }
      }
    }
  }
  out.to_string()
}
