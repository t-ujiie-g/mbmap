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

- `new Map(options)`：`container`、`style`、`center`、`zoom`、`bearing`（北から時計回りの度）、`pitch`（0〜85 度）、`workerCount`（0 なら自動、1〜4）、`workerUrl`、`wasmUrl`、`fontFamily`（ラベルの CSS フォントファミリー。既定 `sans-serif`）、`attributionControl`（既定 true。ソースの `attribution` を文字列として表示する）。
  - スタイルがオブジェクトで、描けない内容を含むときは、例外を投げる。URL の場合は `error` イベントになる。
- `on` / `off` / `once(type, listener?)`：`load`（最初の描画）、`idle`（落ち着くたび）、`move`（カメラが変わるたび）、`error`。
- `getCenter()`、`getZoom()`、`getBearing()`、`getPitch()`、`jumpTo({ center, zoom, bearing, pitch })`、`setCenter`、`setZoom`、`setBearing`、`setPitch`。bearing は -180〜180 に折り返し、pitch は 0〜85 に収める。値が変わらないときは `move` を出さない。有限でない値（NaN など）は TypeError になる。
- カメラの移動（MapLibre と同じ計算。`npm run camera:golden` で MapLibre 6.16 の Camera と比べている）：
  - `easeTo(options)`（既定 500ms）、`flyTo(options)`（ズームアウトして戻る。`curve`、`speed`、`screenSpeed`、`maxDuration`、`minZoom`）、`panBy`、`panTo`、`zoomTo`、`zoomIn`、`zoomOut`、`rotateTo`、`resetNorth`、`resetNorthPitch`、`snapToNorth`、`stop()`。どれも `center`、`zoom`、`bearing`、`pitch`、`around`（その点を動かさない）、`offset`、`duration`、`easing`、`animate`、`essential`（OS の「視差効果を減らす」でもアニメーションする）を受け付ける。
  - `fitBounds(bounds, { padding, maxZoom, bearing, linear })`（既定は flyTo、`linear: true` で easeTo）、`fitScreenCoordinates(p0, p1, bearing)`、`cameraForBounds(bounds, options)`。`bounds` は `[[西, 南], [東, 北]]`、`[西, 南, 東, 北]`、`LngLatBounds`。
  - `project(lngLat)`（画面の `{ x, y }`）、`unproject(point)`、`getBounds()`（`LngLatBounds`。傾けたときは地平線まで）、`isMoving()`、`isEasing()`、`isZooming()`、`isRotating()`。
- 制限：`minZoom`・`maxZoom`（0〜24、既定 0 と 22）、`minPitch`・`maxPitch`（0〜85、既定 0 と 85）、`maxBounds`（表示がその範囲を出ない）。オプションでも、`setMinZoom` などの setter・getter でも変えられる。MapLibre と同じく、表示が南北の端（85.051129°）を越えないようにズームを上げる。
- 初期表示：`bounds`（と `fitBoundsOptions`）を渡すと、`center`・`zoom` の代わりにその範囲を表示する。
- 操作：`dragPan`、`scrollZoom`、`boxZoom`（Shift＋ドラッグ）、`dragRotate`、`keyboard`（矢印で 100px 移動、Shift＋矢印で回転・傾き、`+`・`-` でズーム）、`doubleClickZoom`（Shift で縮小）、`touchZoomRotate`、`touchPitch`（2 本指を上下に動かす）。オプションの `interactive: false` ですべて止め、`map.scrollZoom.disable()` のように 1 つずつ切り替えられる。ドラッグを離すと、MapLibre と同じ慣性で少し流れる。
- イベント：`movestart`・`move`・`moveend`、`zoomstart`・`zoom`・`zoomend`、`rotatestart`・`rotate`・`rotateend`、`pitchstart`・`pitch`・`pitchend`（MapLibre と同じ順）。ユーザーの操作によるものは `originalEvent` に DOM のイベントが入る。地図のパディング（`setPadding`）は未対応。
- `loaded()`、`getContainer()`、`getCanvas()`、`remove()`。

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

- 属性：`style-url`、`center`（`lng,lat`）、`zoom`（0〜22）、`bearing`、`pitch`（0〜85）、`worker-count`（0〜4）、`worker-url`、`wasm-url`。不正な値は受け付けず、`mb-error` を出す。
- プロパティ：`map`（`Map`。作成前と削除後は null）、`mapStyle`（スタイルのオブジェクト。`style-url` より優先）、`center`、`zoom`、`bearing`、`pitch`。
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
