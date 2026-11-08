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
  getProjectionData(params: {
    tileID: { canonical: { x: number; y: number; z: number }; wrap?: number } | null;
    applyGlobeMatrix?: boolean;
  }): ProjectionData;
}

/** MapLibre's projection data: on the globe its matrix, the Mercator one as fallback, the horizon plane and transition. */
export interface ProjectionData {
  mainMatrix: Float64Array | Float32Array;
  fallbackMatrix: Float64Array | Float32Array;
  tileMercatorCoords: [number, number, number, number];
  clippingPlane: [number, number, number, number];
  projectionTransition: number;
  clipAntimeridian?: boolean;
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

/** What MapLibre puts before every prelude. */
const HEAD = "const float PI = 3.141592653589793;\nuniform mat4 u_projection_matrix;\n";

/** MapLibre's Mercator prelude for custom layer shaders (`projectTile` and the like). */
const PRELUDE =
  "float projectLineThickness(float tileY) { return 1.0; }\nfloat projectCircleRadius(float tileY) { return 1.0; }\n" +
  "vec4 projectTile(vec2 p) { return u_projection_matrix * vec4(p, 0.0, 1.0); }\n" +
  "vec4 projectTile(vec2 p, vec2 rawPos) { vec4 r = u_projection_matrix * vec4(p, 0.0, 1.0);" +
  " if (rawPos.y < -32767.5 || rawPos.y > 32766.5) r.z = -10000000.0; return r; }\n" +
  "vec4 projectTileWithElevation(vec2 p, float e) { return u_projection_matrix * vec4(p, e, 1.0); }\n" +
  "vec4 projectTileFor3D(vec2 p, float e) { return projectTileWithElevation(p, e); }\n";

/** MapLibre 6.16's globe prelude (`_projection_globe.vertex.glsl`, comments and spaces left out). */
const GLOBE_PRELUDE = "#define GLOBE_RADIUS 6371008.8\n#ifndef PROJECTION_UBO\nuniform highp vec4 u_projection_tile_mercator_coords;uniform highp vec4 u_projection_clipping_plane;uniform highp float u_projection_transition;uniform mat4 u_projection_fallback_matrix;\n#endif\nout highp float v_projection_tile_x;vec3 globeRotateVector(vec3 vec,vec2 angles){vec3 axisRight=vec3(vec.z,0.0,-vec.x);vec3 axisUp=cross(axisRight,vec);axisRight=normalize(axisRight);axisUp=normalize(axisUp);vec2 t=tan(angles);return normalize(vec+axisRight*t.x+axisUp*t.y);}mat3 globeGetRotationMatrix(vec3 spherePos){vec3 axisRight=vec3(spherePos.z,0.0,-spherePos.x);vec3 axisDown=cross(axisRight,spherePos);axisRight=normalize(axisRight);axisDown=normalize(axisDown);return mat3(axisRight,axisDown,spherePos);}float circumferenceRatioAtTileY(float tileY){float mercator_pos_y=u_projection_tile_mercator_coords.y+u_projection_tile_mercator_coords.w*tileY;float t=exp(PI-(mercator_pos_y*PI*2.0));return(2.0*t)/(t*t+1.0);}float projectLineThickness(float tileY){float thickness=1.0/circumferenceRatioAtTileY(tileY);if(u_projection_transition<0.999){return mix(1.0,thickness,u_projection_transition);}else{return thickness;}}vec3 projectToSphere(vec2 translatedPos,vec2 rawPos){vec2 mercator_pos=u_projection_tile_mercator_coords.xy+u_projection_tile_mercator_coords.zw*translatedPos;float spherical_x=mercator_pos.x*PI*2.0+PI;float t=exp(PI-(mercator_pos.y*PI*2.0));float t2=t*t;float denom=t2+1.0;float sin_sy=(t2-1.0)/denom;float cos_sy=(2.0*t)/denom;vec3 pos=vec3(sin(spherical_x)*cos_sy,sin_sy,cos(spherical_x)*cos_sy);if(rawPos.y<-32767.5){pos=vec3(0.0,1.0,0.0);}if(rawPos.y>32766.5){pos=vec3(0.0,-1.0,0.0);}return pos;}vec3 projectToSphere(vec2 posInTile){return projectToSphere(posInTile,vec2(0.0,0.0));}float globeComputeClippingZ(vec3 spherePos){return(1.0-(dot(spherePos,u_projection_clipping_plane.xyz)+u_projection_clipping_plane.w));}vec4 interpolateProjection(vec2 posInTile,vec3 spherePos,float elevation){v_projection_tile_x=posInTile.x;vec3 elevatedPos=spherePos*(1.0+elevation/GLOBE_RADIUS);vec4 globePosition=u_projection_matrix*vec4(elevatedPos,1.0);globePosition.z=globeComputeClippingZ(elevatedPos)*globePosition.w;if(u_projection_transition>0.999){return globePosition;}vec4 flatPosition=u_projection_fallback_matrix*vec4(posInTile,elevation,1.0);const float z_globeness_threshold=0.2;vec4 result=globePosition;result.z=mix(0.0,globePosition.z,clamp((u_projection_transition-z_globeness_threshold)/(1.0-z_globeness_threshold),0.0,1.0));result.xyw=mix(flatPosition.xyw,globePosition.xyw,u_projection_transition);if((posInTile.y<-32767.5)||(posInTile.y>32766.5)){result=globePosition;const float poles_hidden_anim_percentage=0.02;result.z=mix(globePosition.z,100.0,pow(max((1.0-u_projection_transition)/poles_hidden_anim_percentage,0.0),8.0));}return result;}vec4 interpolateProjectionFor3D(vec2 posInTile,vec3 spherePos,float elevation){v_projection_tile_x=posInTile.x;vec3 elevatedPos=spherePos*(1.0+elevation/GLOBE_RADIUS);vec4 globePosition=u_projection_matrix*vec4(elevatedPos,1.0);if(u_projection_transition>0.999){return globePosition;}vec4 fallbackPosition=u_projection_fallback_matrix*vec4(posInTile,elevation,1.0);return mix(fallbackPosition,globePosition,u_projection_transition);}vec4 projectTile(vec2 posInTile){return interpolateProjection(posInTile,projectToSphere(posInTile),0.0);}vec4 projectTile(vec2 posInTile,vec2 rawPos){return interpolateProjection(posInTile,projectToSphere(posInTile,rawPos),0.0);}vec4 projectTileWithElevation(vec2 posInTile,float elevation){return interpolateProjection(posInTile,projectToSphere(posInTile),elevation);}vec4 projectTileFor3D(vec2 posInTile,float elevation){vec3 spherePos=projectToSphere(posInTile,posInTile);return interpolateProjectionFor3D(posInTile,spherePos,elevation);}\n";

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

/**
 * The options of one draw from the engine's numbers (`Map::custom_numbers`): the model-view-projection and
 * projection matrices, the field of view, near and far planes, the world size and pixels per meter; on the
 * globe then the transition, the globe's matrix and projection, its near and far planes and clipping plane.
 */
export function renderInput(n: ArrayLike<number>): CustomRenderMethodInput {
  const at = (i: number) => Float64Array.from({ length: 16 }, (_, j) => n[i + j]);
  const mvp = at(0);
  const [fov, world, ppm] = [n[32], n[35], n[36]];
  const transition = n[37] ?? 0;
  const globe = transition > 0;
  const main = globe ? Float32Array.from(at(38)) : undefined;
  const data = (fallback: Float64Array, coords: [number, number, number, number], t: number, z: number): ProjectionData => ({
    mainMatrix: main ?? fallback,
    fallbackMatrix: fallback,
    tileMercatorCoords: coords,
    clippingPlane: globe ? [n[72], n[73], n[74], n[75]] : [0, 0, 0, 0],
    projectionTransition: t,
    clipAntimeridian: globe && z === 0,
  });
  return {
    farZ: n[globe ? 71 : 34],
    nearZ: n[globe ? 70 : 33],
    fov,
    modelViewProjectionMatrix: globe ? at(38) : mvp,
    projectionMatrix: at(globe ? 54 : 16),
    shaderData: globe
      ? { variantName: "globe", vertexShaderPrelude: HEAD + GLOBE_PRELUDE, define: "#define GLOBE" }
      : { variantName: "mercator", vertexShaderPrelude: HEAD + PRELUDE, define: "#define PROJECTION_MERCATOR" },
    defaultProjectionData: data(scaled(mvp, world, world, world / ppm), [0, 0, 1, 1], transition, 0),
    getProjectionData({ tileID, applyGlobeMatrix }) {
      const t = applyGlobeMatrix ? transition : 0;
      if (!tileID) return data(new Float64Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]), [0, 0, 1, 1], t, 0);
      const { x, y, z } = tileID.canonical;
      const tiles = 2 ** z;
      const size = world / tiles;
      const tx = (x + tiles * (tileID.wrap ?? 0)) * size;
      return data(scaled(mvp, size / EXTENT, size / EXTENT, 1, tx, y * size), [x / tiles, y / tiles, 1 / tiles / EXTENT, 1 / tiles / EXTENT], t, z);
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
