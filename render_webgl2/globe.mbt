///|
/// Where a tile goes on the globe: `matrix` takes the unit sphere to clip
/// space, `tile` is the tile's mercator corner and size per tile unit (x, y,
/// sx, sy), `plane` the horizon plane (a, b, c, d) past which the sphere is
/// hidden, `transition` how far toward the globe the map is (0 to 1); the tile
/// is drawn as a mesh of `granularity` quads per edge reaching the poles when
/// `north` or `south`.
pub(all) struct GlobeTile {
  matrix : FixedArray[Double]
  tile : FixedArray[Double]
  plane : FixedArray[Double]
  transition : Double
  granularity : Int32
  north : Bool
  south : Bool
}

///|
#external
priv type JsGlobe

///|
extern "js" fn js_globe(
  matrix : FixedArray[Double],
  tile : FixedArray[Double],
  plane : FixedArray[Double],
  transition : Double,
  key : String,
) -> JsGlobe =
  #|(matrix, tile, plane, transition, key) => ({ matrix, tile, plane, transition, key })

///|
extern "js" fn gl_set_globe(gl : Gl, g : JsGlobe?) -> Unit =
  #|(c, g) => { c.globe = g ?? null; }

///|
extern "js" fn gl_has_tile_mesh(gl : Gl, key : String) -> Bool =
  #|(c, key) => c.hasTileMesh(key)

///|
extern "js" fn gl_add_tile_mesh(
  gl : Gl,
  key : String,
  vertices : FixedArray[Int32],
  indices : FixedArray[Int32],
) -> Unit =
  #|(c, key, vertices, indices) => c.addTileMesh(key, vertices, indices)

///|
/// Makes the next tile draws go onto the globe as `g` says, or flat for None.
fn Renderer::use_globe(self : Renderer, g : GlobeTile?) -> Unit {
  match g {
    None => gl_set_globe(self.gl, None)
    Some(g) => {
      let key = "\{g.granularity}\{if g.north { "n" } else { "" }}\{if g.south { "s" } else { "" }}"
      if !gl_has_tile_mesh(self.gl, key) {
        let (v, i) = @globe.tile_mesh(
          g.granularity,
          north=g.north,
          south=g.south,
        )
        gl_add_tile_mesh(self.gl, key, v, i)
      }
      gl_set_globe(
        self.gl,
        Some(js_globe(g.matrix, g.tile, g.plane, g.transition, key)),
      )
    }
  }
}

///|
/// Draws the background `color` (straight RGBA) over a tile on the globe.
pub fn Renderer::draw_globe_background(
  self : Renderer,
  at : Placement,
  color : FixedArray[Double],
) -> Unit {
  self.use_globe(at.globe)
  let a = color[3]
  gl_draw_background(self.gl, at.matrix.m, [
    color[0] * a,
    color[1] * a,
    color[2] * a,
    a,
  ])
}

///|
extern "js" fn gl_draw_background(
  gl : Gl,
  matrix : FixedArray[Double],
  color : FixedArray[Double],
) -> Unit =
  #|(c, matrix, k) => {
  #|  const gl = c.gl, p = c.background;
  #|  gl.useProgram(p.program);
  #|  c.place(p, matrix);
  #|  gl.uniform4f(p.u_color, k[0], k[1], k[2], k[3]);
  #|  c.drawTile();
  #|  gl.bindVertexArray(null);
  #|}

///|
/// Draws MapLibre's atmosphere around the globe: `inverse_projection` takes
/// clip space back to the camera's, `sun` is the light's direction there,
/// `globe` the globe's center in it and `radius` its radius (CSS pixels);
/// `blend` scales its opacity.
pub fn Renderer::draw_atmosphere(
  self : Renderer,
  inverse_projection : @core.Mat4,
  sun : (Double, Double, Double),
  globe : (Double, Double, Double),
  radius : Double,
  blend : Double,
) -> Unit {
  gl_draw_atmosphere(self.gl, inverse_projection.m, [
    sun.0,
    sun.1,
    sun.2,
    globe.0,
    globe.1,
    globe.2,
    radius,
    blend,
  ])
}

///|
extern "js" fn gl_draw_atmosphere(
  gl : Gl,
  inverse : FixedArray[Double],
  k : FixedArray[Double],
) -> Unit =
  #|(c, inverse, k) => {
  #|  const gl = c.gl, p = c.atmosphere;
  #|  gl.useProgram(p.program);
  #|  gl.uniformMatrix4fv(p.u_inv_proj, false, new Float32Array(inverse));
  #|  gl.uniform3f(p.u_sun_pos, k[0], k[1], k[2]);
  #|  gl.uniform3f(p.u_globe_position, k[3], k[4], k[5]);
  #|  gl.uniform1f(p.u_globe_radius, k[6]);
  #|  gl.uniform1f(p.u_atmosphere_blend, k[7]);
  #|  gl.bindVertexArray(c.empty);
  #|  gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  #|  gl.bindVertexArray(null);
  #|}
