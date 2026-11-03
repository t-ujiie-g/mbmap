// Custom layers (MapLibre's CustomLayerInterface): the facade loads this file with the first
// one. The engine calls `draw` where a layer sits in the style; the layer's code runs between a
// saved and a restored GL state. Import-free, so that `npm test` can load it.

/** MapLibre's `EXTENT`, the tile units of `getProjectionData`'s matrices. */
const EXTENT = 8192;

/**
 * What `prerender` and `render` get, as MapLibre 6.16 gives it: `modelViewProjectionMatrix` takes world
 * pixels and meters (MapLibre's own), `defaultProjectionData.mainMatrix` Mercator coordinates 0 to 1
 * (z in the same units), `getProjectionData({tileID})` a tile's 8192 units.
 */
export interface CustomRenderMethodInput {
  farZ: number;
  nearZ: number;
  fov: number;
  modelViewProjectionMatrix: Float64Array;
  projectionMatrix: Float64Array;
  shaderData: { variantName: string; vertexShaderPrelude: string; define: string };
  defaultProjectionData: ProjectionData;
  getProjectionData(params: { tileID: { canonical: { x: number; y: number; z: number }; wrap?: number } | null }): ProjectionData;
}

/** MapLibre's projection data for Mercator: the matrix and the identity of the other fields. */
export interface ProjectionData {
  mainMatrix: Float64Array;
  fallbackMatrix: Float64Array;
  tileMercatorCoords: [number, number, number, number];
  clippingPlane: [number, number, number, number];
  projectionTransition: number;
}

/** MapLibre's `CustomLayerInterface`: `renderingMode` "3d" shares the depth buffer with extrusions and terrain. */
export interface CustomLayerInterface {
  id: string;
  type: "custom";
  renderingMode?: "2d" | "3d";
  onAdd?(map: unknown, gl: WebGL2RenderingContext): void;
  onRemove?(map: unknown, gl: WebGL2RenderingContext): void;
  prerender?(gl: WebGL2RenderingContext, options: CustomRenderMethodInput): void;
  render(gl: WebGL2RenderingContext, options: CustomRenderMethodInput): void;
}

/** MapLibre's Mercator prelude for custom layer shaders (`projectTile` and the like). */
const PRELUDE =
  "const float PI = 3.141592653589793;\nuniform mat4 u_projection_matrix;\n" +
  "float projectLineThickness(float tileY) { return 1.0; }\nfloat projectCircleRadius(float tileY) { return 1.0; }\n" +
  "vec4 projectTile(vec2 p) { return u_projection_matrix * vec4(p, 0.0, 1.0); }\n" +
  "vec4 projectTile(vec2 p, vec2 rawPos) { vec4 r = u_projection_matrix * vec4(p, 0.0, 1.0);" +
  " if (rawPos.y < -32767.5 || rawPos.y > 32766.5) r.z = -10000000.0; return r; }\n" +
  "vec4 projectTileWithElevation(vec2 p, float e) { return u_projection_matrix * vec4(p, e, 1.0); }\n" +
  "vec4 projectTileFor3D(vec2 p, float e) { return projectTileWithElevation(p, e); }\n";

/** Column-major `m` times a scale by `x`, `y`, `z`, then translated by `tx`, `ty` (scaled units). */
function scaled(m: Float64Array, x: number, y: number, z: number, tx = 0, ty = 0): Float64Array {
  const out = new Float64Array(16);
  for (let r = 0; r < 4; r++) {
    out[r] = m[r] * x;
    out[4 + r] = m[4 + r] * y;
    out[8 + r] = m[8 + r] * z;
    out[12 + r] = m[r] * tx + m[4 + r] * ty + m[12 + r];
  }
  return out;
}

const projection = (main: Float64Array, coords: [number, number, number, number]): ProjectionData => ({
  mainMatrix: main,
  fallbackMatrix: main,
  tileMercatorCoords: coords,
  clippingPlane: [0, 0, 0, 0],
  projectionTransition: 0,
});

/**
 * The options of one draw from the engine's numbers (`Map::custom_numbers`): the model-view-projection and
 * projection matrices, the field of view, near and far planes, the world size and pixels per meter.
 */
export function renderInput(n: ArrayLike<number>): CustomRenderMethodInput {
  const mvp = Float64Array.from({ length: 16 }, (_, i) => n[i]);
  const [fov, nearZ, farZ, world, ppm] = [n[32], n[33], n[34], n[35], n[36]];
  return {
    farZ,
    nearZ,
    fov,
    modelViewProjectionMatrix: mvp,
    projectionMatrix: Float64Array.from({ length: 16 }, (_, i) => n[16 + i]),
    shaderData: { variantName: "mercator", vertexShaderPrelude: PRELUDE, define: "#define PROJECTION_MERCATOR" },
    defaultProjectionData: projection(scaled(mvp, world, world, world / ppm), [0, 0, 1, 1]),
    getProjectionData({ tileID }) {
      if (!tileID) return projection(new Float64Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]), [0, 0, 1, 1]);
      const { x, y, z } = tileID.canonical;
      const tiles = 2 ** z;
      const size = world / tiles;
      const tx = (x + tiles * (tileID.wrap ?? 0)) * size;
      return projection(scaled(mvp, size / EXTENT, size / EXTENT, 1, tx, y * size), [x / tiles, y / tiles, 1 / tiles / EXTENT, 1 / tiles / EXTENT]);
    },
  };
}

/** The GL state the renderer relies on, saved before a layer's code runs and restored after. */
function saveState(gl: WebGL2RenderingContext): () => void {
  const caps = [gl.BLEND, gl.DEPTH_TEST, gl.CULL_FACE, gl.STENCIL_TEST, gl.SCISSOR_TEST, gl.POLYGON_OFFSET_FILL, gl.SAMPLE_ALPHA_TO_COVERAGE, gl.SAMPLE_COVERAGE, gl.RASTERIZER_DISCARD, gl.DITHER];
  const on = caps.map((c) => gl.isEnabled(c));
  const p = (k: number) => gl.getParameter(k);
  const active = p(gl.ACTIVE_TEXTURE);
  const textures = [0, 1, 2, 3].map((i) => {
    gl.activeTexture(gl.TEXTURE0 + i);
    return p(gl.TEXTURE_BINDING_2D);
  });
  const blend = [gl.BLEND_SRC_RGB, gl.BLEND_DST_RGB, gl.BLEND_SRC_ALPHA, gl.BLEND_DST_ALPHA, gl.BLEND_EQUATION_RGB, gl.BLEND_EQUATION_ALPHA].map(p);
  const [framebuffer, viewport, scissor, program, vao, buffer, depthFunc, depthMask, colorMask, cullFace, frontFace, depthRange] = [
    gl.FRAMEBUFFER_BINDING, gl.VIEWPORT, gl.SCISSOR_BOX, gl.CURRENT_PROGRAM, gl.VERTEX_ARRAY_BINDING, gl.ARRAY_BUFFER_BINDING,
    gl.DEPTH_FUNC, gl.DEPTH_WRITEMASK, gl.COLOR_WRITEMASK, gl.CULL_FACE_MODE, gl.FRONT_FACE, gl.DEPTH_RANGE,
  ].map(p);
  const unpack = [gl.UNPACK_ALIGNMENT, gl.UNPACK_FLIP_Y_WEBGL, gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL];
  const unpacked = unpack.map(p);
  // MapLibre's `setCustomLayerDefaults`.
  gl.bindVertexArray(null);
  gl.disable(gl.CULL_FACE);
  gl.activeTexture(gl.TEXTURE0);
  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 4);
  gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
  gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
  return () => {
    caps.forEach((c, i) => (on[i] ? gl.enable(c) : gl.disable(c)));
    gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
    gl.viewport(viewport[0], viewport[1], viewport[2], viewport[3]);
    gl.scissor(scissor[0], scissor[1], scissor[2], scissor[3]);
    gl.useProgram(program);
    gl.bindVertexArray(vao);
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.blendFuncSeparate(blend[0], blend[1], blend[2], blend[3]);
    gl.blendEquationSeparate(blend[4], blend[5]);
    gl.depthFunc(depthFunc);
    gl.depthMask(depthMask);
    gl.colorMask(colorMask[0], colorMask[1], colorMask[2], colorMask[3]);
    gl.cullFace(cullFace);
    gl.frontFace(frontFace);
    gl.depthRange(depthRange[0], depthRange[1]);
    unpack.forEach((k, i) => gl.pixelStorei(k, unpacked[i]));
    textures.forEach((t, i) => {
      gl.activeTexture(gl.TEXTURE0 + i);
      gl.bindTexture(gl.TEXTURE_2D, t);
    });
    gl.activeTexture(active);
  };
}

/** The custom layers of one map: `onAdd` and `onRemove` with the map and its context, `draw` for the engine. */
export class CustomLayers {
  #layers = new Map<string, CustomLayerInterface>();
  #map: unknown;
  #gl: WebGL2RenderingContext;

  constructor(map: unknown, gl: WebGL2RenderingContext) {
    this.#map = map;
    this.#gl = gl;
  }

  add(layer: CustomLayerInterface): void {
    this.#layers.set(layer.id, layer);
    layer.onAdd?.(this.#map, this.#gl);
  }

  remove(id: string): void {
    const layer = this.#layers.get(id);
    this.#layers.delete(id);
    layer?.onRemove?.(this.#map, this.#gl);
  }

  get(id: string): CustomLayerInterface | undefined {
    return this.#layers.get(id);
  }

  ids(): string[] {
    return [...this.#layers.keys()];
  }

  /** Runs layer `id`'s `prerender` or `render` (MapLibre's depth modes: tested for "3d", off for "2d"). */
  draw = (id: string, prerender: boolean, numbers: ArrayLike<number>): void => {
    const layer = this.#layers.get(id);
    const f = prerender ? layer?.prerender : layer?.render;
    if (!layer || !f) return;
    const gl = this.#gl;
    const restore = saveState(gl);
    if (!prerender && layer.renderingMode === "3d") {
      gl.enable(gl.DEPTH_TEST);
      gl.depthFunc(gl.LEQUAL);
      gl.depthMask(true);
    } else {
      gl.disable(gl.DEPTH_TEST);
    }
    try {
      f.call(layer, gl, renderInput(numbers));
    } catch (err) {
      queueMicrotask(() => {
        throw err;
      });
    } finally {
      restore();
    }
  };

  destroy(): void {
    for (const id of this.ids()) this.remove(id);
  }
}
