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

| ファイル | 内容 |
|---|---|
| `dist/index.js` | メインスレッドの ESM（`Map`） |
| `dist/index.d.ts` | 型定義 |
| `dist/element.js` | Web Component `<mb-map>`（`mbmap/element`。import すると要素が登録される） |
| `dist/ui.js` | 見た目を持たない UI のコントローラ（`mbmap/ui`） |
| `dist/search.js` | 見た目を持たない検索（GeoSearch、`mbmap/search`） |
| `dist/geojson.js`, `dist/geojson-worker.js`, `dist/geojson.wasm` | GeoJSON ソース用のモジュール、Worker、wasm。スタイルに GeoJSON ソースがあるときだけ、`index.js` が動的 import で読み込む |
| `dist/analysis.js`, `dist/analysis-worker.js`, `dist/analysis.wasm` | 解析（`mbmap/analysis`）の入口、Worker、wasm。`mbmap/analysis` を import したときだけ読み込まれる |
| `dist/geometry.wasm` | ジオメトリ演算（buffer、dissolve、clip、erase、intersect）。解析の Worker が、初めて演算を呼んだときだけ読み込む（場所は `geometryWasmUrl` で変えられる） |
| `dist/proj.wasm` | 座標系の変換。解析の Worker が、初めて座標系を使ったときだけ読み込む（場所は `projWasmUrl` で変えられる） |
| `dist/projstring.js` | PROJ 文字列のパーサ。`analysis.js` が、初めて PROJ 文字列を受け取ったときだけ読み込む |
| `dist/worker.js` | タイル Worker（モジュール Worker） |
| `dist/mbmap.wasm` | Worker が読む wasm-gc |

`worker.js` と `mbmap.wasm` は、既定で `new URL("./worker.js", import.meta.url)` のように `index.js` の隣から読む。ESM をそのまま配信する場合（import map など）は、そのまま動く。バンドラを使う場合、この書き方を解釈するかどうかはバンドラと設定によって違う（まだ検証していない）。動かないときは、2つのファイルを自分で配信し、`workerUrl` と `wasmUrl` で場所を渡す。Worker はページと同じオリジンの http(s)、wasm は http(s) の URL に限る（`data:` や `blob:` は受け付けない）。モジュール Worker はページと同じオリジンでなければならない。

Content Security Policy を使うページでは、wasm のコンパイルに `script-src 'wasm-unsafe-eval'`、Worker に `worker-src 'self'`（または `script-src 'self'`）が要る。`eval` と `new Function` は使っていない。

## API

- `new Map(options)`：`container`、`style`、`center`、`zoom`、`bearing`（北から時計回りの度）、`pitch`（0〜85 度）、`workerCount`（0 なら自動、1〜4）、`workerUrl`、`wasmUrl`、`fontFamily`（ラベルの CSS フォントファミリー。既定 `sans-serif`）、`attributionControl`（既定 true。表示中のレイヤーと地形が使うソースの `attribution` を、MapLibre と同じ順で文字列として表示する）。
  - スタイルがオブジェクトで、描けない内容を含むときは、例外を投げる。URL の場合は `error` イベントになる。
- `on` / `off` / `once(type, listener?)`：`load`（最初の描画）、`render`（描画のたび）、`idle`（落ち着くたび）、`move`（カメラが変わるたび）、`error`。
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
  - `addSource(id, source)`、`removeSource(id)`（レイヤーや地形が使っている間は `error`）、`getSource(id)`（GeoJSON ソースは `setData(data)` でデータを差し替える）。
  - `setTerrain`・`getTerrain`、`setSky`・`getSky`、`setLight`・`getLight`（null で外す）。
  - 描けないスタイルになる変更は `error` イベントを出し、元のスタイルのまま描き続ける。スタイルの読み込み前に呼ぶと例外になる。
- 地物の問い合わせ（結果は MapLibre と同じ。`npm run query:golden` で MapLibre 6.16 と比べている）：
  - `queryRenderedFeatures(geometry?, { layers, filter })`：点 `[x, y]` か範囲 `[[x0, y0], [x1, y1]]`（CSS ピクセル。省略すると地図全体）に描かれている地物を、上のものから順に返す。各地物には `layer`（スタイルのレイヤー）、`source`、`sourceLayer`、`state` が付く。
  - `querySourceFeatures(sourceId, { sourceLayer, filter })`：描画中のタイルにあるソースの地物を返す。
  - ジオメトリはワーカーが持つので、どちらも Promise を返す（MapLibre は同期）。
  - MapLibre 6 は既定で source の maxzoom より深いズームのタイルを切り分けるため（`zoomLevelsToOverscale`）、そこでは同じ地物の切り口と重複が MapLibre と違う。mbmap は source のタイルのまま描き、問い合わせる。
- ラスタタイルとタイルの在りか：
  - `raster` のソースとレイヤー。paint は `raster-opacity`、`raster-hue-rotate`、`raster-brightness-min`・`max`、`raster-saturation`、`raster-contrast`、`raster-resampling` に対応する。止まっているときは MapLibre と同じく画素の格子にそろえて描く。フェードはない。
  - `url` で TileJSON を指すソース（vector、raster、raster-dem）。TileJSON の `tiles`、`minzoom`、`maxzoom`、`bounds`、`attribution` などを読み、ソースに書いた値を優先する。`bounds` の外のタイルは要求しない。`scheme: "tms"` にも対応する。
  - PMTiles：`url: "pmtiles://https://…/x.pmtiles"`。プラグインは不要。ワーカーが範囲リクエストでディレクトリとタイルを読む。圧縮は none と gzip に対応する。サーバーは Range に対応している必要がある。
  - `transformRequest`（オプションと `setTransformRequest`）：スタイル、TileJSON、タイルの要求の URL、ヘッダー、`credentials` を変えられる。既定では資格情報を送らない。PMTiles の範囲リクエストは対象外。
- 地物の状態（feature-state）：`setFeatureState({ source, sourceLayer, id }, state)`、`getFeatureState`、`removeFeatureState(target, key?)`。
  - paint で `["feature-state", key]`（`boolean`・`number`・`string` で型をそろえる）を読むと、その地物だけその状態で描く。fill、line、circle、fill-extrusion の色と不透明度、線の太さ、円の大きさに効く。
  - 地物の id は、タイルの id、GeoJSON の `id`、または source の `promoteId` が指すプロパティ。同じ id の地物はまとめて同じ状態になる。
  - ワーカーが地物の位置を持ち、状態のある地物の分だけを問い合わせるので、変更は 1 往復遅れて描かれる。フィルターや layout では使えない（MapLibre と同じ）。
- マウスイベント：`mousedown`、`mouseup`、`mouseover`、`mouseout`、`mousemove`、`click`（押してから 3px 未満の移動のとき）、`dblclick`、`contextmenu`。`point` と `lngLat` が入る。
  - `map.on("click", "レイヤー id", f)` のようにレイヤーを指定すると、その下の地物（`e.features`）があるときだけ呼ぶ。`mouseenter`・`mouseleave` はレイヤー指定でだけ使える。問い合わせを待ってから呼ぶので、DOM のイベントより少し遅れる。
- `loaded()`、`getContainer()`、`getCanvas()`、`getAttributions()`（いま表示する出典の一覧）、`evaluatePaint(layerId, properties)`（その属性の地物を、いまのズームでどう描くか。凡例が使う）、`remove()`。`getMinZoom(true)` は、緯度の制約と `maxBounds` で実際に下げられる最小ズームを返す（MapLibre と同じ）。`styledata` イベントは、スタイルの読み込みと変更のたびに出る。

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

const blocks = await load(polygonsGeoJSON);  // オブジェクト、UTF-8 のバイト列、http(s) の URL
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
  - `toGeoJSON({ crs })`：FeatureCollection として取り出す（Worker の中で組み立てる）。`crs` を渡すとその座標系の座標で返す。
- 座標系：`load(data, { crs })` で投影座標のデータを読める（読み込むときに経緯度へ変換する）。`buffer` の `mode: "planar"` は `crs`（既定は 3857）の平面で測る。`transform(coords, from, to)` は `[x, y, x, y, …]` を別の座標系に変換して `Float64Array` で返す（投影の範囲外の点は NaN）。初めて座標系を使ったときに `proj.wasm` を読む。
  - `crs` に渡せるもの：EPSG コード（`6677`、`"EPSG:6677"`、`"urn:ogc:def:crs:EPSG::6677"`）、`"CRS84"`、PROJ 文字列（`"+proj=lcc +lat_0=46.5 …"`。epsg.io などにある形）、`defineCrs(name, projString)` で名前を付けたもの（`proj4.defs` と同じ使い方。`defineCrs("EPSG:2154", "+proj=lcc …")`）。
  - PROJ 文字列なしで使える EPSG コード：経緯度 4326（WGS84）・4612（JGD2000）・6668（JGD2011）・4301（日本測地系）、Web メルカトル 3857（3785、900913）、平面直角座標系 I〜XIX 系 6669〜6687（JGD2011）・2443〜2461（JGD2000）・30161〜30179（日本測地系）、UTM 32601〜32660・32701〜32760（WGS84）・6688〜6692（JGD2011、51〜55 帯）・3097〜3101（JGD2000）・3092〜3096（日本測地系）。
  - 投影：`longlat`、`merc`、`tmerc`（`etmerc`）、`utm`、`lcc`、`aea`、`aeqd`、`stere`、`sterea`、`cass`、`laea`、`eqc`、`eqdc`、`sinu`、`eck6`、`moll`、`robin`、`cea`、`mill`、`poly`、`omerc`、`somerc`、`krovak`、`ortho`、`gnom`、`eqearth`、`bonne`。
  - 測地系の変換は `+towgs84`（3 または 7 パラメータ）と `+datum`（`WGS84`、`NAD83`、`potsdam`、`OSGB36`、`ch1903` など proj4js と同じ名前）で、WGS84 を経由して行う。日本測地系は EPSG の 3 パラメータ（-146.414, 507.337, 680.507）。グリッドによる変換（`+nadgrids`、TKY2JGD など）は使えない。JGD2000・JGD2011 と WGS84 は同じものとして扱う。
  - 値は proj4js 2.22.0 と 1mm 未満で一致する（240 の座標系で黄金テストをしている）。proj4js が明らかに誤っているところ（`+R_A` の半径、正弦図法などの偽原点）は PROJ に合わせた。
- `loadDem(tiles, { zoom, bounds, encoding })`：標高タイル（`{z}/{x}/{y}` の http(s) URL）のうち `bounds` を覆うものを並べて、1つの標高の格子（`DemGrid`）にする。`DemGrid` は `width`、`height`、`bounds`（タイルの境界に合わせた範囲）、`elevations()`、`slope()`（度）、`aspect()`（北から時計回りの度。平らなところは NaN）、`hillshade({ azimuth, altitude, zFactor })`（1〜255）、`dispose()`。勾配・斜面方位・陰影起伏は GDAL の gdaldem（Horn の方法）と同じ式で、黄金テストで比べている。
- `distance(from, to)`：2点間の大圏距離（m）。Worker を使わずに同期で計算する。
- `terminate()`：Worker を止める。読み込んだデータは失われる。

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

background / fill / line / circle / symbol レイヤーと、vector ソース（`tiles` に `{z}/{x}/{y}` のテンプレート。http(s) か相対 URL）・GeoJSON ソース（`data` に URL かオブジェクト。`maxzoom`、`buffer`、`tolerance`。クラスタリングは未対応）。GeoJSON は専用の Worker の中で、MoonBit（wasm）で読み込んでタイルに切る。URL は認証情報なしで取得し、http(s) に限る。式は `get` `has` `geometry-type` `zoom` `!` `all` `any`、比較、`in` `match` `case` `coalesce` `interpolate` `step`。未対応のものは、JSON 上の場所付きのエラーになり、黙って無視はしない。

fill-extrusion レイヤー（`fill-extrusion-color`、`fill-extrusion-opacity`、`fill-extrusion-height`、`fill-extrusion-base`、`fill-extrusion-vertical-gradient`）とスタイルの `light`（`anchor`、`color`、`intensity`、`position`）に対応している。高さと基部は地物ごとに Worker で頂点に入れ、ズームの式はタイルのズームとその 1 段下の値の間を補間する（MapLibre と同じ）。高さは 0〜6553.5m（0.1m 単位）。地形があるときは、建物を重心の地面の高さに置く。`fill-extrusion-pattern` と `fill-extrusion-translate` は未対応。

hillshade レイヤー（MapLibre の `standard` 方式。`hillshade-illumination-direction`、`hillshade-illumination-anchor`、`hillshade-exaggeration`、`hillshade-shadow-color`、`hillshade-highlight-color`、`hillshade-accent-color`）と `raster-dem` ソース（`tiles`、`tileSize`、`encoding` は `mapbox`・`terrarium`・`custom`、それに国土地理院の標高タイル用の拡張 `gsi`）にも対応している。

スタイルの `terrain`（`source` に `raster-dem` ソース、`exaggeration`）で、地図を地形の起伏の上に貼って描く。カメラの中心は地面の高さに合わせて持ち上がる。symbol レイヤーのラベルは地形の高さに置き、地形に隠れるものは消す（MapLibre と同じく、地形の深度と比べる）。

ピッチは MapLibre と同じく 85° まで。70° を超えると地平線が画面に入り、スタイルの `sky`（`sky-color`、`horizon-color`、`fog-color`、`fog-ground-blend`、`horizon-fog-blend`、`sky-horizon-blend`。ズームの式も可。`atmosphere-blend` は地球儀用なので読まない）があれば、その上に空を描き、地形には遠くほど霧をかける。`sky` がなければ、MapLibre と同じく空も霧も描かない。

symbol レイヤーは、点に置く文字のラベルに対応している（`text-field`（`{key}` の書き方、`get`、`concat`、`to-string`）、`text-size`、`text-anchor`、`text-offset`、`text-max-width`、`text-line-height`、`text-padding`、`text-allow-overlap`、`text-ignore-placement`、`text-writing-mode`（最初の値。縦書きでは、漢字・かなは立て、ラテン文字は横倒し、括弧と句読点は縦書き用の字形にする）、`symbol-sort-key`、`text-color`、`text-opacity`、`text-halo-color`、`text-halo-width`）。文字はブラウザにあるフォントで描く（グリフ PBF は使わない）ので、`text-font` は読まない。地図を傾けると、MapLibre と同じく遠くのラベルほど小さく描き、カメラの距離の 5 倍より遠いラベルは置かない。線に沿ったラベル、アイコン、`format` はまだない。

WebGL2 とモジュール Worker、wasm-gc が必要（Chrome / Edge 119 以降、Firefox 120 以降、Safari 18.2 以降）。

## ライセンス

Apache-2.0。`LICENSE` と `NOTICE` を参照。
