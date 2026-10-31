// The MoonBit exports of bundle/main (esbuild aliases "mbmap-engine" to its
// js build). Keep in sync with bundle/main/main.mbt.
declare module "mbmap-engine" {
  export interface EngineMap {
    readonly __engineMap: unique symbol;
  }
  /** Tiles of GeoJSON sources, by source id (see map/dom.mbt `Provider`). */
  export type Provider = (source: string, z: number, x: number, y: number) => Promise<ArrayBuffer | null>;
  export function create_map(
    canvas: HTMLCanvasElement,
    style: string,
    lng: number,
    lat: number,
    zoom: number,
    bearing: number,
    pitch: number,
    workerUrl: string,
    wasmUrl: string,
    workers: number,
    geojson: Provider | null,
    font: string,
  ): EngineMap;
  export function map_camera(map: EngineMap): { lng: number; lat: number; zoom: number; bearing: number; pitch: number };
  export function map_set_camera(map: EngineMap, lng: number, lat: number, zoom: number, bearing: number, pitch: number): void;
  export function map_on_move(map: EngineMap, f: () => void): number;
  export function map_on_idle(map: EngineMap, f: () => void): number;
  export function map_off(map: EngineMap, id: number): void;
  export function map_destroy(map: EngineMap): void;
}
