# mbmap

MoonBit で書いた、Web 向けの軽量なベクトルタイル地図描画エンジン（開発中）。API の名前と形は MapLibre GL JS に寄せている。

```js
import { Map } from "mbmap";

const map = new Map({
  container: "map",                 // 要素か id。要素には大きさを与えておく
  style: "https://example.com/style.json", // URL（認証情報なしで取得）かスタイルのオブジェクト
  center: [139.7671, 35.6812],
  zoom: 14,
});
map.on("load", () => console.log(map.getCenter(), map.getZoom()));
```

## 配布物

入口（`package.json` の `exports`）：

| ファイル | 内容 |
|---|---|
| `dist/index.js`, `dist/index.d.ts` | メインスレッドの ESM（`Map`）と型定義 |
| `dist/element.js` | Web Component `<mb-map>`（`mbmap/element`。import すると要素が登録される。`index.js` を import する） |
| `dist/ui.js` | 見た目を持たない UI のコントローラ（`mbmap/ui`） |
| `dist/search.js` | 見た目を持たない検索（GeoSearch、`mbmap/search`） |
| `dist/draw.js` | 見た目を持たない作図（`mbmap/draw`） |
| `dist/analysis.js` | 解析（`mbmap/analysis`）の入口 |
| `dist/geodesic.js` | 楕円体の上の計測（`mbmap/geodesic`）の入口 |
| `dist/data.js` | データの読み込み（CSV・WKT・WKB・Shapefile・TopoJSON・KML/KMZ・GPX・FlatGeobuf・GeoJSON）と書き出し（GeoJSON・CSV・KML、`mbmap/data`）の入口 |

`index.js` が、使うときだけ動的 import で読み込むもの（`index.js` と同じ場所に置く）：

| ファイル | 読み込む時 |
|---|---|
| `dist/geojson.js` | スタイルに GeoJSON ソースがあるとき |
| `dist/legacy.js` | 旧形式のフィルタやプロパティ関数（`["==", "class", "x"]`、`{stops: …}`）があるとき（式に変換する） |
| `dist/sprite.js` | スタイルに `sprite` があるとき |
| `dist/tilejson-merge.js` | `url` を持つソース（TileJSON か PMTiles）があるとき |
| `dist/pmtiles.js` | `pmtiles://` のソースがあるとき（アーカイブのヘッダーを読む） |
| `dist/geotiff-source.js` | `geotiff` のソースがあるとき（タイルは `mbmap/data` のワーカーが作るので、`data.js` と `data-worker.js`・`data.wasm`・`geotiff.wasm`・`data-geotiff.js` も隣に置く） |
| `dist/media.js` | image・video・canvas のソースがあるとき |
| `dist/custom.js` | 最初のカスタムレイヤーを足したとき |
| `dist/export.js` | 最初に `toBlob` を呼んだとき |

Worker と wasm：

| ファイル | 内容 |
|---|---|
| `dist/worker.js`, `dist/mbmap.wasm` | タイル Worker（モジュール Worker）と、それが読む wasm-gc |
| `dist/worker-labels.js`, `dist/worker-pmtiles.js`, `dist/worker-query.js` | タイル Worker の部品。ラベル、PMTiles、地物の問い合わせを初めて扱うときに、`worker.js` が自分の隣から読む |
| `dist/geojson-worker.js`, `dist/geojson.wasm` | GeoJSON ソースの Worker と wasm（読み込みとタイル分割） |
| `dist/geojson-properties.wasm` | 式を持つ GeoJSON の wasm。`clusterProperties` のあるソースがあるときだけ GeoJSON の Worker が読む |
| `dist/analysis-worker.js`, `dist/analysis.wasm` | 解析の Worker と wasm。`mbmap/analysis` を初めて呼んだときに起こす |
| `dist/geometry.wasm` | ジオメトリ演算（buffer、dissolve、clip、erase、intersect、split、merge）。解析の Worker が、初めて演算を呼んだときだけ読む |
| `dist/proj.wasm` | 座標系の変換。解析の Worker とデータの Worker が、初めて座標系を使ったときだけ読む |
| `dist/projstring.js` | PROJ 文字列のパーサ。`analysis.js` と `data.js` が、初めて PROJ 文字列を受け取ったときだけ自分の隣から読む |
| `dist/geodesic-worker.js`, `dist/geodesic.wasm` | `mbmap/geodesic` の Worker と wasm。初めて呼んだときに起こす |
| `dist/data-worker.js`, `dist/data.wasm` | `mbmap/data` の Worker と wasm。初めて呼んだときに起こす |
| `dist/data-zip.js`, `dist/data-crs.js`, `dist/data-fgb.js`, `dist/prjwkt.js` | データの Worker の部品。zip、4326 以外の座標、FlatGeobuf、`.prj` を初めて扱うときに、`data-worker.js` が自分の隣から読む（`prjwkt.js` は `data.js` の隣） |
| `dist/xml.wasm` | KML と GPX の読み込みと KML の書き出し。データの Worker が、初めて KML か GPX を扱うときだけ読む |
| `dist/geotiff.wasm`, `dist/data-geotiff.js` | GeoTIFF・COG の読み込み。データの Worker が、初めて `readRaster` を呼ぶときだけ読む |

どのファイルも、既定では `new URL("./worker.js", import.meta.url)` のように、読み込む側のモジュールの隣から読む。ESM をそのまま配信する場合（import map など）は、`dist/` をまるごと置けばそのまま動く。バンドラを使う場合、この書き方を解釈するかどうかはバンドラと設定によって違う。esbuild はこの `new URL` をそのまま残し、動的 import はバンドルに入れるので、Worker と wasm（`dist/` の `*.wasm` と `*worker*.js`）をバンドルの隣にコピーすれば動く（`examples/react/build.mjs`）。ほかのバンドラはまだ検証していない。動かないときは、ファイルを自分で配信して場所を渡す。

- `new Map` の `workerUrl` は `worker.js` の場所。`worker-labels.js`、`worker-pmtiles.js`、`worker-query.js` は、その隣に置く。`wasmUrl` は `mbmap.wasm` の場所。
- `geojsonWorkerUrl`、`geojsonWasmUrl`、`geojsonPropertiesWasmUrl`（`new Map` のオプション）は、`geojson-worker.js`、`geojson.wasm`、`geojson-properties.wasm` の場所。
- `index.js` の動的 import（上の表）、`analysis.js` と `data.js` の `projstring.js`、`data.js` の `prjwkt.js`、`data-worker.js` の `data-zip.js` と `data-crs.js` は、場所を変えられない。それぞれの隣に置く。
- `mbmap/analysis` の関数は、最後の引数のオプションで `workerUrl`（`analysis-worker.js`）、`wasmUrl`（`analysis.wasm`）、`geometryWasmUrl`、`projWasmUrl` を、`mbmap/geodesic` の関数は `workerUrl`（`geodesic-worker.js`）と `wasmUrl`（`geodesic.wasm`）を、`mbmap/data` の関数は `workerUrl`（`data-worker.js`）、`wasmUrl`（`data.wasm`）、`projWasmUrl`、`xmlUrl`（`xml.wasm`）を受け付ける。Worker は最初の呼び出しのオプションで起こす。

Worker はページと同じオリジンの http(s)、wasm は http(s) の URL に限る（`data:` や `blob:` は受け付けない）。モジュール Worker はページと同じオリジンでなければならない。

Content Security Policy を使うページでは、wasm のコンパイルに `script-src 'wasm-unsafe-eval'`、Worker に `worker-src 'self'`（または `script-src 'self'`）が要る。`eval` と `new Function` は使っていない。

## API

- `new Map(options)`：`container`、`style`、`center`、`zoom`、`bearing`（北から時計回りの度）、`pitch`（0〜85 度）、`workerCount`（0 なら自動、1〜4）、`workerUrl`、`wasmUrl`、`geojsonWorkerUrl`、`geojsonWasmUrl`、`geojsonPropertiesWasmUrl`（場所は「配布物」）、`fontFamily`（ラベルの CSS フォントファミリー。既定 `sans-serif`）、`strict`（既定 false。true にすると、まだ描けない内容を含むスタイルを拒む）、`attributionControl`（既定 true。表示中のレイヤーと地形が使うソースの `attribution` を、MapLibre と同じ順で文字列として表示する）。
  - まだ描けないプロパティ・式・レイヤーは、既定ではそれを除いて描き（プロパティは既定値に戻し、描けないレイヤーとソースは外す）、コンソールと `warning` イベント（`warnings`：`{path, layer, message}` の一覧）で知らせる。`strict: true` のときと、値が不正なときは、スタイルがオブジェクトなら例外を投げ、URL なら `error` イベントになる。
- `on` / `off` / `once(type, listener?)`：`load`（最初の描画）、`render`（描画のたび）、`idle`（落ち着くたび）、`move`（カメラが変わるたび）、`error`、`warning`（スタイルを描いたあと、除いた内容が変わったとき）、`styledata`（スタイルの読み込みと変更のたび）、`sourcedata`（その後に、加わったソースと変わったソースごとに。`sourceId` にソースの id、`dataType` は `"source"`。MapLibre と違い、タイルの読み込みでは出さない）、`styleimagemissing`（タイルが使う画像がないとき。`id` にその名前。1 つの名前に 1 回）。カメラとマウスのイベントは下に。
- `getCenter()`、`getZoom()`、`getBearing()`、`getPitch()`、`jumpTo({ center, zoom, bearing, pitch })`、`setCenter`、`setZoom`、`setBearing`、`setPitch`。bearing は -180〜180 に折り返し、pitch は 0〜85 に収める。値が変わらないときは `move` を出さない。有限でない値（NaN など）は TypeError になる。
- カメラの移動（MapLibre と同じ計算。`npm run camera:golden` で MapLibre 6.16 の Camera と比べている）：
  - `easeTo(options)`（既定 500ms）、`flyTo(options)`（ズームアウトして戻る。`curve`、`speed`、`screenSpeed`、`maxDuration`、`minZoom`）、`panBy`、`panTo`、`zoomTo`、`zoomIn`、`zoomOut`、`rotateTo`、`resetNorth`、`resetNorthPitch`、`snapToNorth`、`stop()`。どれも `center`、`zoom`、`bearing`、`pitch`、`around`（その点を動かさない）、`offset`、`duration`、`easing`、`animate`、`essential`（OS の「視差効果を減らす」でもアニメーションする）を受け付ける。
  - `fitBounds(bounds, { padding, maxZoom, bearing, linear })`（既定は flyTo、`linear: true` で easeTo）、`fitScreenCoordinates(p0, p1, bearing)`、`cameraForBounds(bounds, options)`。`bounds` は `[[西, 南], [東, 北]]`、`[西, 南, 東, 北]`、`LngLatBounds`。
  - `project(lngLat)`（画面の `{ x, y }`）、`unproject(point)`、`getBounds()`（`LngLatBounds`。傾けたときは地平線まで）、`isMoving()`、`isEasing()`、`isZooming()`、`isRotating()`。地形があるときの `project` と `unproject` は地面の高さを入れる（MapLibre と同じ）。
- 画面座標の追跡（マーカーやポップアップを DOM で描くため。`npm run track:golden` で MapLibre 6.16 と比べている）：
  - `track(lngLat, (p) => …)` は `{ getLngLat, setLngLat, remove }` を返す。`p` は `{ x, y, covered }`（CSS ピクセルと、地形に隠れているか）。描画のたび（と登録したとき）に、地図と同じフレームで呼ぶ。登録した点はまとめて 1 回で計算する。
  - 位置は地形の高さを入れたもの、`covered` は MapLibre の Marker が薄くなる判定（`isLocationOccluded`）と同じ。MapLibre は DEM ソースの minzoom より遠くを平らに描くため、そこでは高さが MapLibre と違う。
- 画像の書き出し：`toBlob({ pixelRatio, type, quality, maxSize })` は今の表示の画像を Promise<Blob> で返す（既定は画面の画素密度の PNG）。タイルが揃うのを待ってから画面外に描くので、画面は変わらない。GPU が一度に描ける大きさ（または `maxSize`）を超える画像は、分割して描いてつなぐ（`npm run export:golden`）。出典表示などの DOM は画像に入らない。
- 制限：`minZoom`・`maxZoom`（0〜24、既定 0 と 22）、`minPitch`・`maxPitch`（0〜85、既定 0 と 85）、`maxBounds`（表示がその範囲を出ない）。オプションでも、`setMinZoom` などの setter・getter でも変えられる。MapLibre と同じく、表示が南北の端（85.051129°）を越えないようにズームを上げる。
- 初期表示：`bounds`（と `fitBoundsOptions`）を渡すと、`center`・`zoom` の代わりにその範囲を表示する。
- 操作：`dragPan`、`scrollZoom`、`boxZoom`（Shift＋ドラッグ）、`dragRotate`、`keyboard`（矢印で 100px 移動、Shift＋矢印で回転・傾き、`+`・`-` でズーム）、`doubleClickZoom`（Shift で縮小）、`touchZoomRotate`、`touchPitch`（2 本指を上下に動かす）。オプションの `interactive: false` ですべて止め、`map.scrollZoom.disable()` のように 1 つずつ切り替えられる。ドラッグを離すと、MapLibre と同じ慣性で少し流れる。
- イベント：`movestart`・`move`・`moveend`、`zoomstart`・`zoom`・`zoomend`、`rotatestart`・`rotate`・`rotateend`、`pitchstart`・`pitch`・`pitchend`（MapLibre と同じ順）。ユーザーの操作によるものは `originalEvent` に DOM のイベントが入る。地図のパディング（`setPadding`）は未対応。
- スタイルの変更（MapLibre と同じ名前と引数）：
  - `setStyle(style, { transformStyle })`（オブジェクトか URL。`transformStyle(previous, next)` は MapLibre と同じく、前のスタイルと合わせて描くスタイルを作る）、`getStyle()`。前のスタイルと比べ、タイルの作り方が変わらないソースはタイルを残し、変わったソースは古いタイルを描いたまま読み直す。
  - `addLayer(layer, beforeId?)`、`removeLayer`、`moveLayer(id, beforeId?)`、`getLayer`、`getLayersOrder()`、`setPaintProperty`・`getPaintProperty`、`setLayoutProperty`・`getLayoutProperty`（`visibility` を含む）、`setFilter`・`getFilter`、`setLayerZoomRange`。
  - `addSource(id, source)`、`removeSource(id)`（レイヤーや地形が使っている間は `error`）、`getSource(id)`（`promoteId` を持つ。GeoJSON ソースは `setData(data)` でデータを差し替え、`getData()` はデータの写しを Promise で返す（URL なら `transformRequest` を通して取得する）。クラスタにしたソースは MapLibre と同じ `getClusterExpansionZoom(id)`、`getClusterChildren(id)`、`getClusterLeaves(id, limit, offset)` を持ち、Promise で答える。クラスタにしていないソースでは null になる）。
  - `setTerrain`・`getTerrain`、`setSky`・`getSky`、`setLight`・`getLight`（null で外す）。
  - `getSource(id)` は、image・video・canvas のソースでは MapLibre と同じ `setCoordinates(corners)`（左上から時計回り）、`updateImage({ url, image, coordinates })`、`play()`・`pause()`、`getVideo()`・`getCanvas()` を持つ。
  - 描けないスタイルになる変更は `error` イベントを出し、元のスタイルのまま描き続ける。スタイルの読み込み前に呼ぶと例外になる。
- 画像（パターンとアイコン。MapLibre と同じ名前）：`addImage(id, image, { pixelRatio, sdf })`（`ImageData`、`{ width, height, data }` の RGBA、画像・ImageBitmap・canvas）、`updateImage(id, image)`、`removeImage(id)`、`hasImage(id)`、`listImages()`（スプライトのものを含む）、`loadImage(url)`（`transformRequest` を通して取得し、`{ data: ImageBitmap }` を返す）。同じ名前の `addImage` と、ない名前の `updateImage` は `error` イベントになる。スタイルの `sprite`（URL か `{ id, url }` の一覧。画素密度 2 の画面では `@2x`）は自動で読む。
- カスタムレイヤー（MapLibre の `CustomLayerInterface`）：`addLayer({ id, type: "custom", renderingMode, onAdd, onRemove, prerender, render }, beforeId?)`。`render(gl, options)` の `options` は MapLibre 6.16 と同じ（`modelViewProjectionMatrix`、`defaultProjectionData`、`getProjectionData`、Mercator 用のシェーダの前置き）。`renderingMode: "3d"` は押し出しや地形と深度バッファを共有する。GL の状態はレイヤーの前に保存し、後に戻す。アニメーションは `triggerRepaint()` で次のフレームを頼む。`getStyle()` には入らず、`setStyle` で外れる（MapLibre と同じ）。地形があるときも、地形のテクスチャには描かず画面の上に描く。
- 地物の問い合わせ（結果は MapLibre と同じ。`npm run query:golden` で MapLibre 6.16 と比べている）：
  - `queryRenderedFeatures(geometry?, { layers, filter })`：点 `[x, y]` か範囲 `[[x0, y0], [x1, y1]]`（CSS ピクセル。省略すると地図全体）に描かれている地物を、上のものから順に返す。各地物には `layer`（スタイルのレイヤー）、`source`、`sourceLayer`、`state` が付く。
  - `querySourceFeatures(sourceId, { sourceLayer, filter })`：描画中のタイルにあるソースの地物を返す。
  - ジオメトリはワーカーが持つので、どちらも Promise を返す（MapLibre は同期）。
  - MapLibre 6 は既定で source の maxzoom より深いズームのタイルを切り分けるため（`zoomLevelsToOverscale`）、そこでは同じ地物の切り口と重複が MapLibre と違う。mbmap は source のタイルのまま描き、問い合わせる。
- `transformRequest`（オプションと `setTransformRequest`）：スタイル、TileJSON、GeoJSON の `data`、タイル、スプライト、image ソースの画像の要求の URL、ヘッダー、`credentials` を変えられる（MapLibre と同じ `(url, resourceType)`）。既定では資格情報を送らない。PMTiles の範囲リクエスト（ヘッダーもタイルも）は対象外。ソースと描けるレイヤーは「対応するスタイル」に。
- 地物の状態（feature-state）：`setFeatureState({ source, sourceLayer, id }, state)`、`getFeatureState`、`removeFeatureState(target, key?)`。
  - paint で `["feature-state", key]`（`boolean`・`number`・`string` で型をそろえる）を読むと、その地物だけその状態で描く。fill、line、circle、heatmap、fill-extrusion の色と不透明度、線の太さ、円の大きさに効く。
  - 地物の id は、タイルの id、GeoJSON の `id`、または source の `promoteId` が指すプロパティ。同じ id の地物はまとめて同じ状態になる。
  - ワーカーが地物の位置を持ち、状態のある地物の分だけを問い合わせるので、変更は 1 往復遅れて描かれる。フィルターや layout では使えない（MapLibre と同じ）。
- グローバルな状態（global state、MapLibre と同じ）：`setGlobalStateProperty(name, value)`、`getGlobalState()`、`new Map` の `globalState`（スタイルの `state` の既定値より優先）。`["global-state", name]` を読むレイヤーは描き直され、フィルタやレイアウトで読むレイヤーはタイルを読み直す。`null` を渡すとスタイルの既定値に戻る。
- マウスイベント：`mousedown`、`mouseup`、`mouseover`、`mouseout`、`mousemove`、`click`（押してから 3px 未満の移動のとき）、`dblclick`、`contextmenu`。`point` と `lngLat` が入る。
  - `map.on("click", "レイヤー id", f)` のようにレイヤーを指定すると、その下の地物（`e.features`）があるときだけ呼ぶ。`mouseenter`・`mouseleave` はレイヤー指定でだけ使える。問い合わせを待ってから呼ぶので、DOM のイベントより少し遅れる。
- `loaded()`、`getContainer()`、`getCanvas()`、`getAttributions()`（いま表示する出典の一覧）、`evaluatePaint(layerId, properties)`（その属性の地物を、いまのズームでどう描くか。凡例が使う）、`remove()`。`getMinZoom(true)` は、緯度の制約と `maxBounds` で実際に下げられる最小ズームを返す（MapLibre と同じ）。

## UI のコントローラ `mbmap/ui`

見た目を持たないコントローラ（大きさは 1 つあたり 2KB 以下、全部入りで 10KB 以下）。DOM を作らず、状態（`c.state`）、操作（メソッド）、変化の購読（`c.subscribe(f)` が解除の関数を返す）、`c.destroy()` だけを持つ。見た目は作り手が自由に作る（素の DOM でも React でも）。React では `useSyncExternalStore(c.subscribe, () => c.state)` でそのまま読める。import したコントローラだけがバンドルに入る。

```js
import { createNavigation, createScale } from "mbmap/ui";
const nav = createNavigation(map);
nav.subscribe((s) => { zoomIn.disabled = !s.canZoomIn; needle.style.rotate = `${-s.bearing}deg`; });
zoomIn.onclick = () => nav.zoomIn();
```

MapLibre のコントロールと同じ計算をし、`npm run ui:golden` で MapLibre 6.16 と比べている。

- `createNavigation(map, { home })`：`{ zoom, bearing, pitch, canZoomIn, canZoomOut }`。操作は `zoomIn()`、`zoomOut()`、`resetNorth(pitch?)`（方位記号のクリック）、`home()`。
  - ズームの限界でボタンを無効にする判定は MapLibre と同じ。ただし制約で決まる最小ズームでは、MapLibre はズームの最後の 1 桁がずれてボタンが有効のままになる。mbmap は無効にする。
- `createGeolocation(map, { trackUserLocation, positionOptions, fitBoundsOptions, zoomToUserAccuracy })`：Geolocation API で現在地を得て、精度の範囲に地図を合わせる。
  - 状態は `status`（`off`、`waiting`、`active`、`background`、それぞれの `-error`、`unavailable`）、`position`、`accuracyRadius`（精度の円の半径。画面のピクセル）、`error`。
  - 操作は `trigger()`（MapLibre のボタンのクリックと同じ）。
  - 追跡中に地図を動かすと `background` になる（ズームだけなら追跡を続ける）。点と円は `map.track` で作り手が描く。
- `createFullscreen(map, { container })`：`{ active, pseudo }` と `toggle()`。Fullscreen API がないときは `pseudo` が true になり、作り手が全画面の見た目を作る。
- `createScale(map, { maxWidth, unit })`：`{ width, distance, unit, label }`。`unit` は `metric`、`imperial`、`nautical`。`setUnit()` で切り替えられる。`measureScale(map, maxWidth, unit)` はその場で一度だけ測る。
- `createLegend(map, { layers, title, label })`：レイヤーごとの見本（上のレイヤーから）。
  - 色が属性で決まるレイヤー（`match`、`step`、属性の `interpolate`、`==` だけの `case`）は区分ごとに分ける。区分ごとの色は、いまのズームでエンジンが評価したもの（MapLibre の評価と同じ。`npm run ui:golden`）。
  - 状態は `entries`。各要素は `id`、`type`、`title`、`visible`（いまのズームで表示されるか）、`kind`、`property`、`items`。`items` の各要素は `label`、`category`、`paint`。
  - 題名の既定は `metadata["mbmap:title"]`、なければレイヤーの id。
- `createLayerList(map, { groups, title })`：レイヤー（または `groups` でまとめたもの）の一覧。
  - 状態は `items`。各要素は `id`、`title`、`layers`、`visible`、`mixed`（一部だけ表示）、`inRange`（いまのズームで描かれるか）。
  - 操作は `setVisible(id, visible)`、`toggle(id)`。
- `createBasemaps(map, { basemaps, active, overlay })`：背景地図の切り替え。
  - `basemaps` の各要素は `{ id, title, style }`。`style` はスタイル、URL、または選んだときにスタイルを作る関数。
  - `select(id)` は `setStyle` で差し替え、重ねるレイヤー（既定は `metadata["mbmap:overlay"]` が true のもの）を、そのソースとデータごと残す。
- `createIdentify(map, { layers, radius, highlight, click })`：クリックした点の周り（既定 3px）の地物。
  - 状態は `point`、`lngLat`、`features`（上から）、`index`（選んでいるもの）、`loading`。
  - 操作は `identify(point)`、`select(i)`、`next()`、`previous()`、`clear()`。
  - 選んだ地物には feature-state（既定のキーは `selected`）を立てるので、paint で `["feature-state", "selected"]` を読めば強調できる。
- `createCoordinates(map, { systems, follow })`：マウスの位置（地図の外では中心）の座標を、複数の座標系の文字列で返す。
  - 座標系は `degrees()`、`degreesMinutesSeconds()`、`projected({ transform, crs })`、`utm(transform)`。`format(lngLat)` を持つオブジェクトなら自分で作ってもよい。
  - 投影座標系は `transform`（`mbmap/analysis` の `transform` など）を渡して使う。そのため `mbmap/ui` は座標系の変換を含まない。遅れて届いた古い結果は捨てる。
  - `formatDegrees`、`formatDms`、`utmZone` も単体で使える。
- `createMeasurement(map, { measure, step, id, color })`：地図をクリックして距離や面積を測る。
  - `measure` には `mbmap/geodesic` の `measure` を渡す。そのため `mbmap/ui` は測地線の計算を含まない。
  - 状態は `mode`（`"distance"`、`"area"`、測っていないときは null）、`positions`、`pointer`（マウスについてくる仮の頂点）、`length`（m。面積では周囲）、`area`（m²）、`segments`（辺ごとの長さ）、`finished`。
  - 操作は `start(mode)`、`add(position)`、`undo()`、`finish()`（ダブルクリックでも終わる）、`clear()`。測っている間は、ダブルクリックでのズームを止める。
  - 線と面は、測地線に沿って `step`（既定 1000m）ごとに点を足して描く。描くのは自前の GeoJSON ソース（既定の id は `mbmap-measure`）とレイヤーで、`mbmap:overlay` の印があるので背景地図を替えても残る。
  - `formatLength`、`formatArea` は長さと面積を文字列にする。
- `createProfile({ measure, elevation, samples })`：線の断面図（地図は取らない。線はページが渡す）。
  - `measure` は `mbmap/geodesic` の `measure`、`elevation` は位置の配列から標高を返す関数（`mbmap/analysis` の `sampleDem` など）。そのため `mbmap/ui` は計算を含まない。
  - 状態は `positions`、`path`（測地線に沿って約 `samples` 個、既定 200）、`distances`、`elevations`、`length`、`min`、`max`、`gain`（登りの合計）、`loss`、`active`（指している点）、`loading`、`error`。
  - 操作は `setLine(positions)`、`highlight(distance)`（グラフの上のポインタなど。null で外す）、`clear()`。グラフと地図の上の印は作り手が描く。
- `createAttributeTable(map, { source, sourceLayer, columns, searchColumns, filter, pageSize, locale, highlight, fitBoundsOptions })`：1 つのソースの地物の属性テーブル。
  - 行は、GeoJSON ソースならデータ全部（`getSource(id).getData()`）、ベクタタイルのソースなら描いているタイルの地物（`querySourceFeatures`。`sourceLayer` が要る。id（`promoteId`）が同じものは 1 行にまとめ、ジオメトリはタイルごとの部分の GeometryCollection になる）。ソースの `sourcedata` で読み直し（ベクタタイルのソースは `idle` でも）、同じタスクの中の変更は 1 回にまとめる。
  - 列は `columns`（既定は属性のキーを最初に現れた順に）。
  - 状態は `columns`、`rows`（いまのページの行。各要素は `id`、`properties`、`geometry`）、`total`（全部の行の数）、`filtered`（絞り込んだあとの数）、`page`（0 から）、`pages`、`pageSize`（既定 50）、`sort`（`{ column, direction }` か null）、`query`、`selected`（選んでいる id。文字列）、`loading`、`error`。
  - 操作は `setSort(column, direction?)`（向きを省くと昇順、同じ列ならその逆。null で元の順）、`setQuery(text)`、`setFilter(row => boolean)`、`setPageSize(n)`、`goTo(page)`・`next()`・`previous()`（範囲に収める）、`select(id, { add })`（`add` で選択に足す。選んでいれば外す）、`clear()`、`zoomTo(id, options)`（地物の範囲に `fitBounds`。既定は padding 40、maxZoom 17）、`refresh()`。
  - 並べ替えは `Intl.Collator`（`locale`、数字は数として）で、数、文字列、値のないもの（null、undefined。向きによらず最後）の順。同じ値は元の順のまま。
  - 絞り込みは `searchColumns`（既定は列）の値に `query` を含む行（`mbmap/search` と同じく全角半角、大文字小文字、カタカナとひらがなを区別しない）で、`filter` も満たすもの。
  - 選んだ地物には feature-state（既定のキーは `selected`）を立てる。`cellText(value)` はセルの文字列（null は空、オブジェクトは JSON）。
- `createAttribution(map, { customAttribution })`：`{ items, text }`。地図自身の表示を消す（`attributionControl: false`、`<mb-map attribution-control="false">`）と、出典を自分で表示できる。

## 検索 `mbmap/search`

見た目を持たない検索のコントローラ（GeoSearch）。形は `mbmap/ui` と同じ（`state`、`subscribe`、操作、`destroy`）。付いているプロバイダは、サーバーに問い合わせない。

```js
import { transform } from "mbmap/analysis";
import { coordinates, createSearch, datasetSearch } from "mbmap/search";
const search = createSearch(map, { providers: [coordinates({ transform }), datasetSearch(shops, { fields: ["name"] })] });
search.subscribe((s) => render(s.query, s.results, s.active));
input.oninput = (e) => search.setQuery(e.target.value);   // 入力の間引きと、古い検索の取り消しはコントローラが行う
list.onclick = (e) => search.select(Number(e.target.dataset.i)); // 選ぶと、その場所へ地図を動かす
```

- `createSearch(map, { providers, debounce, limit, zoom, maxZoom })`：
  - 状態は `query`、`results`（プロバイダの順）、`active`（矢印キーで選んでいるもの。`aria-activedescendant` に使う）、`open`、`loading`、`errors`（失敗したプロバイダ。ほかの結果は出る）、`selected`。
  - 操作は `setQuery(q)`（既定 250ms 待ってから検索し、前の検索は `AbortSignal` で取り消す）、`submit()`（すぐ検索）、`move(±1)`、`select(i?)`（点なら `flyTo`、範囲なら `fitBounds`）、`close()`、`clear()`、`reverse(lngLat)`。
- キー操作は作り手が書く。日本語入力の変換を確定する Enter（`isComposing` が true、または Safari で確定直後に来る `keyCode` 229）は、検索の決定に使わないこと。example の `onSearchKey` が書き方の例。
- `coordinates({ transform })`：入力された座標を読む。
  - 読める形：10 進の度（緯度経度のどちらの順でも）、度分秒（`35°40′52″N`、`35度40分52秒`、`'` と `"`）、全角の数字。
  - `transform`（`mbmap/analysis` の `transform` など）を渡すと、平面直角座標系（`第IX系 X -35367.2 Y -5995.2`、`9系`。JGD2011）と UTM（`54N 388708 3949480`）も読む。
- `datasetSearch(data, { fields, label })`：GeoJSON（または今のデータを返す関数）の属性を探す。全角と半角、大文字と小文字、カタカナとひらがなを同じとみなす。一致、前方一致、部分一致の順に並べる。
- 外部の検索 API は、`{ name, search(query, { signal, bbox, limit }), reverse?(lngLat) }` の形のプロバイダとして足す。利用条件と出典の表示は、作り手の責任になる。
  - example の `gsiPlaceSearch`（国土地理院の地名検索、`?gsi-search=1` で有効）は、書き方の例として置いている。この API には公開の利用規約がなく、国土地理院は「主に地理院地図からの利用を想定しており、予告なく変更することがある」と答えている。

## 解析 `mbmap/analysis`

```js
import { load } from "mbmap/analysis";

const blocks = await load(polygonsGeoJSON);  // オブジェクト、UTF-8 のバイト列、http(s) の URL、mbmap/data の DataTable
const shops = await load("/data/shops.geojson");
const area = await blocks.areas();           // Float64Array（m²）
const { count, mean } = await blocks.collect(shops, "sales");
blocks.dispose();
```

- 初めての `load` で、専用の Worker と wasm を読み込む。データと空間索引は Worker の中に置いたままにし、各メソッドは結果だけを型付き配列で返す（Promise）。
- `Dataset`：`length`（地物数）、`areas()`、`lengths()`（m）、`centroids()`、`bboxes()`、`search(bbox)`、`nearest(x, y, { k, maxDistance })`、`pointsWithin(polygons)`、`collect(points, property)`、`grid(bbox, cols, rows)`、`dispose()`。
- 計測と点の内外判定は Turf.js 7.4.0 と同じ値になり、索引の検索は flatbush 4.6.2 と同じ順になる（黄金テストで確かめている）。境界上の点は内側として扱う。`nearest` の距離は経緯度の箱の距離（度）。
- ジオメトリ演算（Clipper2 2.0.1 の移植。C++ 版と同じ結果になることを黄金テストで確かめている。初めて呼んだときに `geometry.wasm` を読む）。どれも結果を新しい `Dataset` で返す：
  - `buffer(meters, { mode, join, cap, arcTolerance, crs })`：地物ごとに広げる（負の値で縮める。属性は残る）。`mode: "geodesic"`（既定）は地面の上の距離（地物ごとの局所的な正距方位図法で、楕円体の 2 つの曲率半径に合わせる）、`"planar"` は投影した平面上の距離（`crs`、既定はウェブメルカトル）。`join` は `round`・`miter`・`square`・`bevel`、`cap`（線の端）は `round`・`butt`・`square`。
  - `dissolve()`：多角形をすべて 1 つの地物に結合する（属性なし）。
  - `clip(other)` / `erase(other)`：`other` の多角形の範囲で切る／除く（自分の属性を残す）。線は線のまま、点は内外で選ぶ。
  - `intersect(other)`：重なる組ごとに 1 地物、両方の属性を持つ（`other` の同名のキーには `_2` を付ける）。
  - `split(lines)`：`lines` の線で地物を分ける。多角形は端から端まで横切ったところ、線は交わったところで分かれ、片は元の属性を持つ。`merge()`：全部の地物を 1 つにする（多角形は union、線は端点でつなぐ、点は MultiPoint。種類が混ざると失敗する）。
  - `splitFeatures(features, line)`、`mergeFeatures(features)`：GeoJSON の地物のまま同じことをする（`mbmap/draw` の `geometry` に渡す形）。
  - `toGeoJSON({ crs })`：FeatureCollection として取り出す（Worker の中で組み立てる）。`crs` を渡すとその座標系の座標で返す。
- 座標系：`load(data, { crs })` で投影座標のデータを読める（読み込むときに経緯度へ変換する）。`buffer` の `mode: "planar"` は `crs`（既定は 3857）の平面で測る。`transform(coords, from, to)` は `[x, y, x, y, …]` を別の座標系に変換して `Float64Array` で返す（投影の範囲外の点は NaN）。初めて座標系を使ったときに `proj.wasm` を読む。
  - `crs` に渡せるもの：EPSG コード（`6677`、`"EPSG:6677"`、`"urn:ogc:def:crs:EPSG::6677"`）、`"CRS84"`、PROJ 文字列（`"+proj=lcc +lat_0=46.5 …"`。epsg.io などにある形）、`defineCrs(name, projString)` で名前を付けたもの（`proj4.defs` と同じ使い方。`defineCrs("EPSG:2154", "+proj=lcc …")`）。
  - PROJ 文字列なしで使える EPSG コード：経緯度 4326（WGS84）・4612（JGD2000）・6668（JGD2011）・4301（日本測地系）、Web メルカトル 3857（3785、900913）、平面直角座標系 I〜XIX 系 6669〜6687（JGD2011）・2443〜2461（JGD2000）・30161〜30179（日本測地系）、UTM 32601〜32660・32701〜32760（WGS84）・6688〜6692（JGD2011、51〜55 帯）・3097〜3101（JGD2000）・3092〜3096（日本測地系）。
  - 投影：`longlat`、`merc`、`tmerc`（`etmerc`）、`utm`、`lcc`、`aea`、`aeqd`、`stere`、`sterea`、`cass`、`laea`、`eqc`、`eqdc`、`sinu`、`eck6`、`moll`、`robin`、`cea`、`mill`、`poly`、`omerc`、`somerc`、`krovak`、`ortho`、`gnom`、`eqearth`、`bonne`。
  - 測地系の変換は `+towgs84`（3 または 7 パラメータ）と `+datum`（`WGS84`、`NAD83`、`potsdam`、`OSGB36`、`ch1903` など proj4js と同じ名前）で、WGS84 を経由して行う。日本測地系は EPSG の 3 パラメータ（-146.414, 507.337, 680.507）。グリッドによる変換（`+nadgrids`、TKY2JGD など）は使えない。JGD2000・JGD2011 と WGS84 は同じものとして扱う。
  - 値は proj4js 2.22.0 と 1mm 未満で一致する（240 の座標系で黄金テストをしている）。proj4js が明らかに誤っているところ（`+R_A` の半径、正弦図法などの偽原点）は PROJ に合わせた。
- `loadDem(tiles, { zoom, bounds, encoding })`：標高タイル（`{z}/{x}/{y}` の http(s) URL）のうち `bounds` を覆うものを並べて、1つの標高の格子（`DemGrid`）にする。`DemGrid` は `width`、`height`、`bounds`（タイルの境界に合わせた範囲）、`elevations()`、`slope()`（度）、`aspect()`（北から時計回りの度。平らなところは NaN）、`hillshade({ azimuth, altitude, zFactor })`（1〜255）、`dispose()`。勾配・斜面方位・陰影起伏は GDAL の gdaldem（Horn の方法）と同じ式で、黄金テストで比べている。
- `DemGrid.sample(positions)`：`[lng, lat]` ごとの標高（m）。セルの中心の間を双一次で補間する（GDAL の `-r bilinear` と同じ。黄金テストで 1e-8 m の桁まで一致）。格子の外と、データのないセルの隣は NaN。
- `loadGrid(raster, { band, scale })`：`mbmap/data` の `readRaster` で読んだ GeoTIFF の帯（既定は 0）を `DemGrid` にする。`noData` のセルは値なし。セルの大きさは解像度を `scale`（gdaldem の `-s`。経緯度の度とメートルなら 111120）で割ったもの。GeoKeys が PixelIsPoint なら、GDAL と同じく画素の中心がタイポイントに来る。`sample` は経緯度を受け取り、GeoTIFF の座標系へは `proj.wasm` で変える。一辺 4096 セルまで。
- `sampleDem(tiles, positions, { encoding, maxZoom, tileSize })`：`positions` を覆う標高タイルを、1 つの格子に収まるいちばん深いズーム（既定で 14 まで、24 が上限）で読み、標高を返す。`tileSize` は 256〜4096。サーバーにないタイル（404）は、`loadDem` と同じく 0 m として扱う。1 つの格子に入りきらないほどのタイル（一辺 16 枚を超えるもの）は、取得する前に断る。
- `distance(from, to)`：2点間の大圏距離（m）。Worker を使わずに同期で計算する。
- `terminate()`：Worker を止める。読み込んだデータは失われる。

## 作図 `mbmap/draw`

```js
import { createDraw } from "mbmap/draw";
import * as geodesic from "mbmap/geodesic";

const draw = createDraw(map, { geodesic });   // 円を描くときだけ geodesic が要る
draw.setMode("polygon");                       // point、linestring、polygon、rectangle、circle、freehand、select、split、null
draw.subscribe((s) => render(s.mode, s.features, s.canUndo, s.canRedo));
```

- クリックの仕方は terra-draw 1.37 に合わせた（`npm run draw:golden` で、同じクリックの結果を比べている）。
  - 点：クリック。
  - 線：クリックで頂点を置き、最後の頂点をもう一度クリック（40px 以内）で終わる。
  - 多角形：最初か最後の頂点をクリックで閉じる。
  - 矩形・円：2 回のクリック。円は楕円体の上の円（64 点）。
  - フリーハンド：クリックで始め、動かすと 20px ごとに頂点を足し、クリックで閉じる。
- 編集（`setMode("select")`）：
  - 形をクリックで選ぶ。
  - 選んだ形の頂点をドラッグで動かし、中点をドラッグで頂点を足し、頂点を右クリックで消す（線は 2 つ、多角形は 3 つより減らさない）。形の中（線と点は近く）をドラッグで全体を動かす。
  - ドラッグの間は地図のパンを止める。1 回のドラッグが 1 段の取り消しになる。
- スナップ（`snapping: true`、または `{ vertices, lines, pixels }`）：描くときと頂点を動かすときに、ほかの形の頂点（なければ辺）へ、40px 以内（terra-draw と同じ）で吸い付く。
- 分割と結合（`geometry: { split: splitFeatures, merge: mergeFeatures }`、どちらも `mbmap/analysis` の関数）：
  - `setMode("split")` で線を引くと、選んでいる形を（なければ、その線が横切る形を）分ける。多角形は端から端まで横切ったところで分かれ、線は交わったところで分かれる。片は元の属性を持つ。
  - Shift+クリックで選ぶ形を増やし、`merge()` で 1 つにする。多角形は union、線は端点でつなぎ、点は MultiPoint にする。属性は最初の形のもの。
  - 計算はジオメトリのモジュール（Clipper2 の移植）が 1e-7°（約 1cm）の格子で行う。1 回の分割・結合が 1 段の取り消しになる。結合でできた Multi の形は、選べるが頂点は編集できない。
- 属性：`setProperties(id, { name: "区画A" })` で足す・変える（null でそのキーを消す。`mode` は変えない）。取り消せる。
- 状態は `mode`、`selection`、`selected`、`features`（描いた地物。`id` と `properties.mode` を持つ GeoJSON）、`drawing`（描いている途中の形）、`vertices`、`canUndo`、`canRedo`。
- 操作は `setMode(mode)`、`select(id, add)`、`setProperties(id, properties)`、`deleteSelected()`、`merge()`、`finish()`、`cancel()`、`undo()`（描いている途中なら最後の頂点を消す）、`redo()`、`add(features)`、`remove(id)`、`clear()`。キー（Enter で確定、Escape で取り消しなど）は作り手が割り当てる。日本語入力の変換中のキーは渡さないこと。
- 座標は小数 9 桁（約 0.1mm）に丸め、多角形の外周は反時計回り、穴は時計回りにする（RFC 7946）。
- 描くのは自前の GeoJSON ソース（`id` で名前の頭を変えられる。既定は `mbmap-draw`）とレイヤーで、`setData` で更新する。色は `color`（既定 `#3b6ed6`）、円の点の数は `steps`（既定 64）、座標の桁は `precision`（既定 9）。描いている間はダブルクリックのズームを止める。

## 楕円体の上の計測 `mbmap/geodesic`

```js
import { inverse, direct, measure } from "mbmap/geodesic";

const { distance, azimuth1 } = await inverse([139.7671, 35.6812], [135.4959, 34.7025]); // m、北から時計回りの度
const { position } = await direct([139.7671, 35.6812], 90, 10_000);                     // 東へ 10 km の点
const { length, area, path } = await measure(ring, { closed: true, step: 1000 });       // 周囲（m）、面積（m²）、描くための点列
```

- WGS84 の楕円体の上で計算する。GeographicLib（geographiclib-geodesic 2.2.0）の移植で、同じ JavaScript エンジンの上ではビット単位で同じ値になる（黄金テストで確かめている）。
- `circle(center, radius, { steps })`：中心から `radius` m の円（既定 64 点、閉じた輪）。
- `inverse(from, to)`：`distance`、`azimuth1`、`azimuth2`、`arc`、`area`（測地線と赤道の間の面積）。
- `direct(from, azimuth, distance)`：`position`、`azimuth`、`arc`。
- `measure(positions, { closed, step })`：線の長さ、または閉じた多角形の周囲と面積（反時計回りが正）、各頂点までの距離（`distances`）。`step` を渡すと、測地線に沿って `step` m ごとに点を足した `path` も返す（経度は ±180 を越えても続けて数える）。
- 初めて呼んだときに、専用の Worker と wasm（約 12KB）を読み込む。`terminate()` で止める。

## データの読み込み `mbmap/data`

```js
import { read, parse } from "mbmap/data";
import { load } from "mbmap/analysis";

const stations = await read("/data/stations.csv");   // 緯度・経度の列から点を作る
map.addSource("stations", { type: "geojson", data: stations.toGeoJSON() });
const dataset = await load(stations);                 // mbmap/analysis の Dataset にもなる
const area = await parse("SRID=4326;POLYGON ((139.76 35.67, 139.775 35.67, 139.775 35.688, 139.76 35.688, 139.76 35.67))", { format: "wkt" });
const wards = await read("/data/wards.zip");          // zip の中の Shapefile。.prj の座標系から経緯度にする
const picked = await read(input.files);               // <input type="file" multiple> で選んだ .shp・.dbf・.prj・.cpg
const world = await read("/data/world.json", { format: "topojson", layer: "countries" });
const drawing = await read(file);                     // 地理院地図の作図など、KML・KMZ・GPX の File も
const near = await read("https://example.com/buildings.fgb", { bbox: [139.76, 35.67, 139.78, 35.69] }); // 索引で範囲の地物だけを範囲リクエストで読む

import { write } from "mbmap/data";
const csv = await write(stations, { format: "csv" });            // DataTable を CSV（点は経度・緯度の列）に
const kml = await write(drawnFeatures, { format: "kml" });       // GeoJSON の地物（作図したものなど）を KML に

import { readRaster } from "mbmap/data";
import { loadGrid } from "mbmap/analysis";
const dem = await readRaster("https://example.com/dem-cog.tif", { bbox: [138.7, 35.3, 138.8, 35.4] }); // COG の範囲だけ
const grid = await loadGrid(dem, { scale: 111120 });  // 経緯度の DEM の傾斜・陰影
```

- `read(input, options)`：`input` は http(s) の URL（文字列か `URL`。ページを基準に解決し、資格情報なしで取得する）、`Blob`・`File`、`ArrayBuffer`・型付き配列（コピーする）、Shapefile の部品（`FileList` か `File` の配列。拡張子で見分ける。または `{ shp, dbf, prj, cpg }` で、それぞれ URL・Blob・バイト列）。文字列はいつも URL として扱う。文字列のデータは `parse(text, { format })` に渡す。
- `options.format`：`"csv"`・`"wkt"`・`"wkb"`・`"shapefile"`・`"topojson"`・`"kml"`（KMZ も）・`"gpx"`・`"flatgeobuf"`・`"geojson"`。省くと URL か `File` の名前の拡張子（`.csv`・`.tsv`・`.txt`・`.wkt`・`.wkb`・`.ewkb`・`.shp`・`.zip`・`.topojson`・`.kml`・`.kmz`・`.gpx`・`.fgb`・`.geojson`）で決める。`.json` の TopoJSON は `format` で指定する。決められないときは失敗する。`transformRequest(url)` で URL の取得に `headers` や `credentials` を付けられる（地図の `transformRequest` と同じ形）。
- 結果の `DataTable`：`length`（行の数。GEOMETRYCOLLECTION は要素ごとに 1 行）、`columns`（属性の名前）、`format`、`layer` と `layers`（読んだ層と、入力にあるすべての層。zip の中の Shapefile、TopoJSON の object。層のない形式では null と空）、`toGeoJSON()`（FeatureCollection。GeoJSON ソースの `data` にそのまま渡せる。TopoJSON の `id`、KML の `Placemark` の `id`、FlatGeobuf の地物の番号（ファイルの中の 0 からの順番）は地物の `id` になる。呼ぶたびに新しく作る）、`tableBytes()`（`mbmap/analysis` の `load` が受け取る形。`id` は持たない）。
- 座標系：行はいつも経緯度（EPSG:4326）にして返す。
  - EWKT・EWKB・CSV のジオメトリの欄の SRID は、行ごとに読み、4326 でなければ経緯度にする（1 つの入力に違う SRID が混ざってもよい）。`proj.wasm` が知る EPSG コード（解析の節の「PROJ 文字列なしで使える EPSG コード」）でない SRID は失敗する。1 つのジオメトリの中で違う SRID（EWKB の入れ子）は失敗する。
  - Shapefile は `.prj`（Esri か OGC の WKT1。wkt-parser と同じく読む。ルートの `AUTHORITY["EPSG", …]` は、`proj.wasm` が知るコードならそれを使う）。WKT2 は失敗する。軸の順は読まない（Shapefile の x は東向き）。
  - `crs`：データが座標系を示さない座標の座標系（`mbmap/analysis` と同じ書き方：EPSG コード、`"EPSG:6677"`、PROJ 文字列）。SRID のない行と、Shapefile（`.prj` の代わりに使う。`.prj` は読まない）に効く。既定は EPSG:4326。KML、GPX、GeoJSON はいつも EPSG:4326 なので、`crs` を渡すと失敗する。
  - FlatGeobuf はヘッダーの `crs`（`org` が EPSG か無しの `code`、なければ `wkt` を `.prj` と同じく読む）。`crs` オプションがあればそちらを使う。
  - 4326 以外を初めて扱うときに `proj.wasm`（約 22KB）と `data-crs.js` を、初めて `.prj` を読むときに `prjwkt.js`（約 4KB）を読み込む。
- Shapefile：`.shp` の点・マルチポイント・ライン・ポリゴンと、その Z・M（2 次元だけ残す）。Null の図形はジオメトリなしの行、マルチポイントの点が 1 つなら Point、ラインの部分が 1 つなら LineString。MultiPatch は失敗する。`.shx` は使わない（`.shp` を先頭から読む）。
  - ポリゴンの輪は向き（時計回りが外周）で分け、穴は内外判定でそれを含むいちばん小さい外周に入れる。外周は反時計回り、穴は時計回りにして返す（RFC 7946）。どの外周にも入らない穴があれば、逆の向きで読み直し（shpjs と同じ）、それでも残る穴は外周として扱う。
  - `.dbf`：C（前後の空白を除く）、N と F（数。空や読めない値は null）、L（`TtYy` は true、`FfNn` は false、ほかは null）、D（`YYYYMMDD` を `"YYYY-MM-DD"` の文字列に。Date にはしない）。M（メモ）とほかの型の欄は読まない。削除の印のあるレコードは、図形ごと行にしない。`.dbf` のレコードがない図形は属性を持たない。
  - 文字コード：`encoding`（`"shift_jis"` などのラベルかコードページ）、`.cpg`（`UTF-8`、`SJIS`、`Shift_JIS`、`CP932`、`ANSI 932`、`932` など）、`.dbf` の言語ドライバ（0x13 と 0x7B は Shift_JIS など）の順に決め、なければ UTF-8。ブラウザの `TextDecoder` で読む。
  - zip：中央ディレクトリから読む（格納と deflate。ZIP64、分割、暗号、ほかの圧縮方式は失敗する）。`__MACOSX` を除く `.shp` が層で、既定は最初のもの、`layer` でフォルダ付きか無しの名前（`.shp` を除く）を選ぶ。名前は UTF-8 の印か UTF-8 として正しければ UTF-8、ほかは Shift_JIS として読む。項目は 1 万まで、展開は合わせて 256MB まで（書かれた大きさを超えて展開されるものは失敗する）。
  - `.shp` の URL を読むと、同じ場所の `.dbf`・`.prj`・`.cpg` も取得する（404 は無いものとする）。
- TopoJSON：topojson-client の `feature` と同じ地物にする。`transform` のある（量子化した）arcs の差分、`~i`（逆向き）の arc、arc のつなぎ目（前の arc の最後の点を次の最初の点で置き換える）、点が少ない線と輪の補い。Point・MultiPoint は `transform` だけで差分にしない。GeometryCollection の object は要素ごとの地物に、要素の中の GeometryCollection は要素ごとの行にする。`id` と `properties`（入れ子の値は JSON の文字列）。`layer` で object を選び、既定は最初のもの。
- CSV（RFC 4180）：引用符（`""` で引用符そのもの、引用の中の改行）、CRLF・LF・CR の行末、先頭の BOM、空行の読み飛ばし。オプション：
  - `delimiter`：1 文字。省くと papaparse と同じやり方で `,`・タブ・`|`・`;` から推測する。
  - `header`（既定 true）：1 行目を列の名前にする。同じ名前は papaparse と同じく `_1`、`_2` を付けて区別する。false なら列は `"0"`、`"1"`、… という名前になる。
  - `dynamicTyping`（既定 true）：papaparse の `dynamicTyping` と同じく、数（`007` は 7、`1e3` は 1000、±2^53 以上と `NaN`・`+1`・`0x10` は文字列のまま）、`true`/`TRUE`/`false`/`FALSE`、空の欄（null）に型を付ける。ISO の日時は（papaparse の Date と違い）文字列のまま。false ならすべて文字列。
  - ジオメトリ：`latitude` と `longitude`、または `geometry`（WKT・EWKT・16 進の WKB の列）で列を指定する。省くと名前で探す：`wkt`・`geometry`・`the_geom`・`geom`（最初の値がジオメトリとして読めるとき）、なければ `lat`・`latitude`・`y`・`緯度` と `lon`・`lng`・`long`・`longitude`・`x`・`経度`（大文字と小文字は区別しない）。座標が数として読めない行も、属性を持ったままジオメトリなしの行になる。ジオメトリの列は属性に入れない（緯度・経度の列は残す）。投影座標の `x`・`y` の列は `crs` で経緯度にできる。
  - ヘッダーより多い欄は捨て、足りない欄は属性を持たない。
- WKT・EWKT：すべての型（GEOMETRYCOLLECTION は要素ごとの行に分ける。入れ子も）、`EMPTY`（ジオメトリなしの行）、Z・M・ZM（2 次元だけ残す。タグのない 3・4 次元の座標も読む）、`MULTIPOINT (1 2, 3 4)` と `MULTIPOINT ((1 2), (3 4))`。空白で区切って複数のジオメトリを続けて書ける（1 行に 1 つなど）。
- WKB・EWKB：バイト列か 16 進の文字列（PostGIS の出力の形。空白は無視）。ジオメトリごと（入れ子も）のバイト順、ISO の Z/M/ZM の型コード（+1000/2000/3000）と EWKB のフラグ。NaN の点は空として扱う。続けて置いた複数のジオメトリを読む。
- KML・KMZ：@tmcw/togeojson 7.1.3 の `kml()` と同じ地物と属性（XML は @xmldom/xmldom 0.9.12 と同じく読み、壊れた文書は同じところで失敗する）。
  - `Placemark`（Point、LineString、LinearRing、Polygon、MultiGeometry、`gx:Track`・`gx:MultiTrack`）、`GroundOverlay`（`LatLonBox` の回転と `gx:LatLonQuad` の多角形、`@geometry-type` は `"groundoverlay"`）の順。MultiGeometry は（togeojson の GeometryCollection と違い）要素ごとの行に分ける。`NetworkLink`（ほかの文書へのリンク）は読まない。
  - 属性：`name`、`description`（CDATA なら togeojson と同じ `{"@type":"html","value":…}`）、`visibility`（真偽値）、`address`、`phoneNumber`、`open`、`styleUrl` と、それが指す `Style`・`StyleMap` と地物の中の `Style` から togeojson と同じ simplestyle 風の値（`stroke`、`stroke-opacity`、`stroke-width`、`fill`、`fill-opacity`、`icon`、`icon-scale`、`icon-color`、`icon-offset`、`label-scale`、…。KML の aabbggrr の色は `#rrggbb` と不透明度に）、`ExtendedData`（`Data/value`、`Schema` で型を付ける `SimpleData`）、`timestamp`、`timespan`、トラックの時刻（`coordinateProperties.times`）。
  - 入れ子の値（オブジェクトと配列：`timespan`、`coordinateProperties`、`icon-offset` など）は JSON の文字列。高さ（z）は捨てる。座標に有限でない値を持つ要素は読まない。
  - KMZ（zip）は、最上位の `doc.kml`、なければ最初の `.kml` を読む（zip の読み方は Shapefile の zip と同じ。展開は 256MB まで）。
- GPX：togeojson の `gpx()` と同じ。`trk`（区間が 2 つ以上なら MultiLineString）、`rte`、`wpt` の順。`_gpxType`、`name`・`cmt`・`desc`・`type`・`time`・`keywords`・`sym`、`links`、名前空間付きの要素（`gpxx_…` など）、`extensions` の線の色・不透明度・太さ、点ごとの時刻と拡張の値（心拍 `heart`、`cads` など。`coordinateProperties`）。標高は捨てる。
- FlatGeobuf：flatgeobuf 4.6.1 の `deserialize` と同じ地物にする。すべての図形の型（ヘッダーの型が Unknown なら地物ごとの型）、GeometryCollection は要素ごとの行、Z・M は捨てる。属性の型は 15 種すべて：整数・浮動小数点は数（Long と ULong は Number に丸める）、Bool、String と DateTime は文字列、Json は（JSON.parse せず）JSON の文字列、Binary は base64 の文字列。曲線の型（CircularString など）は失敗する。ジオメトリのない地物は（flatgeobuf と違い）ジオメトリなしの行。
  - `bbox`（`[minX, minY, maxX, maxY]`、ファイルの座標系で）：パックされた R-tree の索引で、箱が重なる地物だけを読む。URL なら flatgeobuf の HttpReader と同じく範囲リクエストで、ヘッダーと索引の上の段、索引の段、256KB より近い地物はまとめて 1 回で読む（同時に 6 つまで）。範囲リクエストに答えずファイル全体を返すサーバーなら、それを読む。索引のないファイルに `bbox` を渡すと失敗する。FlatGeobuf を初めて読むときに `data-fgb.js`（約 2KB）を読む。
- GeoJSON：GeoJSON ソースと同じ読み手（geojson-vt と同じく GeometryCollection は要素ごとの行、地物の `id` も読む）。
- 書き出し `write(input, options)`：`input` は `DataTable` か GeoJSON の Feature・FeatureCollection（オブジェクト。GeoJSON として読んでから書く）。`options.format` は `"geojson"`・`"csv"`・`"kml"`。文字列を返す（ファイルにするなら `new Blob([text])`）。
  - GeoJSON：`JSON.stringify(table.toGeoJSON())` と同じ（GeoJSON のオブジェクトなら `JSON.stringify` そのもの）。
  - CSV：papaparse 5.7.0 の `unparse` と同じ（区切り `delimiter`、既定は `,`。行末は CRLF。引用符・区切り・改行・BOM を含む値と前後に空白のある値は引用符で囲む。`header`：既定 true）。列は属性の列、そのあとにジオメトリの列。`geometryFormat`：`"lonlat"`（点の経度・緯度の列、名前は `longitude`・`latitude` で変えられる）、`"wkt"`（betterknown 1.2.0 の `geoJSONToWkt` と同じ WKT の列、名前は `geometry` で変えられる。既定 `wkt`）、`"none"`。省くと、ジオメトリがなければ `"none"`、すべて点なら `"lonlat"`、ほかは `"wkt"`。同じ名前の属性の列があれば、その場所にジオメトリを書く。点でない行に `"lonlat"` は失敗する。数は JavaScript の `String(x)` と同じに書く。
  - KML：@placemarkio/tokml 0.4.0 の `toKML` と同じ（地物ごとの Placemark、`id`、属性の `name`・`description`・`visibility` は要素、ほかは `ExtendedData`、Multi の図形は `MultiGeometry`）。書き出しは KML を読む `xml.wasm` が受け持つ。
  - どれも `npm run write:golden` で参照の実装とバイト単位で一致することを確かめている。
- 値は papaparse 5.7.0（`header`、`dynamicTyping`、`skipEmptyLines`）、betterknown 1.2.0（WKT）、wkx 0.5.0（WKB）、shpjs 6.2.0（Shapefile。`.prj` の変換も）、topojson-client 3.1.0（TopoJSON）と一致し、ほかの座標系からの経緯度は proj4 2.22.0 と 1e-8° 以内で一致することを黄金テストで確かめている（`npm run data:golden`）。KML と GPX は @tmcw/togeojson 7.1.3 ＋ @xmldom/xmldom 0.9.12 と一致する（`npm run xml:golden`）。FlatGeobuf は flatgeobuf 4.6.1 と、バイト列からも HTTP の範囲リクエストでも一致する（`npm run fgb:golden`）。違うのは、参照の実装が緩く受け付けるもの（WKT の後ろの余分な文字列、`1a` のような数、型の違う Multi の要素、0 と 1 以外のバイト順、途中で切れた `.shp`、Topology でない TopoJSON）を失敗にするところ、タグのない Z 座標を読むところ、Shapefile の 4 つ（輪の向き、内外判定での穴の割り当て、削除されたレコード、日付を文字列に）と、論理値の `?` を null にするところ。
- 入力は 256MB、点は 2000 万、CSV の欄は 1 行に 4096、1 つの欄は 16MB、属性の欄の数（行 × 列。CSV、`.dbf`、TopoJSON、FlatGeobuf）は 3200 万まで。XML は入れ子 256 段、1 つの要素の属性 1024、ノード 400 万まで。KML と GPX の地物の属性と GPX の 1 トラックの拡張の名前は 4096、表の欄（行 × 列。GPX の拡張は名前 × 点も数える）は 3200 万、点は 2000 万まで。宣言した実体（`<!ENTITY>`）は xmldom と同じく展開しない。FlatGeobuf のヘッダーは 10MB まで（flatgeobuf と同じ）、列は 4096 まで、`bbox` で読むバイトは合わせて 256MB まで。同じデータをオフセットで何度も指す FlatGeobuf は断る。`.prj` の WKT は 65536 文字、1 つのノードの項目は 1024 まで。GeoTIFF は 1 サンプル 64 ビット、1 ブロック 256MB、1 ファイルのタグの値は合わせて 6400 万まで、タイルは画像より 4096 ピクセル大きいところまで、1 回の読み取りで展開するブロックは合わせて 2GB まで。URL からの取得は 1 回につき 5 分で打ち切る。
- GeoTIFF・COG `readRaster(input, options)`：`input` は http(s) の URL（範囲リクエストで、窓に重なるブロックだけを読む。近いブロックはまとめて 1 回で）、`Blob`（必要なところだけ切り出して読む）、バイト列。geotiff 3.0.5 の `readRasters` と同じ値を返す。
  - `options`：`window`（読む画像の画素 `[x0, y0, x1, y1]`、終わりは含まない。画像の外は `fillValue`、既定 0）か `bbox`（ファイルの座標系）、`width`・`height`・`resX`・`resY`（いちばん粗くて足りる概観図を選び、その大きさにリサンプリング。`resampleMethod` は `"nearest"` か `"bilinear"`）、`image`（画像を番号で選ぶ）、`samples`（帯の番号）。
  - 結果：`width`、`height`、`bands`（帯ごとの Uint8Array・Int8Array・Uint16Array・Int16Array・Uint32Array・Int32Array・Float32Array・Float64Array）、`bbox`・`resolution`（ジオタグがなければ null）、`crs`（GeoKeys の EPSG コード、なければ null）、`noData`（GDAL_NODATA）、`window`、`image`、`images`、`pixelIsPoint`。
  - 読めるもの：TIFF と BigTIFF（どちらのバイト順も）、ストリップとタイル、planar 1・2、非圧縮・LZW・Deflate・PackBits・JPEG・WebP（JPEG と WebP はブラウザで復号）、予測子 2・3、符号なし 1〜16 と 32 ビット、符号付き 8・16・32 ビット、浮動小数点 16・32・64 ビット、バイト数 0 のブロック（no data か 0）。LERC と ZSTD は失敗する。
  - geotiff と違うところ：ビッグエンディアンで予測子のあるファイルを仕様どおりに読む（geotiff はリトルエンディアンとして戻す）、`width` だけを渡すと窓の高さのまま幅だけリサンプリングする（geotiff は空の帯を返す）、途中で切れたファイルは失敗する。値は `npm run geotiff:golden` で、バイト列からも HTTP の範囲リクエストでも一致することを確かめている。
  - 初めて読むときに `geotiff.wasm` と `data-geotiff.js`（合わせて gzip で約 17KB）を読み込む。
- 初めて呼んだときに、専用の Worker と wasm（gzip で約 38KB）を読み込む。KML か GPX を初めて読むときに、もう 1 つの wasm（`xml.wasm`、約 26KB）を読む。`terminate()` で止める。

## Web Component `<mb-map>`

```html
<script type="module">import "mbmap/element";</script>
<mb-map style-url="/style.json" center="139.7671,35.6812" zoom="14" style="height: 400px"></mb-map>
```

- 属性：`style-url`、`center`（`lng,lat`）、`zoom`（0〜22）、`bearing`、`pitch`（0〜85）、`worker-count`（0〜4）、`worker-url`、`wasm-url`、`attribution-control`（`true` か `false`。出典を自分で表示するときは `false`）。不正な値は受け付けず、`mb-error` を出す。
- プロパティ：`map`（`Map`。作成前と削除後は null）、`mapStyle`（スタイルのオブジェクト。`style-url` より優先。変えると地図を作り直さず `setStyle` で差し替える）、`center`、`zoom`、`bearing`、`pitch`。
- イベント：`mb-load`、`mb-movestart`、`mb-move`、`mb-moveend`、`mb-idle`、`mb-error`。`detail` は `{ map, center, zoom, bearing, pitch, error? }` で、Shadow DOM の外まで伝わる。
- 文書から外すと地図を解放し、戻すと同じカメラで作り直す。同じタスク内での移動では作り直さない。
- React 19 からは、そのまま `<mb-map zoom={...} onmb-move={...} />` と書ける（`examples/react`、`bench/npm/pages/element`）。

## 操作

ドラッグで移動、ホイールとピンチでズーム。右ドラッグ（または Ctrl＋ドラッグ）で、横に動かすと回転、縦に動かすと傾く。2本指をひねると回転する。

## 対応するスタイル

MapLibre の Style Spec（v8）を、MapLibre 6.16 と同じ描き方で描く（`npm run style:golden` などで画素ごとに比べている）。描けないプロパティ・式・レイヤーは、JSON 上の場所付きの警告を出して除く（`strict` ではエラー）。黙って無視はしない。公開のスタイル（OpenMapTiles、OpenFreeMap、Protomaps など）から何が除かれるかは、`npm --prefix bench run style:compat` で一覧できる。

### ソース

- `vector`：`tiles` に `{z}/{x}/{y}` のテンプレート（http(s) か相対 URL）、`minzoom`、`maxzoom`、`bounds`（外のタイルは要求しない）、`scheme: "tms"`、`promoteId`、`attribution`。
- `raster`：`tiles`、`tileSize`（128・256・512）など vector と同じもの。
- `raster-dem`：`tiles`、`tileSize`、`encoding` は `mapbox`・`terrarium`・`custom`（`redFactor` などの係数）、それに国土地理院の標高タイル用の拡張 `gsi`。
- `url` で TileJSON を指すソース（vector、raster、raster-dem）。TileJSON の `tiles`、`minzoom`、`maxzoom`、`bounds`、`attribution` などを読み、ソースに書いた値を優先する。
- GeoTIFF・COG（mbmap 独自のソース型）：`{ type: "geotiff", url: "https://…/x.tif" }` を `raster` レイヤーで描く。`dem: true` なら標高のソースになり、`hillshade`・`color-relief`・`terrain` に使える。
  - EPSG のコードを持つファイルなら座標系を問わずに描く。EPSG:3857 と EPSG:4326（JGD2011・JGD2000 の経緯度も）はそのまま、ほかの座標系（平面直角座標系、UTM など、`mbmap/analysis` の座標変換が知っているもの）は画素ごとの中心を `proj.wasm` でファイルの座標系にしてから引く（初めてのときに `proj.wasm` を読む）。
  - 表示するタイルごとに、ちょうどよい概観図の必要なブロックだけを範囲リクエストで読む（ヘッダーとブロックはワーカーに残して使い回す）。`bounds` と `maxzoom` はファイルから決める（ソースに書けばそちらを使う）。
  - 色：8 ビットの 3 帯・4 帯は RGB・RGBA。1 帯（または `bands` の最初の帯）は `range`（`[最小, 最大]`、省くといちばん粗い画像の値の範囲）を黒から白に、`colors`（`[値, 色]` の並び。色は CSS の書き方）があればその間を直線でつなぐ。no data と範囲の外は透明。`resampling` は `"nearest"`（既定）か `"bilinear"`。`tileSize` は 256（既定）か 512。
  - 標高は Terrarium の PNG にしてから描くので、1/256 m 刻みになる。
  - 描いたタイルは、GSI の標準地図から作った COG を元の PNG タイルと画素単位で比べて一致すること、平面直角座標系 IX 系（EPSG:6677）のファイルを proj4js で独立に引いた画素と一致することを確かめている（`npm run geotiff:tiles`）。
  - `mbmap/data` の `rasterInfo(input)` と `rasterTile(input, z, x, y, options)` で、同じ情報とタイル（PNG）を直接得られる。
- PMTiles：`url: "pmtiles://https://…/x.pmtiles"`。プラグインは不要。ワーカーが範囲リクエストでディレクトリとタイルを読む。圧縮は none と gzip に対応する。サーバーは Range に対応している必要がある。
- `geojson`：`data` に URL（認証情報なしで取得し、http(s) に限る）かオブジェクト。`maxzoom`、`buffer`、`tolerance`、`lineMetrics`、`promoteId`、`cluster`、`clusterRadius`、`clusterMaxZoom`、`clusterMinPoints`、`clusterProperties`。GeoJSON は専用の Worker の中で、MoonBit（wasm）で読み込んでタイルに切る（geojson-vt と同じタイル）。`clusterProperties` のあるソースは、式を持つ別の wasm `geojson-properties.wasm` で読む。
- `image`（`url`、`coordinates`）、`video`（`urls`、`coordinates`。音を消してループ再生する）、`canvas`（`canvas` に要素の id、または `addSource` に要素そのもの、`animate`、`coordinates`）。四隅の位置は MapLibre と同じく計算し、四角形でない配置は MapLibre と同じくゆがめて描く。再生中の動画と `animate` の canvas は毎フレーム描き直す（MapLibre と違い、そのあいだも `idle` になる）。

### レイヤー

- `background`：`background-color`、`background-opacity`、`background-pattern`。
- `fill`：`fill-color`、`fill-opacity`、`fill-antialias` と `fill-outline-color`（MapLibre の輪郭の描き方）、`fill-pattern`、`fill-translate`・`fill-translate-anchor`、`fill-sort-key`。
- `line`：`line-color`、`line-opacity`、`line-width`、`line-gap-width`、`line-offset`（地物ごとの式も）、`line-blur`（ズームの式まで）、`line-dasharray`（ズームの式も地物ごとの式も）、`line-gradient`（`["line-progress"]` で。GeoJSON ソースの `lineMetrics: true`）、`line-pattern`、`line-translate`・`line-translate-anchor`、`line-cap`、`line-join`、`line-miter-limit`、`line-round-limit`、`line-sort-key`。
- `circle`：`circle-color`、`circle-opacity`、`circle-radius`、`circle-blur`（ズームの式まで）、`circle-stroke-color`・`circle-stroke-opacity`・`circle-stroke-width`、`circle-pitch-scale`、`circle-pitch-alignment`、`circle-translate`・`circle-translate-anchor`、`circle-sort-key`（タイルをまたいでキーの順に描く）。
- `heatmap`：`heatmap-radius`、`heatmap-weight`、`heatmap-intensity`、`heatmap-color`（`["heatmap-density"]` で）、`heatmap-opacity`。MapLibre と同じく、密度を画面の 1/4 の大きさのテクスチャに足してから色を付ける。
- `fill-extrusion`：`fill-extrusion-color`、`fill-extrusion-opacity`、`fill-extrusion-height`、`fill-extrusion-base`、`fill-extrusion-vertical-gradient`、`fill-extrusion-pattern`、`fill-extrusion-translate`。スタイルの `light`（`anchor`、`color`、`intensity`、`position`）で陰を付ける。高さと基部は地物ごとに Worker で頂点に入れ、ズームの式はタイルのズームとその 1 段下の値の間を補間する（MapLibre と同じ）。高さは 0〜6553.5m（0.1m 単位）。半透明のものは、MapLibre と同じく各画素にいちばん手前の面だけを描く。地形があるときは、建物を重心の地面の高さに置く。
- `raster`：`raster-opacity`、`raster-hue-rotate`、`raster-brightness-min`・`max`、`raster-saturation`、`raster-contrast`、`raster-resampling`。止まっているときは MapLibre と同じく画素の格子にそろえて描く。フェードはない。
- `hillshade`：`hillshade-method`（`standard`、`basic`、`combined`、`igor`、`multidirectional`。複数の光源も）、`hillshade-illumination-direction`、`hillshade-illumination-altitude`、`hillshade-illumination-anchor`、`hillshade-exaggeration`、`hillshade-shadow-color`、`hillshade-highlight-color`、`hillshade-accent-color`。
- `color-relief`：`color-relief-color`（`["elevation"]` の `interpolate`）、`color-relief-opacity`。
- `symbol`：点と線に沿った（`symbol-placement` の `point`、`line`、`line-center`）文字のラベルとアイコン。
  - 文字：`text-field`（`{key}` の書き方、`get`、`concat`、`to-string`、`format`）、`text-font`、`text-size`、`text-anchor`、`text-offset`、`text-radial-offset`、`text-variable-anchor`、`text-variable-anchor-offset`、`text-justify`、`text-max-width`、`text-line-height`、`text-letter-spacing`、`text-transform`、`text-rotate`、`text-max-angle`、`text-keep-upright`、`text-padding`、`text-optional`、`text-allow-overlap` と `text-overlap`、`text-ignore-placement`、`text-writing-mode`（最初の値。縦書きでは、漢字・かなは立て、ラテン文字は横倒し、括弧と句読点は縦書き用の字形にする）、`text-color`、`text-opacity`、`text-halo-color`、`text-halo-width`、`text-halo-blur`、`text-translate`・`text-translate-anchor`。
  - アイコン：`icon-image`、`icon-size`、`icon-rotate`、`icon-anchor`、`icon-offset`、`icon-padding`、`icon-text-fit`・`icon-text-fit-padding`、`icon-optional`、`icon-allow-overlap` と `icon-overlap`、`icon-ignore-placement`、`icon-rotation-alignment`、`icon-pitch-alignment`、`icon-keep-upright`、`icon-color` と `icon-halo-*`（SDF の画像）、`icon-opacity`、`icon-translate`・`icon-translate-anchor`。
  - `symbol-spacing`、`symbol-sort-key`、`symbol-z-order` も MapLibre と同じ。`symbol-avoid-edges` は読まない（警告を出す）。
  - 文字はブラウザにあるフォントで描く（グリフ PBF は使わない）。`text-font` は MapLibre がグリフをその場で描くときと同じく、名前を CSS のフォントファミリーに並べ（最後に `fontFamily`）、最初の名前の `Bold`・`Light`・`Italic` などから太さと斜体を決める。`text-font` がなければ `fontFamily` で描く。
  - 地図を傾けると、MapLibre と同じく遠くのラベルほど小さく描き、カメラの距離の 5 倍より遠いラベルは置かない。

`*-translate` は定数とズームの式を受け付け、`queryRenderedFeatures` もそれに合わせて当たりを判定する。

### 画像

`fill-pattern`、`line-pattern`、`fill-extrusion-pattern`、`background-pattern`、`icon-image` は、スタイルの `sprite` と `addImage` で足した画像を使う。パターンは整数のズームで選ぶ（MapLibre のズームの間のクロスフェードはしない）。

### 地形と空

スタイルの `terrain`（`source` に `raster-dem` ソース、`exaggeration`）で、地図を地形の起伏の上に貼って描く。カメラの中心は地面の高さに合わせて持ち上がる。symbol レイヤーのラベルは地形の高さに置き、地形に隠れるものは消す（MapLibre と同じく、地形の深度と比べる）。

ピッチは MapLibre と同じく 85° まで。70° を超えると地平線が画面に入り、スタイルの `sky`（`sky-color`、`horizon-color`、`fog-color`、`fog-ground-blend`、`horizon-fog-blend`、`sky-horizon-blend`。ズームの式も可。`atmosphere-blend` は地球儀用なので読まない）があれば、その上に空を描き、地形には遠くほど霧をかける。`sky` がなければ、MapLibre と同じく空も霧も描かない。

### 式

MapLibre 6.16 の式を、型の注釈も含めて MapLibre と同じに評価する（`npm run expression:golden` で style-spec 26.5.0 と比べている）。`let`・`var`、`interpolate`（`interpolate-hcl`・`interpolate-lab` も）、`step`、`match`、`case`、`coalesce`、比較（`collator` つきも）、数学と文字列の演算、`format`（`font-scale`、`vertical-align`、区切りごとの `text-font` と `text-color`）、`number-format`、`split`・`join`、`resolved-locale`、`is-supported-script`（MapLibre 6.16 と同じく常に true）、`global-state`、`feature-state`（paint で）、`within` と `distance`（フィルタ、レイアウト、fill・line・circle・heatmap の地物ごとの paint。記号や押し出しの paint、feature-state を読むレイヤーの paint では未対応）、`accumulated`（`clusterProperties` の reduce で）など。数の書式と文字列の照合はブラウザの `Intl` で行う。旧形式のフィルタとプロパティ関数（`stops`）は、MapLibre と同じく式に変換して描く。

未対応のおもなもの：`object` と `properties`、`get`・`has` のオブジェクト引数、`format` の中の `image`、`symbol-placement`・`text-anchor`・`text-offset`・`icon-offset`・`fill-antialias` を式で与えること、線に沿ったラベルの `viewport` の配置（`text-pitch-alignment`・`text-rotation-alignment`）、`light.position` の式。

WebGL2 とモジュール Worker、wasm-gc が必要（Chrome / Edge 119 以降、Firefox 120 以降、Safari 18.2 以降）。

## ライセンス

Apache-2.0。`LICENSE` と `NOTICE` を参照。
