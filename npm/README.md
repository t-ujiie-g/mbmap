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
| `dist/worker.js` | タイル Worker（モジュール Worker） |
| `dist/mbmap.wasm` | Worker が読む wasm-gc |

`worker.js` と `mbmap.wasm` は、既定で `new URL("./worker.js", import.meta.url)` のように `index.js` の隣から読む。ESM をそのまま配信する場合（import map など）は、そのまま動く。バンドラを使う場合、この書き方を解釈するかどうかはバンドラと設定によって違う（まだ検証していない）。動かないときは、2つのファイルを自分で配信し、`workerUrl` と `wasmUrl` で場所を渡す。Worker はページと同じオリジンの http(s)、wasm は http(s) の URL に限る（`data:` や `blob:` は受け付けない）。モジュール Worker はページと同じオリジンでなければならない。

Content Security Policy を使うページでは、wasm のコンパイルに `script-src 'wasm-unsafe-eval'`、Worker に `worker-src 'self'`（または `script-src 'self'`）が要る。`eval` と `new Function` は使っていない。

## API

- `new Map(options)`：`container`、`style`、`center`、`zoom`、`bearing`（北から時計回りの度）、`pitch`（0〜85 度）、`workerCount`（0 なら自動、1〜4）、`workerUrl`、`wasmUrl`、`fontFamily`（ラベルの CSS フォントファミリー。既定 `sans-serif`）、`attributionControl`（既定 true。ソースの `attribution` を文字列として表示する）。
  - スタイルがオブジェクトで、描けない内容を含むときは、例外を投げる。URL の場合は `error` イベントになる。
- `on` / `off` / `once(type, listener?)`：`load`（最初の描画）、`idle`（落ち着くたび）、`move`（カメラが変わるたび）、`error`。
- `getCenter()`、`getZoom()`、`getBearing()`、`getPitch()`、`jumpTo({ center, zoom, bearing, pitch })`、`setCenter`、`setZoom`、`setBearing`、`setPitch`。bearing は -180〜180 に折り返し、pitch は 0〜85 に収める。値が変わらないときは `move` を出さない。有限でない値（NaN など）は TypeError になる。
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
- イベント：`mb-load`、`mb-move`、`mb-idle`、`mb-error`。`detail` は `{ map, center, zoom, bearing, pitch, error? }` で、Shadow DOM の外まで伝わる。
- 文書から外すと地図を解放し、戻すと同じカメラで作り直す。同じタスク内での移動では作り直さない。
- React 19 からは、そのまま `<mb-map zoom={...} onmb-move={...} />` と書ける（`examples/react`）。

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
