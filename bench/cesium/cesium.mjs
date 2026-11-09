// The CesiumJS side of bench/cesium/run.mjs: the same tileset on a plain white ellipsoid (no Ion,
// imagery, terrain, sky or fog), with the selection settings mbmap and loaders.gl use, lowered as
// mbmap's `height` lowers it, and MapLibre's camera of ?view= as a lookAt around the center at 0 m.
import { HEIGHT, HEIGHT_OFFSET, FOV, ORBIT_FRAMES, VIEWS, WIDTH, cameraDistance, quantiles, settle, trackFrames } from "./views.mjs";

const Cesium = window.Cesium;
const frames = trackFrames();
const view = VIEWS[Number(new URLSearchParams(location.search).get("view") ?? 0)];
const credits = document.createElement("div");
const widget = new Cesium.CesiumWidget("map", {
  baseLayer: false,
  terrainProvider: new Cesium.EllipsoidTerrainProvider(),
  skyBox: false,
  skyAtmosphere: false,
  creditContainer: credits,
  useBrowserRecommendedResolution: true,
});
const scene = widget.scene;
scene.backgroundColor = Cesium.Color.WHITE;
scene.globe.baseColor = Cesium.Color.WHITE;
scene.globe.showGroundAtmosphere = false;
scene.globe.enableLighting = false;
scene.fog.enabled = false;
scene.screenSpaceCameraController.enableInputs = false;
const target = Cesium.Cartesian3.fromDegrees(view.center[0], view.center[1], 0);
const enu = Cesium.Transforms.eastNorthUpToFixedFrame(target);
// mbmap's light (Mapbox's default: azimuth 210°, polar 30°), as the direction it travels.
const DEG = Math.PI / 180;
const toLight = new Cesium.Cartesian3(Math.sin(30 * DEG) * Math.sin(210 * DEG), Math.sin(30 * DEG) * Math.cos(210 * DEG), Math.cos(30 * DEG));
const lightDirection = Cesium.Matrix4.multiplyByPointAsVector(enu, toLight, new Cesium.Cartesian3());
scene.light = new Cesium.DirectionalLight({ direction: Cesium.Cartesian3.negate(lightDirection, lightDirection) });
// PerspectiveFrustum.fov is the horizontal one when the viewport is wider than tall.
scene.camera.frustum.fov = WIDTH > HEIGHT ? 2 * Math.atan(Math.tan(FOV / 2) * (WIDTH / HEIGHT)) : FOV;

/** MapLibre's camera: heading is the bearing, pitch is measured from straight down. */
function place(bearing) {
  const range = cameraDistance(view);
  scene.camera.lookAt(target, new Cesium.HeadingPitchRange(bearing * DEG, -(90 - view.pitch) * DEG, range));
}
place(view.bearing);
let tileset = null;

/** The selected tiles' content URLs, or null while anything is asked for or processed. */
function drawn() {
  const s = tileset.statistics;
  if (!tileset.tilesLoaded || s.numberOfPendingRequests > 0 || s.numberOfTilesProcessing > 0 || tileset._selectedTiles.length === 0) return null;
  return tileset._selectedTiles.map((t) => t._contentResource.url).sort().join();
}

window.__run = async () => {
  const t0 = performance.now();
  tileset = await Cesium.Cesium3DTileset.fromUrl("/bench/fixtures/plateau-chiyoda/tileset.json", {
    maximumScreenSpaceError: 8,
    dynamicScreenSpaceError: false,
    foveatedScreenSpaceError: false,
    skipLevelOfDetail: false,
    cullRequestsWhileMoving: false,
    preloadWhenHidden: false,
  });
  const center = tileset.boundingSphere.center;
  const up = Cesium.Ellipsoid.WGS84.geodeticSurfaceNormal(center, new Cesium.Cartesian3());
  tileset.modelMatrix = Cesium.Matrix4.fromTranslation(Cesium.Cartesian3.multiplyByScalar(up, HEIGHT_OFFSET, up));
  scene.primitives.add(tileset);
  const settled = await settle(drawn);
  const tiles = tileset._selectedTiles;
  return {
    settleMs: settled - t0,
    selected: tiles.length,
    statisticsSelected: tileset.statistics.selected,
    contents: tiles.map((t) => new URL(t._contentResource.url, location.href).pathname).sort(),
  };
};

// Clips (null: does not) as mbmap's Map.setClipping does: planes in east, north, up meters at `origin` (the tileset lowered onto
// the ellipsoid there, so 0 m is the same ground), polygons of longitudes and latitudes; then settles.
window.__clip = async (c) => {
  // mbmap draws both faces, so a cut building shows its inside walls in both; black around, so pale faces count.
  tileset.backFaceCulling = false;
  scene.backgroundColor = Cesium.Color.BLACK;
  scene.globe.baseColor = Cesium.Color.BLACK;
  if (c) {
    scene.render();
    const at = Cesium.Transforms.eastNorthUpToFixedFrame(Cesium.Cartesian3.fromDegrees(c.origin[0], c.origin[1], c.origin[2] ?? 0));
    const frame = Cesium.Matrix4.multiply(Cesium.Matrix4.inverse(tileset.clippingPlanesOriginMatrix, new Cesium.Matrix4()), at, new Cesium.Matrix4());
    if (c.planes?.length) {
      tileset.clippingPlanes = new Cesium.ClippingPlaneCollection({
        planes: c.planes.map(([x, y, z, d]) => new Cesium.ClippingPlane(new Cesium.Cartesian3(x, y, z), d)),
        modelMatrix: frame,
        unionClippingRegions: c.unionClippingRegions ?? false,
        edgeWidth: c.edgeWidth ?? 0,
        edgeColor: c.edgeColor ? new Cesium.Color(...c.edgeColor, 1) : Cesium.Color.WHITE,
      });
    }
    if (c.polygons?.length) {
      tileset.clippingPolygons = new Cesium.ClippingPolygonCollection({
        polygons: c.polygons.map((ring) => new Cesium.ClippingPolygon({ positions: Cesium.Cartesian3.fromDegreesArray(ring.flat()) })),
        inverse: c.inverse ?? false,
      });
    }
  }
  await settle(drawn);
};

window.__orbit = async () => {
  frames.clear();
  await new Promise((done) => {
    let i = 0;
    const step = () => {
      place(view.bearing + ++i);
      if (i < ORBIT_FRAMES) requestAnimationFrame(step);
      else done();
    };
    requestAnimationFrame(step);
  });
  const cpu = quantiles([...frames.values()]);
  place(view.bearing);
  await settle(drawn);
  return cpu;
};

window.__renderer = () => {
  const gl = scene.context._gl;
  const ext = gl.getExtension("WEBGL_debug_renderer_info");
  return ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
};
window.__pageReady = true;
