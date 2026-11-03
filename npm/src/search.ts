// `mbmap/search`: GeoSearch without its look (VISION §6). The providers that
// come with it ask no server; external APIs are providers of the same shape.
export { coordinates } from "./search/coordinates";
export { createSearch, type Search, type SearchOptions, type SearchState } from "./search/controller";
export { datasetSearch, normalize } from "./search/dataset";
export { parseLngLat, parsePlaneRectangular, parseUtm } from "./search/parse";
export type { LngLat, SearchProvider, SearchRequest, SearchResult, Transform } from "./search/types";
