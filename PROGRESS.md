# PROGRESS

## 現在の状況（2026-11-03）

- **終わったもの**：Phase 0〜14、Phase 13 と Phase 14 の後のリファクタリングとセキュリティチェック（PR #43 と、この見直し）、Phase 14.1（測地線の計測）、14.2（断面図）、14.3（描画）、14.4（編集）、14.5（分割・結合）。これで Phase 14 の 5 段階がそろった。
- **次**：Phase 15.6b（線に沿ったアイコン）。15.6a（点のアイコン）までと、15.1〜15.5、15.7〜15.12、15.2 は完了。15.6 の後は、Phase 15 の後のリファクタリングとセキュリティチェック。段階は下の「方針の更新：Phase 15」。
- **入口の大きさ**（予算は VISION §2）：

  | 入口 | 大きさ | 予算 |
  |---|---|---|
  | 表示（メイン） | 105.9KB（画像・動画・canvas のソースは別に `media.js` 2.0KB、カスタムレイヤーは `custom.js` 1.8KB） | 120KB（2026-11-03、ユーザー判断。15.8 で 100KB を超えるため、100KB から引き上げ） |
  | 表示ワーカー | 92.3KB | 100KB |
  | `mbmap/ui` | 6.8KB（全部入り） | 10KB（1 つ 2KB） |
  | `mbmap/search` | 2.8KB | 5KB |
  | `mbmap/draw` | 4.9KB（4867 バイト） | 10KB（2026-11-03、ユーザー判断。8KB 以内に収まればなおよい） |
  | `mbmap/geodesic` | 1.1KB ＋ ワーカー 12.0KB | 2KB ＋ 15KB |
  | `mbmap/analysis` | 3.3KB ＋ ワーカー 27.0KB（geometry.wasm 41.3KB） | 5KB ＋ 30KB（50KB） |

## Phase 15.6a：点のアイコン（2026-11-03）

状態：**完了**。15.6 は 2 つに分けた（15.6a は点のアイコン、15.6b は線に沿ったアイコン）。

- **スタイル**（`style/icon.mbt`）：`icon-image`（`{token}` の文字列、式、`["image", …]`）、`icon-size` と `icon-rotate`（データで変わってよい）、`icon-anchor`、`icon-offset`、`icon-padding`（MapLibre の `Padding`：1〜4 個の数）、`icon-allow-overlap`、`icon-ignore-placement`、`icon-optional`、`text-optional`、`icon-rotation-alignment` / `icon-pitch-alignment`（`auto` は MapLibre と同じく解決）、`icon-keep-upright`、`icon-text-fit`、`icon-text-fit-padding` を読む。paint は `icon-opacity`、`icon-color`、`icon-halo-color`、`icon-halo-width`、`icon-halo-blur`。線に沿うアイコン（`symbol-placement: line`）は 15.6b まで Unsupported。
- **ワーカー**：wasm は各ラベルに画像名の部品、`icon-size`（MapLibre と同じく 1 段深いズームで）、`icon-rotate` を足す（docs/FORMATS.md「Labels」）。文字のないアイコンだけのラベルも作る。
  - グルー（`worker/js/symbols.mjs`）が MapLibre の `shapeIcon`、`fitIconToText`、`getIconQuads`（画像の 1 px 外まで）、`CollisionFeature`（パディングと回転の外接矩形）を移植した。アイコンは 1 ラベル 1 四角形で、別のバッファー（`icon`）に入れる。頂点の角は MapLibre と同じく大きさ 1 の 1/32 px、大きさは ×128。
  - アイコンの大きさを知るために、メインスレッドが画像の名前と大きさをワーカーに送る（`{type: "images"}`。フレームに 1 回、変わったときだけ）。大きさの変わった画像を使ったタイルは読み直す。ワーカーが知らない画像は `missing` で返り、メインスレッドが `styleimagemissing` を 1 度だけ出す。
  - ファサードがスプライトを読んでいる間（`map_hold_images`）、アイコンのあるスタイルのタイルはワーカーで待つ（MapLibre のタイルがスプライトを待つのと同じ）。待たないと、読み込み前のタイルで `styleimagemissing` が出てしまう。
- **アトラス**：アイコン用に `PatternAtlas` をもう 1 つ持つ（折り返さない、透明な 1 px の余白。MapLibre の `ImageAtlas` のアイコン）。位置は動かさず、同じ大きさの画像に置き換えたときは画素だけ書き換える（アニメーションする画像でもタイルを読み直さない）。
- **配置**（`map/labels.mbt`）：MapLibre の `placeLayerBucketPart` と同じく、文字の箱を調べ、アイコンの箱を調べ、`text-optional` / `icon-optional` で組み合わせてから、文字、アイコンの順にグリッドへ入れる。`icon-allow-overlap` の「常に出す」規則も同じ。可変アンカーと `icon-text-fit` では、アイコンも各アンカーで収まる必要があり、文字と一緒に動く（`a_shift`）。問い合わせはアイコンの箱でも当たる。
- **描画**：MapLibre の symbol_icon と、SDF のアイコンには symbol_sdf（色、ハロー、ぼかし。幅 1 px を超えるハローは別のパス）を移した。レイヤーごとに、全タイルのアイコンを描いてから文字を描く（MapLibre の順）。大きさはデータで変わらなければ uniform（ズームで変わる値を毎フレーム評価）。拡大・回転・傾き・画素比の違いがなければ最近傍で取る（MapLibre の `iconsNeedLinear`）。`icon-rotation-alignment: map` は地図と一緒に回し、`icon-pitch-alignment: map` は地図の面に寝かせる。`icon-offset` があると、MapLibre と同じく遠近で大きさを変えない。
- **`npm run labels:golden`**：アイコンの場面を 10 個足した（GSI の記号をコードでアイコンに：平面、回転・オフセット・パディング・1.3 倍、傾き 50° と地図に沿う回転・データで変わる大きさ、文字とアイコン、`text-optional`、`icon-optional` と見つからない画像、`icon-ignore-placement` の下層と `icon-allow-overlap`、可変アンカー、`icon-text-fit: both` と可変アンカー、`icon-text-fit: width`）。
  - **27 場面すべて一致**（アイコン 968 個）。グリッドに入れた箱（文字とアイコン）の位置の差は 0.001px 未満。比較に、文字とアイコンそれぞれが出たかと、グリッドの箱の並びを足した。
- **`npm run style:golden`**：合成のスプライトにピン（14 × 18）と SDF の輪（20 px）を足し、場面を 3 つ足した。`icons`（ピン、半透明の点、色とハローの SDF の輪）、`icons-turned`（25° 回転、1.4 倍、地図に沿う回転、40° 傾けた地図）、`icons-2x`（2x の画面、地図に沿って回り画面に立つ）。**3 場面とも平均 0 / p99 0（画素まで一致）**。
  - 合成のスプライトの PNG は RGB で書かれていて、透明が失われていた（`bench/lib/png.mjs` の `encodePng`）。アルファ付きで書けるようにし、アイコンにだけ使う。模様の場面は不透明のまま測ってきたので、そのままにした。アルファを入れると `patterns` は平均 0.074 / p99 2 になる（半透明の模様の差。Phase 15 の後の見直しで調べる）。
- **example**：山手線の駅（クラスタにならないもの）を、ショーケースのスプライトの駅のアイコンで描いた（ズームで大きさが変わる、`icon-allow-overlap`）。スプライトは斜線とアイコンを、アルファ付きで作り直した（これまでの斜線は RGB の PNG で、斜線の間が黒く塗られていた）。
- 大きさ：メイン 100.7 → 105.9KB（+5.2KB）、表示ワーカー 88.4 → 92.3KB（+3.9KB：wasm +2.7KB、グルー +1.2KB）。
  - メインの内訳（概算）：シェーダー 0.6KB、配置の組み合わせと箱 1.2KB、描画（`draw_icons` と GL）1.0KB、スタイルの読み込み 1.0KB、画像の送信と読み直し・アトラス 1.0KB。アイコンの組み方と箱はグルーに置き、メインには入れていない。
  - `IconLayout` の `derive(Eq)`（0.4KB）は、レイアウトの JSON の比較に置き換えた。
- MapLibre との違い：
  - `icon-size` がデータとズームの両方で変わるとき、頂点の大きさはタイルのズーム ＋ 1 の値（MapLibre はズームの間を補間する）。
  - `icon-offset` の有無は、値が 0 でないかで見る（MapLibre は書いてあるか）。
  - 引き伸ばし（`stretchX`、`stretchY`、`content`）、`icon-overlap`、`icon-translate`、`symbol-z-order`（重なりを許すときの画面の y 順の描画）、フェードはない。SDF と非 SDF の画像を混ぜたとき、最初のアイコンに合わせる（MapLibre と同じ）。
  - 重なりを許すアイコンでも、遠すぎる（遠近の比が `MIN_PERSPECTIVE_RATIO` 未満）ものは出さない（文字と同じ）。
- **本線で測ってほしいもの**：`worker:browser`（記号レイヤーの組み立てにアイコンの読み込みと組み方が加わった）。`render --labels`（配置にアイコンの箱が加わったが、アイコンのないスタイルでは比較が増えるだけ）。

## Phase 15 の計測：ワーカー、ラベル、線に沿ったラベル（2026-11-03）

並列で進めた段（15.7〜15.12）では性能ベンチを回さなかったので、すべてマージした後に本線でまとめて測った。

- **`worker:browser`**（`process_tile` の中央値）：
  - Chromium 7.61ms、Firefox 10.70ms、WebKit 8.20ms。
  - 途中のリファクタリングの時点（7.44 / 10.28 / 8.16ms）より +0.5〜4%（アンカーの一覧と、線のラベルを 3 段分作る処理）。出力の大きさは 77.4MB で変わらない。
- **`render --labels`**（vsync あり、1 フレームの CPU 時間。中央値 / 95 パーセンタイル）：
  - パンは 0.47 / 1.0 → 0.62 / 1.46ms、ズームは変わらない（0.44 / 0.92ms）。15.7 で MapLibre の配置（画面外 100px まで置く、タイルの順）に合わせた分。
  - 同じ場面の MapLibre は 1.78 / 2.67ms。
- **`render --labels --line-labels`**（新しい選択肢：example の等高線のラベルを足す）：
  - パンは 0.68 / 1.56ms、ズームは 0.50 / 0.99ms。
  - MapLibre は 1.81 / 3.03ms と 1.52 / 3.02ms。15.8 の完了条件（フレームの CPU 時間が目標内）を満たす。

## Phase 15.12：カスタムレイヤー（2026-11-03）

状態：**完了**。

- MapLibre 6.16 の `CustomLayerInterface` を移した（`{id, type: "custom", renderingMode, onAdd, prerender, render, onRemove}`）。
  - **置き場所**：`addLayer` は、スタイルの文書に `{id, type: "custom"}` の置き場所を入れる。順番、`beforeId`、`moveLayer`、`removeLayer` は、ふつうのレイヤーと同じ編集で済む。`getStyle()` からは除く。新しいスタイル（`setStyle`）にないカスタムレイヤーは `onRemove` を呼んで外す（MapLibre と同じ）。
  - **エンジン**：style のレイヤーの種類 `Custom`（ソースなし）。描画の順番でそのレイヤーに来たら、JS の関数を 1 つ呼ぶ（`map/custom.mbt`）。`prerender` は、フレームを消す前に呼ぶ（MapLibre のオフスクリーンの段）。地形があるときは、記号や押し出しと同じく地形の上に描く（地形のテクスチャには描かない）。
  - **`custom.js`**（`npm/src/custom.ts`、1.8KB、予算 3KB を新設）：最初のカスタムレイヤーで読む。`onAdd(map, gl)` はそのときに呼ぶ（読み込み済みなら `addLayer` の中で）。`render(gl, options)` の `options` は MapLibre と同じ形：`modelViewProjectionMatrix`（世界のピクセルとメートル）、`projectionMatrix`、`fov`（ラジアン）、`nearZ`、`farZ`、`defaultProjectionData`（`mainMatrix` はメルカトルの 0〜1）、`getProjectionData({tileID})`（タイルの 8192 単位）、`shaderData`（メルカトルの prelude：`projectTile` など）。
  - **GL の状態**：利用者のコードの前に、使う状態を保存し、MapLibre の `setCustomLayerDefaults`（VAO を外す、カリングなし、`TEXTURE0`、pixelStore の既定）と深度（"3d" は深度テストあり、"2d" はなし）を設定する。後で、ブレンド、深度、カリング、ステンシル、シザー、カラーマスク、フレームバッファ、ビューポート、プログラム、VAO、バッファ、テクスチャ（0〜3）、pixelStore を戻す。
  - `triggerRepaint()` を足した（アニメーションするカスタムレイヤー用）。`addLayer` の検証は MapLibre の `validateCustomStyleLayer` と同じ（`render` がない、`renderingMode` が 2d・3d でない）。
- **core**：`Transform::world_matrix`（MapLibre の `modelViewProjectionMatrix`）と `Transform::projection`（`projectionMatrix`、`nearZ`、`farZ`）。`npm run camera:golden` に比較を足した：19 の視点で、画面の位置の差 0 px、射影行列と近・遠の面の相対差 5.6e-8 以下。
- **pack test**：`bench/npm/pages/custom/` と `checks/custom.mjs`。MapLibre の prelude で描いた青い箱が、`beforeId` で GeoJSON の赤い四角の下に入り、`moveLayer` で上に出る。利用者のコードが壊した状態（カリング、ブレンド、シザー、カラーマスク、pixelStore、アクティブなテクスチャ）は戻り、後のレイヤーは正しく描ける。`options`（中心がクリップ空間の原点、`fov`、`getProjectionData`）、"3d" の深度テスト、`prerender`、`triggerRepaint`、`getLayer`、`getStyle`、`onRemove`、検証のエラーを確かめる。
- example：東京駅から 5 km（分析の半径）の輪を、カスタムレイヤー（自前の WebGL）で地点の下に描いた（`examples/shared/ring.js`）。スタイルを替える（2D/3D、背景地図）と外れるので、`styledata` で入れ直す。pack test は、背景地図を替えて戻した後も地点の下にあることを確かめる。
- 大きさ（15.11 の後）：メイン 92.3 → 93.0KB（ファサードの `addLayer` と置き場所、エンジンの呼び出しと行列）、表示ワーカー 83.11 → 83.12KB（レイヤーの種類）、`custom.js` 1.8KB（予算 3KB を新設）。
- MapLibre との違い：
  - `onAdd` は `custom.js` を読んだ後（最初の 1 回だけ非同期）。
  - `renderToTerrainTile` と `renderTerrainHeightMap`（地形のテクスチャへの描画）、`getProjectionData` の `aligned`（ピクセルにそろえた行列）、地球儀の投影はない。行列は Float64Array のまま渡す。

## Phase 15.11：画像・動画・canvas のソース（2026-11-03）

状態：**完了**。

- MapLibre 6.16 の `ImageSource`、`VideoSource`、`CanvasSource` を移した。
  - **置き方**：画像の 4 隅から、中心のタイル（`getCoordinatesCenterTileID`）、8192 単位で丸めた隅、ゆがめ方（`calculateImageWarp` の auto：射影と、強く縮むときの双一次への混ぜ）を求める。この計算は `media.ts` の `quadOf` に置き、エンジンには数で渡す（下の大きさの節）。
  - **描画**：既存のラスターのシェーダーに、隅（`u_top`、`u_bottom`）とゆがめ方（`u_warp`）を足した（MapLibre の raster.vertex.glsl と同じ）。ラスタータイルは隅を 0〜4096 で渡すので、出力は変わらない（`raster:golden` は 8 組とも差 0 のまま）。画像はタイルで切らず、MapLibre が分割するとき（混ぜがあり平行四辺形でない）は 16 × 16 の格子で描く。テクスチャはミップマップなしで、乗算済みで上げる。`raster-resampling: nearest` でも縮小は線形（MapLibre と同じ）。
  - **動画と canvas**：再生中の動画、`animate` の canvas はフレームごとに上げ直し、描画を続ける。`pause` はその場で 1 回上げる（MapLibre の `pause` と同じ）。
  - **地形**：地形のタイルのテクスチャにも描く（画像の範囲が重なるタイルに）。
- **ファサード**：画像・動画・canvas のソースがあるスタイルで、`media.js` を読む（`legacy.js`、`pmtiles.js` と同じ。2.0KB）。
  - 画像は資格情報なしで取り、URL はスタイルの URL を基準に解決し、http(s) だけを受ける。`transformRequest` には `"Image"` として渡る（`ResourceType` に足した）。
  - 動画は muted・loop の `<video>`（`crossOrigin = "anonymous"`）。canvas は `getElementById` で探す（セレクタは作らない）。`addSource` に要素を渡す形も受ける（スタイルの JSON の複製には入らないので、ファサードが別に持つ）。
  - `getSource(id)` に `setCoordinates`、`updateImage`（`url` か、デコード済みの `image`）、`play`、`pause`、`getVideo`、`getCanvas`。`getStyle()` の `coordinates` と `url` も変わる。
  - 隅の形がおかしいとき（4 隅でない、数でない、世界の外）は `error` を出し、何も描かない。
- **`npm run style:golden`**：新しい場面 `images`（タイルからはみ出す長方形に `raster-opacity`、射影でゆがむ台形に色相・彩度・コントラスト、強く縮む台形を格子で `nearest` と明るさ）と、同じものを回して傾けた `images-turned` は、どちらも平均 0 / p99 0（画素まで一致）。ほかの場面は変わらない。
- **pack test**：`bench/npm/pages/media/` に画像・動画・canvas を並べ、`bench/npm/checks/media.mjs` で画素を読む。canvas は再生中に描き直され、止めると止めたときの絵のまま。動画は止めて再開できる。画像は `setCoordinates` で動き、`updateImage` で canvas の絵に変わり、`data:` の URL は `error` になる。動画を再生中でも `idle` は来る。動画は自作の 1KB の webm（赤 1 秒、青 1 秒）。
- example：東京駅の構内の略図（自作の PNG。`examples/shared/station-sketch.png`）を、線路に沿って傾けて重ねた（「駅の略図」グループ）。
- 大きさ（15.5a の後）：メイン 90.2 → 92.3KB（エンジンの描画と上げ直しで約 1.2KB、ファサードの読み込みと `getSource` で約 0.7KB）、表示ワーカー 83.06 → 83.11KB（スタイルの `Image` の種類）、`media.js` 2.0KB（予算 3KB を新設）。
  - 置き方の計算を最初は core（MoonBit）に置いたところ、メインが 3.0KB 増えた。`media.ts` に移し、エンジンのソースの表を `HashMap` から配列にして、+1.9KB まで減らした。
- MapLibre との違い：
  - 動画の再生中や canvas の `animate` 中も `idle` が来る（MapLibre は来ない）。`load` と `toBlob` が待ち続けないため。
  - 世界の繰り返し（経度の折り返し）は、ほかのタイルと同じく描かない。`setWarp` / `getWarp`（実験的）、動画の `seek`、canvas の大きさの変化の検知（再生していないとき）は移していない。
  - 画像・動画・canvas のレイヤーは `queryRenderedFeatures` に出ない（MapLibre も同じ）。

## Phase 15.5b：線と押し出しの模様、半透明の押し出し（2026-11-03）

状態：**完了**。

- **`line-pattern`**：MapLibre の line_pattern を移植した。
  - 模様は、高さが線の floor width になるように拡大縮小し、線に沿った距離で繰り返す。
  - 距離は破線と同じ仕組みで持つ（`StyleLayer::line_distances`：破線か模様の線）。
- **`fill-extrusion-pattern`**：MapLibre の fill_extrusion_pattern を移植した。
  - 屋根はタイル座標で、壁は輪に沿った距離と高さで模様を置く。
  - 壁の距離（MapLibre の `edgeDistance` の半分）は、押し出しの頂点のこれまで 0 だった値に入る。MapLibre と同じく 32768 を超えるとやり直す（`EXTRUSION_VERTEX_STRIDE` 7 → 8。パックした大きさは変わらない）。
  - 光の当たり方は、模様用の式（MapLibre と同じく、模様なしとは違う式）にした。
- **半透明の押し出し（もとからの不具合を直した）**：GSI の建物を不透明度 0.9 で描くと、main のままでも MapLibre と平均 5.36 ずれていた。
  - MapLibre は、レイヤーの全タイルを先に深度だけ描き、次に色を描く。色のパスはステンシルで数え、1 画素に 1 回だけ塗る。mbmap はメッシュごとに 2 パスで描き、ステンシルもなかったので、同じ高さで重なる屋根を 2 度塗っていた。
  - MapLibre と同じ手順にした（コンテキストと書き出し用のフレームバッファーにステンシルを付けた）。不透明でも模様があれば、MapLibre と同じく 2 パスで描く。
- **`npm run style:golden`**：新しい場面 3 つ。ほかの場面は変わらない。query:golden は 320/320。

  | 場面 | 平均 | p99 |
  |---|---|---|
  | `line-patterns`（ズームで変わる幅、半透明の線） | 0.233 | 1 |
  | `extrusion-patterns`（地物ごとの模様、傾けた視点） | 0.268 | 2 |
  | `extrusions-translucent`（模様のない半透明） | 0.098 | 0 |

  - 模様の 2 場面は、模様の縁が 1 画素未満ずれる差が残る。GeoJSON の箱 1 つでは 0.03 前後で一致した。
- 大きさ：メイン 90.2 → 91.2KB（線と押し出しの模様のシェーダー）、表示ワーカー 83.1KB のまま。

## Phase 15.5a：スプライト、`addImage`、塗りと背景の模様（2026-11-03）

状態：**完了**。15.5 は 2 つに分けた（15.5a は塗りと背景、15.5b は線と押し出しの模様）。

- **画像**：facade に `addImage`、`updateImage`、`removeImage`、`hasImage`、`listImages`、`loadImage` と `styleimagemissing` イベントを足した（MapLibre と同じ形）。
  - 受け付けるのは ImageData、RGBA の生データ（`{width, height, data}`）、または canvas に描けるもの（画像、ImageBitmap、canvas）。同じ id への 2 回目の `addImage` と、大きさが合わないデータは `error` にする。
  - スタイルの `sprite`（URL 1 つ、または `{id, url}` の並び。2x の画面では @2x を読む）は、遅延ロードの `sprite.js`（0.9KB）が `transformRequest` を通して読む。スプライトを読み終えるまで `idle` を待たせる。
- **アトラス**：メインスレッドは、模様を初めて描くときに画像をアトラスに詰める（棚詰め。MapLibre の `ImageAtlas` と同じく 1px の折り返しの余白を付ける）。画像が変わると作り直す。画像がない間はそのレイヤーを描かない（MapLibre と同じ）。
- **描画**：`fill-pattern` と `background-pattern` を、MapLibre の fill_pattern、fill_outline_pattern、background_pattern のシェーダーで描く。
  - 模様の位置は、整数ズームでのタイルの世界座標の画素で決まる。上位と下位の 16 bit に分けるのは MapLibre と同じ。
  - 模様は整数ズームで取る（ズームの間のクロスフェードはしない）。SDF の模様も描ける。
  - 地物ごとに模様を変えるレイヤーは、グループで描く（`StyleLayer::paints_by_group`）。
  - 塗りの輪郭は、タイルの塗りを全部描いてから描く。MapLibre と同じ順で、グループの塗りが前のグループの輪郭を覆わない。
  - `line-pattern` と `fill-extrusion-pattern` は、15.5b まで Unsupported のまま。
- **`npm run style:golden`**：合成のスプライト（`bench/style/sprite.mjs`。1x と 2x）を使う新しい場面 2 つ。
  - `patterns`（定数と地物ごとの模様、模様の輪郭と色の輪郭、背景）は平均 0.040 / p99 0。
  - `patterns-2x`（2x の画面、ズーム 15.6）は平均 0.030 / p99 0。
  - golden は、場面の `dpr` を MapLibre にも `ratio` として渡すようにした（それまで MapLibre は常に 1x だった）。
  - 半透明の背景の模様は 1 ずれる（MapLibre は透明に clear してページの白と合成するが、mbmap は白で clear する）。そのため場面の背景は不透明にした。
- **pack test**：`bench/npm/checks/images.mjs` で、画像がないときの `styleimagemissing`、`addImage` で描かれること、`updateImage`、重複と大きさ違いの `error`、`hasImage` / `listImages` / `removeImage` を確かめる。
- **example**：自前のスプライト（`examples/shared/sprite/`、斜線）で、構造物に斜線を重ねた。
- 大きさ：メイン 84.6 → 88.1KB（アトラス、シェーダー、画像の API）、表示ワーカー 81.7 → 82.1KB、`sprite.js` 0.9KB（予算 2KB）。15.9 と合わせて、メイン 90.2KB、表示ワーカー 83.1KB。

## Phase 15.9：heatmap レイヤー（2026-11-03）

状態：**完了**。

- **スタイル**：`heatmap` レイヤーを読む（`LayerKind::Heatmap`、`HeatmapPaint`）。
  - `heatmap-radius`（`StyleLayer::radius`）と `heatmap-weight` はデータで変わってよい。頂点ごとの値は円と同じ仕組みで、重みは不透明度のスロット（`SLOT_WEIGHT`）、半径は大きさのスロットに入る。feature-state を読むものは Unsupported（パス付き）。
  - `heatmap-intensity` と `heatmap-opacity` はズームだけ。`heatmap-color` は `["heatmap-density"]`（`Expr::HeatmapDensity`）だけを読む。データやズームを読めば Invalid。
  - `heatmap-density` はほかのプロパティでは Invalid（MapLibre と同じ）。既定の色の式は、名前の色を 16 進で書いた（色の解析は名前の色を 3 つしか知らない）。
- **ワーカー**：円と同じく、タイルの中の点ごとに四角形を 1 つパックする（`KIND_CIRCLE`。形式は変わらない）。円とはバッファーを共有しない。
- **メインスレッド**：MapLibre の 2 つのパスを移植した（`map/heatmap.mbt`、`render_webgl2/heatmap.mbt`、シェーダーは heatmap と heatmapTexture）。
  - 1 つ目：各点のガウス核を、画面の 1/4 の大きさの RGBA16F テクスチャーへ加算する（`ONE, ONE`）。四角形は地図の上に置く（ピッチで遠くは小さくなる）。核はタイルの外へはみ出してよいので切り取らない。タイルは 1 度だけ描き、子の代わりに祖先を描くときは、その子たちを描かない（MapLibre の `hasRenderableParent`）。
  - 2 つ目：密度を、`heatmap-color` の 256 px のランプ（`color_ramp`、`JsProps.density` で評価）で色にし、`heatmap-opacity` を掛けて画面に描く。ランプは式ごとに 1 度作り、スタイルが変われば使われないものを捨てる。
  - `EXT_color_buffer_float` は WebGL2 の多くの環境にある（MapLibre も有効にするだけで、ないときの代わりはない）。ないときは RGBA8 に描く（密度は 1 で頭打ちになり、粗くなる）。
  - ランプの乗算済みアルファを、MapLibre の `premultiplyAlpha` と同じく JS で丸めて作るようにした（WebGL の `UNPACK_PREMULTIPLY_ALPHA_WEBGL` は 1 ずれた）。線のグラデーションも同じ関数を使うので、`gradients` が 0.056 → 0.052 になった。
- **地形**：MapLibre と同じく、地形のタイルごとに、そのタイルの点の核を 512 px のテクスチャーに描いて色にし、地形のテクスチャーに重ねる。核はタイルの境目で切れる（MapLibre も同じ）。MapLibre は `encoding: "gsi"` を読めないので、画素の比較はしていない（目で確かめた）。
- **問い合わせ**：heatmap の点は、地図の上の半径の中で当たる（MapLibre の `circleIntersection`、`pitch-alignment: map`）。GSI の注記の点で、3 か所の問い合わせが MapLibre と一致した（一時的なスクリプトで確かめた）。
- **`npm run style:golden`**：新しい場面 3 つ。ほかの場面は変わらない（`gradients` は上のとおり少し良くなった）。

  | 場面 | 内容 | 平均 | p99 |
  |---|---|---|---|
  | `heatmap` | GeoJSON の 3000 点、既定のランプ、データで変わる重み、ズームで変わる半径と強さ | 0.484 | 5 |
  | `heatmap-tiles` | GSI の注記の点、既定のランプ、データで変わる重み | 0 | 0 |
  | `heatmap-turned` | GSI の注記の点、ステップのランプ、データで変わる半径、回して傾けた地図 | 0 | 0 |

  - `heatmap` の差は、点の位置の量子化による。mbmap の GeoJSON タイルの範囲は 4096、MapLibre は 8192 なので、z11 で点が最大 1/16 px ずれ、密度が 1% ほど変わる。ベクトルタイル（範囲 4096 で、両方同じ）では一致する。
- example：山手線の駅の密度を heatmap で描いた（「駅の密度」グループ。ズームインすると薄くなる）。
- 大きさ：メイン 84.6 → 86.8KB（86793 バイト）、表示ワーカー 81.7 → 82.8KB（82805 バイト）。
- 性能は測っていない（並列の作業中のため。ベンチは本線でまとめて走らせる）。heatmap のないスタイルでは、熱い経路に変更はない。
## Phase 15.8：線に沿ったラベル（`symbol-placement: line` / `line-center`）（2026-11-03）

状態：**実装と黄金テストは完了**。フレームの CPU 時間は本線で測る（並列の作業中は計測しない約束のため）。

- **スタイル**：`symbol-placement`（`line`、`line-center`）、`symbol-spacing`（既定 250）、`text-max-angle`（45）、`text-keep-upright`（true）。線に沿うときの `text-rotation-alignment` / `text-pitch-alignment` は `map` と `auto` だけ。`viewport` や、線に沿うラベルの `text-offset` などは Unsupported。
- **ワーカー**：wasm は線の地物（LineString と Polygon の輪）ごとに、文字と線をそのままパックする（docs/FORMATS.md「Labels」）。グルーが MapLibre の `mergeLines`、`clipLine`、`getAnchors`（`resample`）、`checkMaxAngle`、`getCenterAnchor`、同じ文字の近すぎるアンカーの除外（`anchorIsTooClose`）を移植した `worker/js/line-labels.mjs` でアンカーを求め、1 アンカー 1 ラベルにする。
  - MapLibre は、ソースの maxzoom を超えるとズームごとにラベルを置き直す（タイル単位の間隔が 1/2 ずつになる）。mbmap はソースのタイルを使い回すので、1・2・4 倍深いタイルの分を最初から作り（`LINE_LEVELS`）、表示ズームに合う段だけを置く。それより深いズームでは 4 倍の段を使う（MapLibre よりまばら）。
  - 1 エントリーのラベルは 4096 まで（`MAX_LINE_LABELS`。`symbol-spacing` を小さくすると際限なく増えるため）。
- **配置**（`map/line_labels.mbt`）：MapLibre の `placeCollisionCircles` を移植した。最初と最後の文字を線に沿って置き、その間の経路を画面に投影し（画面外 100px で切る）、`PathInterpolator` と同じ間隔の円で衝突を調べる。`label.Grid` に円を足した（円と箱、円と円の判定は `GridIndex` と同じ）。
- **描画**：カメラが動いたフレームごとに、表示中のラベルの文字を線に沿って歩かせ（`placeGlyphAlongLine` と `updateLineLabels`。逆さまになるなら反対向きに置き直す。線が足りなければ隠す）、文字ごとの位置と角度を頂点属性 `a_glyph` に送る。シェーダーは MapLibre の地図に沿う文字（`pitch_with_map`）と同じく、文字を地図の面に置いて遠近の比で大きさを変える。
- **`npm run labels:golden`**：等高線（`contour` の `alti`）の場面を 7 つ足した。平面、40° 回転、45° 傾き、ズーム 15.4（1 段深い）と `symbol-spacing` 150、`line-center` と `text-max-angle` 30、`text-keep-upright: false` で 160° 回転、点のラベルとの衝突。
  - **17 場面すべて一致**（点のラベル 1,120、線のラベル 108）。文字の画面上の位置の差の最大は 0.001px 未満、角度の差も 1e-6 rad 未満（許容は 0.5px と 0.01 rad）。
  - 最初の食い違いは、MapLibre が同じ文字で端がつながる線をまとめる（`mergeLines`）ことだった。移植して一致した。
- example：等高線に高さを線に沿って書いた（「等高線」グループの `contour-label`）。
- 大きさ：メイン 93.8 → 98.0KB（予算 100KB の残りは 2KB。線のラベルの配置と文字の配置が約 3.3KB、スタイル、円の衝突、シェーダーで約 0.9KB）、表示ワーカー 85.4 → 88.3KB。
- **要相談（予算）**：メインの残りが 2KB になった。案は A) このまま進める、B) 線のラベルの配置と文字の配置（約 3.3KB）を、線に沿うレイヤーがあるときだけ読む別ファイルに分ける（MoonBit の `map` から切り出す仕組みが要り、設計の変更になる）、C) 予算を見直す。アイコン（15.6）の前に決めたい。
- **本線で測ってほしいもの**：`npm run render`（`--labels` に等高線のラベルを足した状態、または例のスタイル）のフレームの CPU 時間。カメラが動くフレームごとに、表示中の線のラベルの文字を CPU で置き直し、頂点バッファーを送り直す。
- 未対応：縦書きの文字を線に沿わせること（MapLibre は縦長の区間で縦書きの版に切り替える）、`text-offset`（線からのずれ）、地形の上では文字ごとではなくアンカーの高さに置く、線のラベルの問い合わせは円の外接矩形で判定する（MapLibre は円ごとの矩形）。

## Phase 15.7：`text-variable-anchor`（2026-11-03）

状態：**完了**。

- **スタイル**：`text-variable-anchor`、`text-radial-offset`、`text-variable-anchor-offset`、`text-justify`（`auto` を含む）を読む。MapLibre の `getTextVariableAnchorOffset` と `evaluateVariableOffset` と同じく、各アンカーの em 単位のずれにしてから渡す（ベースラインの 7/24 em を含む）。`text-variable-anchor` がなくても `text-radial-offset` は効く。どれもデータで変わる値は Unsupported（パス付き）。`text-justify` の既定は MapLibre と同じ `center` になった（これまでは常にアンカーの側にそろえていた）。
- **ワーカー**：アンカーの一覧を symbol のエントリーの頭に足した（docs/FORMATS.md「Labels」）。グルーは中央に置いた形で文字を組む。行が 2 つ以上で `text-justify: auto` なら、左・中・右にそろえた 3 通りを並べて持つ（MapLibre が配置の後で使う方を選ぶのと同じ）。ラベルの表は 1 件 9 → 12 個の浮動小数（文字の大きさ、sort key、組み方の数）。
- **配置**（`map/labels.mbt`）：MapLibre の `Placement` に合わせ直した。可変アンカーだけでなく、点のラベル全体が MapLibre と同じ結果になった。
  - アンカーを順に試し、前回の配置で使ったアンカーを最初に試す。`text-allow-overlap` なら、重ならない場所を探した後に重なりを許す 2 巡目がある（`attemptAnchorPlacement` の passes）。
  - ずらし量は、パディング込みの箱の幅と高さから求め、頂点ごとの属性 `a_shift` で描く（遠近の倍率も掛かる）。
  - 画面の外 100px までを配置の範囲にする（`viewportPadding`）。衝突判定は辺が接しても衝突とし（`GridIndex`）、箱は MapLibre のタイルの整数の単位に切り捨てる（`CollisionBox` が Int16 のため。オーバースケールしたタイルでは単位が粗くなる）。
  - タイルの順は MapLibre の `Style._updatePlacement`（深いタイル、x、y の順）。これまでの「中心に近い順」と違った。`symbol-sort-key` のあるレイヤーは、タイルをまたいで sort key 順に置く。
  - パディングにも遠近の倍率を掛ける（MapLibre と同じ）。`text-allow-overlap` のラベルはグリッドの外でも出す（クエリには掛からない）。
- **文字の組み方**：行の分け方を MapLibre の `determineLineBreaks` に移した（行の長さをそろえる、改行・括弧の重み、`codePointAllowsIdeographicBreaking`）。これまでの貪欲な分け方と禁則処理（行頭の「。」などを避ける）はやめた。MapLibre は禁則処理をしないので、「あい。」は「あい／。」になる。
- **`npm run labels:golden`**（新規、`bench/results/labels-golden.json`）：MapLibre 6.16 と同じページで、同じスタイル、タイル、カメラで、表示されたラベルの集合と選ばれたアンカーを比べる。mbmap 側は `map_placed_labels`（テスト用のエクスポート。facade は使わないので本体のバンドルには入らない）で読む。
  - 10 場面すべて一致（1,120 ラベル）。固定アンカー（平面、30° 回転、50° 傾き、縦書きと sort key の例のスタイル）と、可変アンカー（radial、回転、傾き、`text-offset` と複数行と sort key、`text-variable-anchor-offset` と上に別レイヤー、`text-allow-overlap`）。箱の位置の差は 0.001px 未満。
  - 最初はタイルの順、行の分け方、箱の整数化、`viewportPadding` の 4 つで食い違っていた。いずれも MapLibre に合わせた。
- example：地点名（`places-label`）を点の横に置く（下・上・右・左の空いている方、`text-radial-offset` 0.8）。
- `npm run style:golden` と `query:golden`（320/320）は変わらない。
- 大きさ：メイン 86.8 → 89.3KB（15.9 の後から。スタイルの読み込みと配置で約 1.2KB ずつ）、表示ワーカー 82.8 → 85.1KB（行の分け方の表、スタイルの読み込み）。
- 未対応：縦書きと可変アンカーの組み合わせ（MapLibre の `placeTextForPlacementModes`）、アイコン（15.6）との `icon-text-fit`、フェード（ラベルは置いた位置にすぐ移る）。タイ文字などの単語境界（`Intl.Segmenter`）での改行はしない。

## リファクタリングとセキュリティチェック：Phase 15 の途中（2026-11-03）

状態：**完了**。15.1〜15.4、15.10、15.2 で足したものを見直した（ユーザーの指示で、Phase 15 の途中に挟んだ）。

- **ずれ**：`query:golden` が 319/320 だった（15.3a から）。
  - 原因は、塗りの輪郭が `feature-state` を見ていなかったこと。MapLibre の輪郭の色は、既定で塗りの色（state も含む）。
  - Feature ranges に、地物ごとの輪郭の索引の範囲を足した（docs/FORMATS.md）。輪郭も範囲ごとに state の色で描くようにして、320/320 に戻った。
- **定数**：破線の距離を `@core.TILE_EXTENT` の単位と定義し直した。描画にはタイル 1 単位あたりの CSS px を渡すので、`8192` と `4096.0` の直書きはなくなった。
- **重複**：
  - 線のジオメトリが同じかの判定を、`StyleLayer::same_line_layout` にまとめた（style の差分とワーカーで共有）。
  - `reads_state` と `reads_line_progress` は、共通の走査 `Expr::any` を使う。
  - 線の長さの二重計算（tess とワーカーの `ring_length`）は残した。`add_line` が長さを返すようにすると、呼び出し 5 か所に手が入る割に、得るものが小さい。
- **分割**：
  - `map/render.mbt` から、破線とグラデーションの補助を `map/line.mbt` へ移した。
  - `render_webgl2/gl.mbt` と `renderer.mbt` から、線の GL と描画を `gl_line.mbt`、`renderer_line.mbt` へ移した。
  - `worker/processor.mbt` から、`line_layer` とグラデーションの行を `worker/lines.mbt` へ移した。
- **セキュリティ**：
  - npm audit（npm、bench）と Dependabot は 0 件。
  - 【中】破線のパターンの数に上限がなく、アトラスを作る処理が長さの 2 乗で重くなった。`MAX_DASH_PARTS`（64）を超えたら実線にする。
  - 【中】グラデーションのテクスチャの行数と画素数に上限がなかった（タイル内の線の数に比例）。2048 行かつ 2^20 画素を超えたら `line-color` で描く。テクスチャを作り直すときに、解放済みのものを持ち続けていた点も直した。
  - 【低】旧式のフィルタの判定（`isLegacyFilter`、`classify`）が、入れ子の深さに上限なく再帰した。深さ 32（`MAX_EXPR_DEPTH`）で打ち切る。それより深いものはエンジンがパス付きで拒む。
- **性能**（main で測った）：
  - `worker:browser` の `process_tile` の中央値は、Chromium 7.44 / Firefox 10.28 / WebKit 8.16ms。15.2 の時点（7.30 / 9.90 / 7.92ms）より +2〜4% で、出力は 77.4MB のまま。
  - `render` のフレームの CPU 時間（vsync の上限あり）は変わらない（パン 0.56ms）。
  - 今回の整理は熱い経路を変えていない。
- 大きさ：メイン 84.4 → 84.6KB（輪郭を state ごとに描くため）。

## Phase 15.4：線のグラデーション（`line-gradient`、`lineMetrics`）（2026-11-03）

状態：**完了**。

- **GeoJSON タイラー**：geojson-vt 6.3.0 の line metrics を移植した。
  - 線は 1 本ずつ地物になる（MultiLineString も分ける）。切った断片は、元の線のどこからどこまでかを持つ。
  - タイルの地物は `geojsonvt_clip_start` / `geojsonvt_clip_end` を属性として持つ。
  - `npm run geojson:golden` に lineMetrics の組を足した。切れ目の値まで比べて、8148 タイルで差は 0。
- **スタイル**：`line-gradient` を読む。`["line-progress"]`（`Expr::LineProgress`）はほかのプロパティでは Invalid、データで変わるグラデーションも Invalid にした（MapLibre と同じ）。GeoJSON ソースの `lineMetrics` は boolean でなければ Invalid。
- **ワーカー**：グラデーションのレイヤーは、頂点ごとに線の長さに対する割合を記録する。鋭い角の分割も MapLibre と同じ。さらに、線ごとの行とその切れ目、最も長い線の長さをパックする（`LAYER_ENTRY_WORDS` 15 → 17）。
- **メインスレッド**：MapLibre の `renderColorRamp` を移植した（メッシュごとに作り、式が変われば作り直す。ステップの勾配は MapLibre と同じく線の長さで幅を決める）。描画は line_gradient シェーダー。
  - 色の勾配の評価は `JsProps` の `progress` を通す。最初に別の `FeatureContext` の型を作ったところ、15.2 で大きくなった `Expr::eval` がもう 1 つ実体化され、メインが gzip で 24KB 増えた（84.4 → 108.6KB）。そのため、評価の型は 1 つに保つ。
- **`npm run style:golden`**：新しい場面 `gradients`（補間で端が半透明のもの、ステップのもの、タイルの境界をまたぐ線）は平均 0.056 / p99 1。差は 1 区間の縁のアンチエイリアス（最大 17）で、色は一致。ほかの場面は変わらない。
- example：東京駅の周りの散歩道を、グラデーションで描いた（「散歩道」グループ）。
- 大きさ：メイン 82.9 → 84.4KB、表示ワーカー 79.8 → 81.7KB、GeoJSON ワーカー 26.5 → 27.4KB。
- 未対応：`line-dasharray` との組み合わせ（MapLibre の line_gradient_sdf）は、グラデーションだけを描く。ベクトルタイル（line metrics のない線）は、タイルの中の線ごとに 0 から 1 で描く。

## Phase 15.3b：線の距離と破線（`line-dasharray`）（2026-11-03）

状態：**完了**。

- MapLibre の破線を移植した。
  - tess は、破線のレイヤーだけ、頂点ごとに線の始まりからの距離（MapLibre の `linesofar`）を記録する。鋭い角（75° 以上）の前後に点を足し、長い線は距離を 0 からやり直す。どちらも MapLibre の line bucket と同じ。
  - ワーカーは距離を頂点ごとの u16 でパックする（`LAYER_ENTRY_WORDS` 13 → 15）。破線のレイヤーがバッファーを共有するのは、破線のレイヤーとだけ。破線でない線の出力は変わらない（エントリーが 8 バイト増えるだけ）。
  - メインスレッドは MapLibre の `LineAtlas`（SDF の破線テクスチャ）を移した。バイト単位で一致する（7 パターンのハッシュで確かめた）。描画は line_sdf シェーダー。
  - パターンと `line-floorwidth` は整数ズームで取る。縁のぼかしは、そのパターンと 1 ズーム隣のパターンの短い方で決める（静止時の MapLibre のクロスフェードと同じ）。ズームの間のクロスフェードのアニメーションはしない。
  - データで変わる破線は Unsupported（パス付き）のまま。
- **`npm run style:golden`**：新しい場面 `dashes`（鉄道の白い破線、丸い端の点線、境界）は平均 0.034 / p99 0、`dashes-zoomed`（小数ズーム、ズームで変わるパターンと幅）は 0 / 0。ほかの場面は変わらない。
- example：境界線を破線にした。
- 大きさ：メイン 75.7 → 75.9KB、表示ワーカー 70.6 → 70.9KB（15.10 の後。破線の分はメイン +2.2KB：アトラス、シェーダー、破線の描画）。

## Phase 15.3a：塗りの輪郭（`fill-antialias`、`fill-outline-color`）（2026-11-03）

状態：**完了**。15.3 は 2 つに分けた（15.3a 輪郭、15.3b 線の距離と破線）。

- MapLibre の塗りの輪郭を移植した。
  - MapLibre は、塗りの輪の辺を 1px の線（`gl.LINES`）で描く。線の位置と画素の中心の距離で淡くする（fill-outline のシェーダー）。輪郭は塗りの後に描く。
  - 色は `fill-outline-color`（データで変わってもよい。頂点ごとの値の縁の色のスロットに入れる）、なければ塗りの色。不透明度は `fill-opacity`。
  - `fill-antialias: false` で描かない。
- tess は、輪の辺の組（閉じていない輪は閉じる辺も）を作る。パックでは、塗りの三角形の索引の後に置く（`LAYER_ENTRY_WORDS` 11 → 13）。
- **`npm run style:golden`**：
  - 塗りの場面が、平均 1.238 / p99 40 から **0 / 0**（MapLibre と完全に一致）になった。15.1a で見つけた差は、これだった。
  - 新しい場面（データで変わる輪郭の色、`fill-antialias: false` の水域）も 0 / 0。
  - 傾けた場面も 0.611 → 0.559 になった。
- **費用**（`worker:browser`、35 タイル）：
  - 出力は 74.1 → 77.4MB（+4.5%）。MapLibre も同じ線のリストを作る。
  - process_tile の中央値は、Chromium 7.39 → 7.54ms、Firefox 9.80 → 9.96ms、WebKit 7.84 → 8.06ms。
  - サイズは、メイン 73.0 → 73.5KB、表示ワーカー 69.0 → 69.4KB。
- example は、既定で輪郭が出るので、3 つとも建物の境目が MapLibre と同じに見えるようになった（設定は変えていない）。
- 既知のこと：feature-state を読む塗りのレイヤーでは、輪郭は状態ごとの範囲に分けず、レイヤーの paint で描く。状態の範囲は三角形の索引で数えているため。
- 確認：
  - tess（閉じた輪、閉じていない輪、穴）、ワーカーのパック（輪郭の索引）。
  - pack test 9/9、`export:golden`、`style:golden` の 7 つの場面。

## Phase 15.10：GeoJSON のクラスタ（2026-11-03）

状態：**完了**（`clusterProperties` を除く）。

### できたこと

- **`tiler` の `ClusterIndex`**：@maplibre/geojson-vt 6.3.0 の `cluster-tile-index.ts`（MapLibre 6.16 が使うもの。supercluster ではない）と、それが使う kdbush 4.1.0 を移植した（`tiler/cluster.mbt`、`tiler/kdbush.mbt`）。
  - 点の集め方も geojson-vt と同じ：変換と `wrap` を通す（MapLibre の buffer 128px では、経度の端から 1/4 以内の点が反対側にも複製され、クラスタの id の数え方に入る）。MultiPoint は位置ごとに 1 点。
  - kdbush の選択（Floyd-Rivest）の `log` と `exp`、緯度経度に戻す `atan` と `exp` は `@core.Trig` を通す。wasm-gc ではホストの `Math` を使い、JS とビットまで一致する。
  - 出力：タイル（列形式のタイル。クラスタの id と `cluster`、`cluster_id`、`point_count`、`point_count_abbreviated`）、`expansion_zoom`、`children`、`leaves`（FORMATS.md の「Cluster features」）。
- **スタイル**：`cluster`、`clusterRadius`、`clusterMaxZoom`、`clusterMinPoints` を受け付ける（型と負の値を検査）。`clusterProperties` は、式の map/reduce（並列 1 の 15.2）が要るので、`cluster: true` のときは Unsupported のまま（パス付き）。
- **GeoJSON ワーカー**：`load` にクラスタの設定を足し、`{type: "cluster"}` のメッセージで 3 つの問い合わせに答える。メッセージの形は検査する（id、op、int32 の範囲）。
- **facade**：`map.getSource(id)` が、MapLibre と同じ `getClusterExpansionZoom`、`getClusterChildren`、`getClusterLeaves` を持つ（Promise）。設定の導き方（`clusterMaxZoom` が 0 か未指定なら `maxzoom - 1`、`clusterMinPoints` は 2 以上、`clusterRadius` の既定 50）も MapLibre と同じ。導出と引数の検査は遅延ロードの `geojson.ts` に置いた。クラスタにしていないソースでは null、知らない id は reject。
- **example**：3 つとも、山手線の 30 駅をクラスタにしたソースを足した。円の大きさは駅の数、数をラベルにし、まとまりをクリックすると分かれるズームへ移る。

### 確認

- **`npm run cluster:golden`**（新規）：geojson-vt 6.3.0 の `ClusterTileIndex` と比べて **差 0**。
  - データ：GSI の点（記号・注記・標高点）、世界の MultiPoint、乱数の点 2 万（塊、±180 越え、極の近く、同じ位置）。
  - 設定：MapLibre の既定、geojson-vt の既定、半径を広げ minPoints 5、wrap なし。
  - 5280 タイル（16.9 万地物。id と属性を含む）、1.4 万クラスタの展開ズーム・子・葉（既定、`limit` と `offset`、Infinity）と、存在しない id。計 7.3 万の問い合わせ。js は全体を、wasm-gc は js とのハッシュで比べた。
  - 半径を 1% ずらすと 5.4 万件が食い違うことも確かめた（テストが空振りしていない）。
- `npm run geojson:golden` は差 0 のまま（5377 タイル）。
- **`npm run style:golden`**：新しい場面 `clusters`（3000 点、ズーム 11、`point_count` で円の色と大きさを `step`）は平均 0.061、p99 1。目では区別できない（mbmap のタイルは 4096 単位、MapLibre は 8192 単位なので、位置の丸めが 1/8 px ずれる）。ほかの場面は変わらない。
- MoonBit のテスト：クラスタの id と展開ズーム、子と葉（limit、offset、負の limit）、知らない id、`min_points` と `max_zoom`、MultiPoint、wrap と wrap なし、3000 点で各点がちょうど 1 つに入ること、`point_count_abbreviated`、2 つの符号化。スタイルの検査。
- pack test：3 つの example で、ズーム 11 のクラスタが 30 駅を持つこと、3 つの問い合わせ、不正な引数の reject、クラスタでないソースの null、クリックで展開ズームへ移ること（`bench/npm/checks/clusters.mjs`）。

### サイズ

| 入口 | main | この段 |
|---|---|---|
| 表示（メイン） | 73.5KB（73494 バイト） | 73.7KB（73676 バイト） |
| `geojson.js` | 0.9KB（944 バイト） | 1.4KB（1427 バイト。ソースの設定の導出を index.ts から移した） |
| GeoJSON ワーカー | 20.3KB（20303 バイト） | 26.5KB（26537 バイト。予算 30KB） |
| 表示ワーカー | 69.4KB（69441 バイト） | 69.6KB（69567 バイト。スタイルの検査） |

- GeoJSON ワーカーの +6.2KB（wasm だけなら gzip -9 で 19.3 → 24.7KB）は、ほぼクラスタのコードそのもの。外して測ると、子と葉の問い合わせとその符号化が 0.9KB、`point_count_abbreviated` の文字列化が 0.1KB。残りは木の構築、タイル、kdbush。

### 残したもの

- `clusterProperties`（map/reduce の式。15.2 の式がそろってから）。
- `setClusterOptions`、`getClusterOptions`、`generateId`（GeoJSON ソースの `generateId` そのものが未対応）。
- 速さは測っていない（クラスタのベンチはまだない）。

## Phase 15.2：式と、旧式のフィルタ・関数の変換（2026-11-03）

状態：**完了**。メインの入口が予算 80KB を超えたため、ユーザーが予算を 100KB に引き上げた（2026-11-03、ユーザー判断。VISION §2）。

### できたこと

- **式**（`style/expr.mbt` の compile、`style/eval.mbt` と `style/ops.mbt` の eval）：
  - 算術と数学：`+ - * / % ^ sqrt log10 ln log2 sin cos tan asin acos atan min max round abs ceil floor pi e ln2`。`log10` と `log2` は MapLibre と同じく `ln(x) / LN10` で計算する。`round` は 0 から遠い方へ丸める。
  - 型：`to-number`、`to-string`、`to-boolean`、`to-color`、`typeof`、`array`（要素の型と長さ）。既存の `number`、`string`、`boolean` も MapLibre の評価エラーに合わせた。
  - 文字列：`concat`（text-field の外でも）、`upcase`、`downcase`、`length`、`slice`、`index-of`（コードポイントで数える）、`at`（配列。style-spec 26.5 の `at` は文字列を取らない）。`in` は文字列の haystack で needle を文字列にする。
  - `let` と `var`：compile のときに束縛した式に置き換える。置き換えた後の大きさを `MAX_EXPR_NODES`（4096）で抑える（`let` を重ねると指数的に大きくなるため）。
  - 色：`rgb`、`rgba`、`to-rgba`。補間 `cubic-bezier`（`@core.Bezier`）、`interpolate-hcl`、`interpolate-lab`（style-spec の `color_spaces.ts` を移植。`style/color_space.mbt`）。数の配列の補間も。
  - 地物：`id`、`get`/`has` の第 2 引数の `["properties"]`。オブジェクト値は未対応（Unsupported のまま）。
- **MapLibre の評価エラー**：`Value::Failed` で表す。上の式へ伝わり、プロパティは既定値になる（フィルタは偽）。比較 `<` の型違い、`!`・`all`・`case` の真偽値でない値、補間の入力が数でない・NaN、`at` の範囲外などが該当する。
- **型の注釈**：compile は、型を求められた所で MapLibre のパーサーと同じく、型が `value` の式を assertion（色は `to-color`）で包む。`match`・`case`・`step`・`interpolate` の 2 つ目以降の出力は、最初の出力の型に合わせる。`coalesce` は引数を包まず、全体を包む。比べられない型の `==` などは Invalid にする。
  - これで、`fill-color: ["get", "color"]` のような文字列の色が描ける（以前は黒）。
- **ホストの関数**：`FeatureContext` に `id`、`trig`、`number_text`（`String(number)`）、`text_number`（`Number(string)`）を足した（`pow` は `trig` に入れた）。
  - メインスレッドはブラウザの `String`、`Number`、`Math` を使う。
  - 表示ワーカーは `host.*` の import（`wasmio/js/host.mjs` の `hostText`。1 回に UTF-16 の 1 単位を渡す）を使う。MoonBit の `Double::to_string` をワーカーに入れると 3.9KB 増えたため（測定）。文字列から数への変換では、出力領域を作業場所にできない（タイルをパックしている途中のため）。
- **地物の id**：グループ方式の paint が `["id"]` を読むときは、グループのプロパティの `$id`（`@style.FEATURE_ID_KEY`）に入れる（FORMATS.md）。
- **旧式の変換**（`npm/src/legacy.ts`、遅延ロードの `legacy.js`、予算の行を足した。3.6KB／5KB）：
  - style-spec 26.5.0 の `convertFilter` と `convertFunction`（`convertTokenString` も）を移植した。プロパティの型・既定値・補間の有無の表は style-spec の参照から作った。
  - 例外が 1 つある。段が 1 つの interval 関数で、style-spec の変換は 0 より上の出力を 0 にしてしまう（`fixupDegenerateStepCurve` の書き間違い）。MapLibre 自身は関数をそのまま評価するので、そちらに合わせて同じ値を繰り返す。
  - facade は、`isLegacyFilter` と `hasLegacy`（`style.ts`、メインに入る）で旧式があると分かったときだけ `legacy.js` を読む。対象は setStyle、`#edit` を通る編集（読み込みの後で編集をやり直す）、`queryRenderedFeatures` と `querySourceFeatures` の `filter`。エンジンは式だけを見る。`getStyle()` は元のまま返す。
  - これまで `["==", "class", "x"]` は 2 つのリテラルの比較になり、常に偽だった。いまはエンジンに直接渡すと Invalid（型の違う比較）になり、facade を通せば変換される。
- **example**：3 つとも、標高点の半径を `["+", 2, ["*", ["sqrt", ["max", ["to-number", ["get", "alti"], 0], 0]], 0.3]]` にした（`examples/shared/style.js`）。
- pack test の「対応していない式」の例を `["sqrt", 2]` から `["number-format", 2, {}]` に替えた。

### 確認

- **`npm run expression:golden`**（新規、`bench/style/expressions.mjs` と `expression-cases.mjs`、`bench/expr` の js ビルド）：
  - style-spec 26.5.0（maplibre-gl 6.16.0 が使う版。bench の node_modules にあるものを使い、依存は足していない）の `createExpression` と比べた。
  - 対象：式 183、GSI の地物 2686（注記、記号、等高線、鉄道、道路、建物などと、端の場合を作った 14）、ズーム 5 つ。評価は 278 万回。
  - 結果：**値の違いは 0**。色は straight RGBA で 1e-9 以内（MapLibre は内部で premultiplied にして戻すため）。
  - MapLibre がパースで拒み、mbmap が評価時に Failed にする定数の式が 3 つある（定数の畳み込みをしないため。`MAPLIBRE_REJECTS` に書いた）。
  - 旧式のフィルタ 31：変換が style-spec と一致し、`featureFilter` と同じ地物を選ぶ。
  - 旧式の関数 21：変換が style-spec と一致し（上の例外 2 つを除く）、値は MapLibre の `StylePropertyFunction` の評価と一致する（null・エラー・NaN は既定値として比べた）。
- **`npm run style:golden`**：新しい場面 2 つ。
  - `expressions`：算術、`to-number`、`interpolate-hcl`、`let`/`var`。平均 0.003、p99 0。
  - `legacy`：旧式のフィルタと関数（`legacy.js` の読み込みを含む）。平均 0.002、p99 0。
  - ほかの場面は変わらない。
- MoonBit のテスト（4 つのバックエンド）：演算子ごと、エラーの伝わり方、`let`/`var` と `MAX_EXPR_NODES`、パース時の型の誤り、色空間、`js_number`。ワーカー（`id`、ホストのフックを通る変換、グループの `$id`）、map（`JsProps` のフック、NaN は既定値）。
- npm test（`legacy.test.ts` を追加）、pack test 9/9、`query:golden`、`ui:golden`、`export:golden`。
  - `query:golden` の state の場面で 1 点だけ画素が違う（319/320）。main（5e5c57c）でも同じなので、この段の変更によるものではない（15.3a の輪郭の後から）。
  - 15.3b の上でも、破線の場面は変わらない（`dashes` 0.034 / 0、`dashes-zoomed` 0 / 0）。`line-dasharray` が `Failed` になったときは実線で描く（配列でない値と同じ）。
- **性能**（`worker:browser`、35 タイル、main 5e5c57c と同じマシンで続けて測った）：process_tile の中央値は、Chromium 7.36 → 7.30ms、Firefox 9.88 → 9.90ms、WebKit 7.98 → 7.92ms。違いはぶれの範囲で、出力も同じ（77.4MB）。

### サイズ

測ったのは main 5e5c57c の上（15.3b の破線を入れる前）。15.3b の上に rebase した後は、メイン 82.9KB（82940 バイト）、表示ワーカー 79.8KB。

| 入口 | main（5e5c57c） | この段 | 予算 |
|---|---|---|---|
| 表示（メイン） | 73.7KB（73676 バイト） | 80.7KB（80712 バイト） | 100KB（80KB から引き上げ） |
| 表示ワーカー | 69.6KB | 78.5KB | 100KB |
| `legacy.js`（新規） | — | 3.6KB | 5KB |

- メインの +7.0KB の内訳（エンジンの js を esbuild で縮めて gzip、機能を外して測った）：
  - `Call` の演算子（算術、文字列、配列、色）：2.0KB。うち文字列・配列・色が 1.5KB。
  - HCL と Lab の補間：1.0KB。
  - `to-*` の変換：0.4KB。
  - 残り約 2.8KB：型の注釈、`let`/`var`、エラーの伝わり方、`FeatureContext` のフック、`Trig`。
  - facade（旧式の判定と `legacy.js` の読み込み）：約 0.8KB。
- 試して効いたもの：compile のエラーを `raise` から「最初のエラーを記録する」方式にした（js の出力で Result の包みがなくなり、1.0KB 減）。
- ワーカーの +8.9KB は compile と eval（wasm-gc は js より大きくなる）。予算内。
- 示した選択肢（予算を上げる、評価をワーカーへ寄せる、一部をメインから外す）から、ユーザーは予算の引き上げ（80 → 100KB）を選んだ。

### 既知の違い・まだのもの

- `upcase`/`downcase` は、Latin（ASCII、Latin-1、拡張 A、全角）とキリル文字だけを変換する。ギリシャ文字（語末のシグマを含む）などはそのまま。
- `to-color` は mbmap の `parse_color` を使う（16 進、`rgb()`/`rgba()`、`black`/`white`/`transparent`）。CSS の色名、`hsl()`、% や空白区切りの書き方は、まだ読めない。
- 定数の畳み込みはしない。MapLibre がパースで拒む定数の式（範囲外の `rgb` など）は、mbmap では評価時に Failed になる。
- 文字列型のプロパティ（MapLibre は `to-string` で包む）は、mbmap にはまだない。
- `object`、オブジェクトのリテラル、`properties` 単独、`get`/`has` のオブジェクト引数、`collator`、`format`、`number-format`、`within`、`distance`、`global-state`、`image`、`split`/`join` などは、引き続き Unsupported。
- 旧式の変換の対象はレイヤーの filter、paint、layout だけ。`light` などの関数は変換しない。

## Phase 15.1b：データで変わる paint を頂点属性に（2026-11-03）

状態：**完了**。

### 設計

- 対象：fill、line、circle の、データで変わる paint（色、不透明度、太さ・半径、縁の色・不透明度・太さ）。ただし feature-state を読むレイヤーは除く。
- 値の持ち方：一番外がズームの `interpolate` か `step` の式は、**すべての折れ点の出力**を地物ごとに頂点に持つ。そうでない式は 1 つだけ持つ。
  - MapLibre は `z` と `z+1` の 2 つを持ち、ソースの最大ズームを超えるとタイルを読み直す。mbmap は読み直さないので、折れ点をすべて持つことで、z14 のタイルを z18 で見ても正確になる。
- 描画：描くときに、いまのズームを挟む 2 つの折れ点を、属性のオフセットで選んで混ぜる（`u_t`）。一定の値も同じ属性に `vertexAttrib*` で渡す。そのため、シェーダーの種類は増えない。
- 並び：頂点ごとの値の並びは `style` の `StyleLayer::vertex_paint` が決める。ワーカーとメインスレッドの両方がこれを使う。形式は FORMATS.md の「Vertex paint」。
- 共有ジオメトリ（同じ形のレイヤー）は、これまでどおり共有する。頂点ごとの値は、レイヤーごとの別のバッファに置く。
- `same_tiles` は、タイルに焼き込んだ paint も比べる。
- グループ方式のまま残したもの：feature-state を読むレイヤー、symbol、fill-extrusion。

### 結果

- **`npm run style:golden`**：MapLibre と画素で比べて、新しい場面が両方とも一致した。
  - 連続値の円：ラベルの点の `arrngAgl`（角度で、数百の値がある。以前の 64 グループの上限を超える）で、半径と色を補間し、縁を段階で付ける。平均 0.001、p99 0。
  - ズームとデータで変わる道路の太さ：z14 のタイルを z16.5 で見る。平均 0.001、p99 0。
  - 既存の線の場面も、0.045 から 0 になった。
- **出力とワーカーの時間**（`npm run worker:browser`、35 タイル、ベンチのスタイル）：

  | | main | この段 |
  |---|---|---|
  | 出力の合計 | 59.2MB | 74.1MB（+25%） |
  | process_tile 中央値 Chromium | 6.59ms | 7.39ms |
  | 〃 Firefox | 8.64ms | 9.80ms |
  | 〃 WebKit | 7.06ms | 7.84ms |

  - ベンチのスタイルでデータで変わるのは、建物の色（頂点 4 → 8 バイト）、道路の色と、折れ点 2 つの太さ（8 → 20 バイト）、記号の円の色。増えた分は、頂点ごとに値を持つ方式そのものの費用（MapLibre も同じ持ち方）。
  - 試したこと：
    - 1 つしかない値は 1 つだけ持つ（2 つ持つ形から変えた。81.7 → 74.1MB）。
    - 地物の値を頂点の数だけ繰り返す処理を、倍々の `memory.copy` にした。Chromium で 7.70 → 7.39ms。Firefox と WebKit ではぶれの範囲。
- **描画**（`node render/run.mjs`、Chromium）：初めての idle は 130.6 → 131.1ms で変わらない。フレームの CPU 時間の p50 は同じか少し速い（ズームイン 0.465 → 0.385ms）。グループごとの描画呼び出しがなくなったため。
- **サイズ**：メイン 71.2 → 73.0KB、表示ワーカー 67.2 → 69.0KB。メインの残りは 7.0KB。
- 計測には、main を別の git worktree でビルドして使った（AGENTS §2 の Parallel work）。

### 確認

- MoonBit のテスト：
  - `vertex_paint` が取り出すもの（スロットの順、ズームの折れ点、step、feature-state と extrusion は対象外）。
  - `position`（補間の係数、端、step）、`encode`（色の語、既定値）。
  - ワーカーのパック：頂点ごとの値、共有ジオメトリでもレイヤーごとの値、値のない別名。
  - `same_tiles`。
- pack test（9/9）、`export:golden`、`query:golden`（320/320 一致）、`ui:golden`。

## Phase 15.1a：MapLibre と画素で比べる仕組み（`npm run style:golden`）（2026-11-03）

状態：**完了**。

- `bench/style/golden.mjs` と `scenes.mjs`：場面ごとに小さなスタイルとカメラを用意する。両方のエンジンを同じページに並べ（`bench/query/index.html`）、Chromium の GPU で描いて、画素の差（チャンネルごとの平均と 99 パーセンタイル）を比べる。
- 場面ごとの上限は、測った値のすぐ上に置く。3 回続けて測り、値は毎回同じだった。

  | 場面 | 平均 | p99 | 足りないもの |
  |---|---|---|---|
  | 塗り（水域、半透明の建物） | 1.238 | 40 | `fill-antialias`：MapLibre は塗りの輪郭を既定で描くので、隣り合う建物の間に細い線が出る。mbmap は描かない |
  | 線（道路の match と太さの補間、鉄道） | 0.045 | 0 | — |
  | 円（地物の点、縁あり） | 0 | 0 | — |
  | 傾けて回す（45°、30°） | 0.611 | 19 | — |

- Phase 15 の各段は、ここに自分の場面を足し、上限を守る（完了条件）。
- 合成のスプライトは、使う段（15.5）で作る。

## 方針の更新：Phase 15（2026-11-03、ユーザー判断）

- **対応していない式やプロパティ**：Phase 15 の間は、いまのまま、スタイル全体を拒否する（未リリースなので）。Phase 15 の終わりに、まだ対応していないもの（`collator`、`within`、`number-format` など。VISION で完全互換は目指さないと決めている）の一覧を見て、拒否を続けるか、そのレイヤーを外して描くかを決める。
- **メインの予算（80KB、いまは 71.2KB）**：TS だけで済む部分（スプライトの読み込み、画像・動画・canvas のソース、カスタムレイヤー、旧式の変換）は、使うときだけ読む別のファイルにする。それでも足りなくなりそうなら、測った値を見せて相談する。
- **データで変わる paint**：**最初から頂点ごとの値（頂点属性）にする**（VISION §7 の大きな設計変更。ユーザーが承認した）。いまのグループ方式（1 タイル 64 まで）を、数値と色の paint については置き換える。
- **段階と並列**：15.1（土台）の後、3 本で並列に進める（AGENTS §2 の Parallel work）。PR は 1 本ずつ報告し、マージは順番に行う。

  | 線 | 段 | 内容 | 完了条件 |
  |---|---|---|---|
  | 土台 | 15.1a | 画素で比べる仕組み | 済み |
  | 土台 | 15.1b | データで変わる paint を頂点属性にする | 済み（#54） |
  | 本線 | 15.3 | 線の距離、`line-dasharray`、`fill-antialias` と輪郭の色 | 済み（#55、#57） |
  | 本線 | 15.4 | `line-gradient`（tiler の lineMetrics） | 済み（#59） |
  | 本線 | 15.5 | スプライト、`addImage`、模様 4 種 | 合成のスプライト（1x と 2x）で、模様の場面 |
  | 本線 | 15.6 | アイコン | 点は済み（15.6a、`labels:golden` 27/27）。線に沿うアイコンは 15.6b |
  | 本線 | 15.7 | `text-variable-anchor` | 済み（`labels:golden` 10/10） |
  | 本線 | 15.8 | 線に沿ったラベル | 位置は済み（`labels:golden` 17/17）。フレームの CPU 時間は本線で計測 |
  | 本線 | 15.9 | heatmap | 済み |
  | 本線 | 15.11 | 画像・動画・canvas のソース | 済み |
  | 本線 | 15.12 | カスタムレイヤー | 済み |
  | 並列 1 | 15.2 | 式（算術、型変換、文字列、`let`/`var`、色、補間）と、旧式のフィルタ・関数の変換 | 済み（#58） |
  | 並列 2 | 15.10 | GeoJSON のクラスタ（geojson-vt 6.3.0 の `cluster-tile-index.ts` を移植） | 済み（#56） |

## リファクタリングとセキュリティチェック：Phase 14 の後（2026-11-03）

状態：**完了**。Phase 14 で足したもの（`git diff 6413d5e..` の 77 ファイル）を見直した。

- **進め方**：セキュリティ（§8）とリファクタリング（§7）を、それぞれ読むだけのサブエージェントに並列で任せた。依存の監査、警告、DOM への書き込みの確認は自分で行った。指摘をまとめて一覧にしてから直した（AGENTS §2 の "Parallel work"）。

### セキュリティ（§8）

- 問題がなかった所：
  - `npm audit` は bench、npm、examples/react とも 0 件。Dependabot も 0 件。新しい依存は exact で固定している。
  - wasm の線形メモリは、新しい関数もすべて `@wasmio` を通る。
  - geodesic の反復は回数の上限で打ち切られる。端の値と NaN と ±Infinity を総当たりで試し、trap も遅い呼び出しもなかった。
  - プロトタイプの汚染はない（`__proto__` を持つ属性を流して確かめた）。
  - DOM への書き込みは `textContent` と `createElementNS` だけ。eval、blob のワーカー、資格情報付きの取得はない。
- 直した所：
  - 【中】`loadDem` が、タイルの枚数を全部取得してから検査していた。`sampleDem` に `tileSize: 1` を渡すと 63 万枚を取得し、`loadDem` でズーム 24 の全世界を指定すると、二重ループが 2^48 回回った。
    - 取得の前に、一辺のタイル数（16 枚まで）を検査するようにした。
    - `demZoom` は `tileSize` を 256〜4096 に限り、`maxZoom` を 24 までにする。
  - 【低】`WorkerClient` が、ワーカーの読み込みや実行に失敗すると、呼び出しを永久に待たせていた。`onerror` と `onmessageerror` で、保留中の呼び出しを reject する。
  - 【低】geodesic のワーカーが、`step` に数値以外を受け付け、有限でない座標に誤った文言で失敗していた。どちらも引数の検査で断る。
  - 【低】`precision` は 0〜15 に収める（`toFixed` の RangeError を避ける）。
- 記録だけにした所：
  - 結合の線つなぎは二乗の計算量（8,000 本で 182ms）。分割は点数の積の計算量（2 万 × 2 万頂点で 1.9 秒）。どちらもワーカーの中で、入力はページ自身のもの。
  - 分割で片と元の形を対応づける一時的な属性名（`mbmap:draw-source`）を、利用者の属性がすでに持っていると上書きされる。

### 不具合

- 【高】分割・結合でできた多角形の穴を、反時計回りにしていた。塗りの分割は外周と同じ向きの輪を新しい多角形とみなすので、穴が塗られていた。保存する GeoJSON も RFC 7946 に反していた。外周は反時計回り、穴は時計回りにした（`npm test` に穴の向きのテストを足した）。
- 【中】結合でできた Multi の形に、スナップとヒット判定が何も言わずに効かなかった。輪をたどる処理を `draw/edit.ts` の純粋な関数（`paths`、`hits`、`snapOn`）にし、Multi も平らにして扱う。`npm test` で試す。
- 【中】`Draw.select` の型に `add` がなかった。`setProperties` は、値が変わらなくても取り消しの段を積んでいた（React の欄を離れるたび）。
- 【中】CI の pack test が、たまに落ちていた（PMTiles のソースの画素が背景色になる）。
  - 原因：facade が TileJSON や PMTiles のヘッダーを読んでいる間も、エンジンは（そのソースなしで）`idle` になり、facade がそれをそのまま出していた。MapLibre は、ソースを読み込んでいる間は `idle` を出さない。
  - 直し方：読み込み中は `idle` と `load` を待たせ、最後の読み込みが終わったときにエンジンが `idle` なら出す。pack test を 3 回続けて、ui:golden を 1 回走らせ、すべて通った。メインは 71.1 → 71.2KB。
- 【低】次の 3 つを直した。
  - 分割を待つ間に編集すると、その編集が失われた。いまは分割のほうを捨てる。
  - 結合の結果に形がないと、例外になった。
  - 素早く 2 回クリックすると、円が 2 つ確定することがあった。

### 性能（`npm run draw:many`：32 頂点の多角形を N 個描いた上で、作図中にマウスを 1 回動かしてから画面に出るまで。Chromium、vsync あり）

| 形の数 | 直す前 | 直した後 |
|---|---|---|
| 100 | 32.7ms | 32.4ms |
| 500 | 49.4ms | 32.5ms |
| 2000 | 99.2ms | 32.8ms |

- 原因：動きのたびに、すべての形を `setData` し直していた。
- 直し方：ソースを 2 つに分けた。確定した形のソースは、形か選択が変わったときだけ `setData` する。作図中の形、頂点、ハンドルは、小さい別のソースに置く。あわせて、状態の `set` を 1 回にまとめた（購読者が 1 回の動きで 2 回呼ばれていた）。
- 2 フレームが残るのは、マウスのイベントがフレームの頭に届くため。形の数にはよらなくなった。

### リファクタリング（§7）

- 重ねるレイヤーの追加と後始末を `addOverlay`（`npm/src/ui/overlays.ts`）にまとめた。計測と作図の両方が使う。`"mbmap:overlay"` は定数 `OVERLAY` にした。
- `overlay` の `parts_of` は、重複する点の除去に `deduped` を使う。`geodesic` の `Accumulator` を `priv` にした（.mbti に漏れていた）。
- `mbmap/draw` が外に出していた定数と関数（`CIRCLE_STEPS`、`CLOSE_PIXELS`、`rectangleRing` など）は、使う人がいないので出すのをやめた。サイズは 4970 → 4867 バイト。
- profile が、距離だけを求める呼び出しにも点列の計算をさせていたのをやめた。
- `pack-test.mjs`（1209 行）から、Phase 14 の確認（計測、断面図、作図、編集、分割）を `bench/npm/checks/geo-tools.mjs` に分けた。
- テストを足した：
  - geodesic のワーカーが断る入力（黄金テストに 4 件）。
  - 分割・結合と、種類が混ざった結合の reject、タイルの枚数の検査（pack test の analysis）。
  - `addOverlay`、`paths`、`hits`、`snapOn`、`demZoom` の引数の検査（`npm test`）。
  - `mercator_cell` の数値。
- ドキュメント：
  - AGENTS の draw の記述（サイズ、ソースを 2 つに分けたこと、穴の向き）。
  - FORMATS の circle の制限。
  - `Draw` のメソッドの説明。
  - `sampleDem` の説明：404 のタイルは 0 m になる。データがないときに NaN になる、という記述は誤りだったので直した。
- 記録だけにした所：
  - 2 つのワーカーのグルーの重複（形が違う）。
  - DEM の `MAX_GRID_SIDE` が TS 側に写しで 3 か所ある（どこの写しかは書いてある）。
  - `#snap` が動くたびに全頂点を投影する（2000 個の形でもフレームの中に収まっていた）。
  - `mbmap/draw` は 4867/5000 バイトで、余裕がなかった。**予算を 10KB に上げた**（ユーザー判断。8KB 以内に収まればなおよい）。

## Phase 15 の下調べ（2026-11-03、並列のサブエージェントで。コードは書いていない）

Phase 15 を始めるときに範囲と段階を決める材料。数値はどれも推定で、計測はしていない。

- **前提に関わる発見**：
  - 未対応の式やプロパティが 1 つでもあると、スタイル全体が読めない（`map/map.mbt` の `BadStyle`）。たとえば `icon-image`、`symbol-placement: line`、`format`、旧式の関数 `{stops}`、`cluster: true`。実際のスタイル（OpenMapTiles 系、地理院の公式スタイル）は、そのままでは描けない。
  - 一方で、知らない paint のキー（`line-dasharray`、`fill-pattern` など）は黙って無視される。
  - 旧式のフィルタ `["==", "class", "x"]` は、2 つのリテラルの比較として常に false になる。`["in", key, …]` は Invalid になる。MapLibre の `feature_filter/convert.ts` と `function/convert.ts` に当たる変換が要る。
  - データで変わる paint はグループ方式で、上限は 64（`worker/groups.mbt`）。算術式で連続値の paint（`circle-radius: ["sqrt", ["get", "pop"]]`、heatmap の weight）が書けるようになると、すぐに上限を超える。数値の paint を頂点属性にするかは、大きな設計の判断（VISION §7）。
  - メインの残りは 8.9KB しかない。全部入れると +20〜30KB と見込まれ、予算（80KB）を超える。予算を上げるか、TS だけの部分（スプライト、画像・動画・canvas のソース、カスタムレイヤー、旧式の変換）を遅延 import にするかを決める必要がある。
  - render ベンチは速度とサイズだけを測っている。完了条件の「MapLibre と並べた描画の比較」には、画素で比べるハーネスが要る。ラベルとアイコンは、画素ではなく、置かれた集合と位置で比べる。式は style-spec の `createExpression` との黄金テストが基準になる（依存に足すなら §8.1 の確認が要る）。
- **GSI のフィクスチャで試せるもの**：
  - アイコン：`symbol` の点 3419。
  - 番号の盾（`icon-text-fit`）：`transp` の `nRNo`。
  - `text-rotate`：`label` の `arrngAgl`。
  - 破線：`railway`、`boundary`。
  - 線に沿ったラベル：`contour` の `alti`（道路名はない）。
  - 模様：`waterarea`、`building`。
  - スプライトはリポジトリにない。合成して作ることを勧められた。
- **段階の案**：
  - 15.1 土台：予算と分け方、頂点属性、シェーダーと `StyleLayer` を分ける、画素の比較のハーネスを作る。
  - 15.2 式と旧式の変換。
  - 15.3 線の距離と破線。
  - 15.4 `line-gradient`。
  - 15.5 スプライトと模様。
  - 15.6 アイコン。
  - 15.7 `text-variable-anchor`。
  - 15.8 線に沿ったラベル。
  - 15.9 heatmap。
  - 15.10 クラスタ（geojson-vt 6.3.0 の `cluster-tile-index.ts` を移植）。
  - 15.11 画像・動画・canvas のソース。
  - 15.12 カスタムレイヤー。
- **並列にできそうなもの**：
  - 15.10 クラスタは、描画とほとんど重ならない。
  - 15.2 式は 15.1 の後なら並べられる。
  - 15.11、15.12 は、シェーダーを分けた後なら並べられる。
  - 線（15.3、15.4）と記号（15.5〜15.8）は、同じファイルを触るので続けて進める。

## Phase 14.5：分割・結合（2026-11-03）

状態：**完了**。これで Phase 14 の 5 段階がそろった。

### できたこと

- **`overlay.split`**（geometry.wasm）：地物を線で分ける。
  - 多角形：Clipper の、開いた線と多角形の交わりで、多角形を端から端まで横切る部分（弦）を正確に出す。輪を弦で 2 つに分けることを、弦ごとに繰り返す。
  - 穴は、それを含む片に入れる。中で終わる線と、穴に触れる線は、何も切らない。
  - 線：切る線と交わるところで分ける。点はそのまま。
  - 片は元の属性を持つ。
- **`overlay.merge`**：多角形は union、線は端点が一致するものをつなぐ（つながらないものは MultiLineString）、点は MultiPoint にする。属性は最初の地物のもの。種類が混ざると失敗する。
- どちらも 1e-7°（約 1cm）の整数の格子で計算する。geometry.wasm は 35.5 → 41.3KB（予算 50KB）。
- **`mbmap/analysis`**：`Dataset.split(lines)`、`Dataset.merge()`、GeoJSON の地物のまま使う `splitFeatures`、`mergeFeatures` を足した。入口は 3.1 → 3.3KB。
- **`mbmap/draw`**（4.1 → 4.7KB、予算 5KB）：
  - `setMode("split")`：線を引くと、選んでいる形を（なければ、線が横切る形を）分ける。
  - Shift+クリックで選ぶ形を増やし、`merge()` で 1 つにする。
  - 状態に `selection` を足した。1 回の分割・結合が 1 段の取り消しになる。
  - 片と元の形の対応は、一時的な属性で取る。
  - Shift+押下は地図のボックスズームを始めてしまうので、描くモードの間は、ダブルクリックズームと一緒にボックスズームも止める。
- **example**：3 つとも「分割」のモードと「結合」の操作を足した。

### 確認

- MoonBit のテスト（4 つのバックエンド）：
  - 正方形を横切る線で 2 つに分ける（反時計回り、属性、切り口の点）。
  - 曲がった線、2 回出入りする線（3 つに分ける）。
  - 中で終わる線と外れた線（分けない）。
  - 穴を含む片、線を 2 本の線で 3 つに分ける。
  - 結合の 3 種類、種類が混ざると失敗すること。
- `npm test`：Multi の形の丸め。
- pack test（3 つの example）：
  - 矩形を分割で 2 つにする（面積の合計が元と同じ。格子の丸めで 1e-4 以内）。
  - Shift で 2 つを選んで結合し、1 つの Polygon に戻る。
  - 取り消すと 2 つに戻る。
  - 終わったあと、ボックスズームとダブルクリックズームが戻る。

### 既知の問題・まだのもの

- 結合でできた Multi の形は、選んで消すことはできるが、頂点の編集と移動はできない。
- 分割の正しさは、面積と構造で確かめている。GEOS（JSTS）など、ほかの実装との黄金テストは Phase 17（空間関係）で行う。
- 穴に触れる線では分けない。

## Phase 14.4：編集（選択、頂点、スナップ、属性）（2026-11-03）

状態：**完了**。

### できたこと

- **`mbmap/draw` の選択モード**（`setMode("select")`。入口は 2.4 → 4.1KB、予算 5KB）：
  - クリックで形を選ぶ。点と線は 40px 以内、多角形は中か辺の近く。
  - 選んだ形の頂点と中点を表示する。
  - 頂点をドラッグで動かす。中点をドラッグすると頂点が足される。頂点を右クリックで消す（線は 2 つ、多角形は 3 つより減らさない）。形の中をドラッグで全体を動かす。
  - ドラッグの間は `dragPan` を止める。エンジンはパンを動きごとに確かめるので、押した時点で止めれば地図は動かない。
  - 1 回のドラッグが 1 段の取り消しになる。終わったら座標を丸め、外周を反時計回りに直す。
- **スナップ**（`snapping`）：描くときと頂点を動かすときに、ほかの形の頂点（なければ辺の最も近い点）へ吸い付く。範囲は terra-draw と同じ 40px。
- **属性**：`setProperties(id, properties)`（null でキーを消す、`mode` は変えない、取り消せる）、`select`、`deleteSelected`。
- 編集の計算は import のない `npm/src/draw/edit.ts` に置いた（頂点、中点、移動、挿入、削除、平行移動、線分の最も近い点、多角形の内外）。
- **example**：3 つとも「選択」を足した。
  - 選んだ形の「名前」「メモ」を編集できる。変更は確定したとき（Enter か、欄を離れたとき）に入るので、1 回の編集が 1 段の取り消しになる。
  - Delete か Backspace で、選んだ形を消す。Escape で選択を外す。
  - React の一覧から形を選べる。

### 比較（`npm run draw:golden` に足した。terra-draw の select mode と、snapping の toCoordinate）

- 正方形を描き、次の操作を両方で同じに行った。結果の頂点の数は同じで、座標の差は 1.9px 以内だった。
  - 選ぶ、頂点のドラッグ、中点のドラッグ、右クリックでの頂点の削除、全体のドラッグ。
  - terra-draw のドラッグは少し動いてから始まるので、その間に MapLibre が数 px パンする。この差はそのため。mbmap は押した時点からドラッグになる。
  - そのため、比較は手順ごとに新しいページで行う。
- スナップ：2 つ目の多角形の頂点を、1 つ目の頂点の 10px 横でクリックした。両方とも、1 つ目の頂点の座標そのものになった（差 0）。

### 確認

- `npm test`：編集の関数（閉じた輪の始点を動かすと終点も動く、頂点の数の下限、中点、平行移動、線分の最も近い点、内外判定）。
- pack test（3 つの example）：
  - 頂点のドラッグで、その頂点だけが動き、地図の中心は変わらない。
  - 中点のドラッグで頂点が 1 つ増え、右クリックで元に戻る。
  - 全体のドラッグで、すべての頂点が東へ動く。
  - 点が、10px 以内の多角形の頂点へスナップする。
  - 名前を入れて確定し、取り消すと消える。
  - Delete で選んだ形が消える。
  - 終わったあと `dragPan` が戻る。

### 既知の問題・まだのもの

- 地図の地物（タイル）へのスナップはまだない。描いた形どうしだけ。
- 多角形の穴は、描くことも編集で足すこともまだできない。
- 回転と拡大縮小（terra-draw の select mode にある）は作っていない。
- `mbmap/draw` は 4.1KB で、予算 5KB に近い。14.5 で足りなくなったら、予算を見直すか、編集の部分を別のファイルに分けるかを相談する。

## Phase 14.3：描画（`mbmap/draw`）（2026-11-03）

状態：**完了**。

### `setData` の遅れ（決めること：作図中の図形の描き方）

- 測り方（`npm run draw:setdata`、`bench/draw/run.mjs`）：
  - 国土地理院のタイルの上に、10〜5000 頂点の多角形と頂点の点を GeoJSON ソースで描く。
  - 頂点を 1 つ動かして `setData` し、`idle`（その更新が画面に出たフレーム）までの時間を測る。
  - Chromium、Metal、vsync あり、各 40 回。
- **最初は MapLibre より 1 フレーム遅かった**：

  | 頂点 | mbmap（直す前） | MapLibre 6.16 |
  |---|---|---|
  | 10〜5000 | 中央値 33.3ms | 中央値 16.6ms |

  - 頂点の数にはよらなかったので、処理の量ではなく、待ちの問題だった。
  - メッセージを追うと、GeoJSON のワーカーの読み込みは 3.5ms で終わっていた。ところが、タイルの要求は次のフレームの描画で出していた（約 11ms 待つ）。そのため、結果はその次のフレームで描かれていた。
- **直した**：`Map::reload_source` で、そのソースのタイルをすぐに要求する（GeoJSON のワーカーは、タイルの要求を読み込みの後に処理する）。
  - 直した後は 10〜5000 頂点のどれも中央値 16.5〜16.6ms（p95 17.1〜18.2ms）。MapLibre と同じ、次のフレームで出る。
  - vsync を外した計測は、ヘッドレスのフレームの間隔が乱れて意味のある数にならなかったので、やめた。
- **決定**：作図中の図形も `setData` で描く（別の速い経路は作らない）。

### terra-draw（bench の開発用の依存、AGENTS §8.1 の確認）

- `terra-draw` 1.37.0 と `terra-draw-maplibre-gl-adapter` 1.5.0 を入れた（どちらも 2026-10-06 公開、`--save-exact`）。
  - MIT ライセンス。作者本人が保守している。週 56 万（アダプタは 32 万）ダウンロード。
  - 依存なし、インストール時のスクリプトなし、公開されている脆弱性なし（`npm audit` 0 件）。
  - 最新の 1.39.0 は公開から 6 日しかたっていなかったので、2 週間以上たったものにした。
- 配布物には入らない。比較（`npm run draw:golden`）だけに使う。

### できたこと

- **`mbmap/draw`**（新しい入口 `draw.js`、2.4KB）：`createDraw(map, { geodesic })`。
  - モードは点、線、多角形、矩形、円、フリーハンド。クリックの仕方と閾値は terra-draw に合わせた（閉じるのは 40px 以内、フリーハンドは 20px ごと、円は 64 点）。
  - 状態は `mode`、`features`、`drawing`、`vertices`、`canUndo`、`canRedo`。
  - 操作は `setMode`、`finish`、`cancel`、`undo`（描いている途中は最後の頂点を消す）、`redo`、`add`、`remove`、`clear`。
  - 座標は小数 9 桁に丸め、外周は反時計回りにする（terra-draw と RFC 7946 に合わせた）。
  - 描くのは自前の GeoJSON ソースで、レイヤーに `mbmap:overlay` の印がある。描いている間はダブルクリックのズームを止め、カーソルを十字にする。
- **`mbmap/geodesic` の `circle`**：楕円体の上の円。黄金テストに 1,000 件足し、geographiclib の `Direct` とビット単位で一致した（合計 73,014 件）。
- **example**：3 つとも「作図」の欄を足した。
  - HTML と Web Component はボタンの並びと説明の 1 行。React はつながったツールバーと、描いた図形の一覧（1 つずつ消せる）。
  - Enter で確定、Escape で取り消し、⌘Z / Ctrl+Z で取り消し、Shift 付きでやり直し。日本語入力の変換中のキーと、入力欄の中のキーは無視する。
  - GeoJSON で保存できる。
  - 作図と計測は、どちらかを始めるともう一方をやめる。どちらかをしている間は、クリックで地物を識別しない。

### 比較（`npm run draw:golden`、同じクリックを mbmap/draw と terra-draw に、Chromium で）

| モード | 結果 |
|---|---|
| 点・線・多角形 | 座標が一致（差 0） |
| 矩形 | 4 つの角が一致 |
| 円 | 65 点どうし。半径は 260.40m と 260.05m（terra-draw の `globe` は球、mbmap は WGS84。差 0.13%） |
| フリーハンド | 17 点と 18 点（terra-draw は始点を重ねて持つ）。始点は一致 |

### 確認

- `npm test`：矩形の角、モードごとの形、頂点の数の判定、反時計回り、丸め。
- pack test（3 つの example）：
  - 多角形を最初の頂点で閉じる（反時計回り）。
  - 線を Enter で確定し、もう 1 本を Escape で取り消す。
  - 円を 2 回のクリックで描く（65 点）。
  - 取り消しとやり直し。
  - 描いている間はクリックで識別しない。
  - 計測を始めると作図をやめる。
  - 全部消したあと、ダブルクリックのズームが戻る。

### 既知の問題・まだのもの

- 頂点の編集、選択、スナップ、属性は 14.4。分割・結合は 14.5。
- タッチの操作はまだ確かめていない（クリックのイベントだけを使っている）。

## Phase 14.2：断面図（2026-11-03）

状態：**完了**。

### できたこと

- **`analysis`**：
  - `Grid::sample`：セルの中心（i + 0.5）の間を双一次で補間する。端のセルは境界まで伸ばす。格子の外と、2×2 の窓にデータのないセルがあるところは NaN。どれも GDAL の `-r bilinear` に合わせた（GDAL で確かめた）。
  - `mercator_cell`：経緯度を、ウェブメルカトルのタイルを並べた格子のセルの位置にする。
  - 解析のワーカーに `grid_sample` を足した。格子のズームとタイルの位置は `loadDem` のときにワーカーの中に覚えておき、ページからは受け取らない。
- **`mbmap/analysis`**（2.7 → 3.1KB。ワーカーは 26.5 → 27.0KB）：
  - `DemGrid.sample(positions)` を足した。
  - `sampleDem(tiles, positions, { encoding, maxZoom })`：位置を覆うタイルを、1 つの格子（一辺 4096 セル）に収まるいちばん深いズームで読み、標高を返す。ズームの選び方は `npm/src/dem-zoom.ts`。
- **`mbmap/ui` の `createProfile`**（単体で 0.9KB）：
  - 線を渡すと、測地線に沿って約 `samples` 個（既定 200）の点を取り、距離と標高、最高・最低、登りと下りの合計を出す。
  - `highlight(distance)` で、グラフの上のポインタが指す点を選ぶ。
  - 測地線の計算（`measure`）と標高（`elevation`）はページが渡すので、`mbmap/ui` はどちらも含まない。地図も取らない。
  - 古い結果は捨てる。標高を読めなかったときは `error` に入る。
- **example**：距離を測り終えると、その線の断面図が出る。
  - グラフは SVG。HTML と Web Component は数字を表に、React はグラフの下に 1 行で並べる。
  - グラフの上のポインタが指す場所に、地図の上の点（`map.track`）が付いてくる。
  - 標高は、スタイルが描くのと同じ国土地理院の標高タイルから読む。

### 黄金テスト（`npm run terrain:golden` に足した。GDAL 3.13 の `gdallocationinfo -r bilinear -wgs84` と比較）

- 富士山の 1024×1024 の格子を EPSG:3857 の GeoTIFF（Float64）にして比べた。
  - 2,120 点：内側 2,000、上端と右端の近く 100、格子の外 20。
  - 差は最大 4.7e-9 m。経緯度からの変換が、GDAL は PROJ、こちらは `mercator_cell` という違いによる。
  - 値がない点も一致した。
- 先に小さな格子で GDAL の約束を確かめた。端は端のセルの値。範囲の外は値なし（空の行）。2×2 の窓に重みが 0 でも no data があれば no data。

### 確認

- MoonBit のテスト：`Grid::sample`（GDAL で確かめた値、端、外、データのないセル）と `mercator_cell`。
- `npm test`：最高・最低・登り・下り（データのない点を飛ばす）、いちばん近い点、`demZoom`。
- pack test（3 つの example）：測った線の断面図が出ること。
  - 点の距離が 0 から線の長さまで増えていくこと。
  - どの点にも標高があること。
  - グラフの上にポインタを置くと、地図の上の点がその場所（`map.project` と同じ位置）に出ること。
  - 「消す」で断面図も消えること。

### 既知の問題・まだのもの

- 日付変更線を越える線は、経度を ±180 を越えて続けて数えるので、`sampleDem` のタイルの範囲を正しく取れない。
- `sampleDem` は、タイルの大きさを 256 px と仮定してズームを選ぶ（`tileSize` で変えられる）。

## Phase 14.1：測地線の計測（`mbmap/geodesic`、計測のコントローラ）（2026-11-03）

状態：**完了**。

### できたこと

- **`geodesic`**（純粋な MoonBit、4 つのバックエンドでテスト）：geographiclib-geodesic 2.2.0 の移植。
  - `Geodesic`：逆問題（距離、両端の方位角、弧長、測地線と赤道の間の面積 S12）と順問題。楕円体は既定で WGS84。
  - `GeodesicLine`：距離か弧長で線上の点を求める。経度を ±180 を越えて続けて数える `unroll` もある。
  - `PolygonArea`：多角形の周囲と面積（極を囲むもの、日付変更線を越えるものも）、折れ線の長さ。
  - `measure_path`（長さ、面積、各頂点までの距離）と `densify`（測地線に沿って点を足す。地図に曲線として描くため）。
  - `@core.Trig` に `cbrt` と `atanh` を足した（GeographicLib が使う。wasm-gc ではホストの `Math` を使う）。
- **`mbmap/geodesic`**（新しい入口 `geodesic.js` 1.0KB、`geodesic-worker.js` と `geodesic.wasm` で 11.8KB）：`inverse`、`direct`、`measure`（`step` を渡すと描くための点列も返す）、`terminate`。
  - 入口の Worker を呼ぶ部分を `npm/src/worker-client.ts` にまとめ、`mbmap/analysis` もそれを使うようにした。
- **`mbmap/ui` の `createMeasurement`**（単体で 1.4KB）：地図をクリックして距離と面積を測る。
  - 状態は `mode`、`positions`、`pointer`（マウスについてくる仮の頂点）、`length`、`area`、`segments`、`finished`。操作は `start`、`add`、`undo`、`finish`（ダブルクリックでも）、`clear`。
  - 計算は、ページが渡す `mbmap/geodesic` の `measure`（座標のコントローラが `transform` を受け取るのと同じ形）。そのため `mbmap/ui` は測地線の計算を含まない。
  - 計算は 1 つずつ走らせ、その間に来た変更は最新の 1 つだけ計算する。
  - 線と面は自前の GeoJSON ソース（`mbmap-measure`）に `setData` で描く。レイヤーに `mbmap:overlay` の印を付けたので、背景地図を替えても残る。測っている間はダブルクリックのズームを止める。
  - `formatLength`、`formatArea` を足した。
- **example**：3 つとも「計測」の欄を足した。
  - HTML と Web Component はボタンの並び、React はつながったツールバー。読み取りの行は共通（`examples/shared/measure.js`）。
  - 測っている間は、クリックで地物を識別しない。

### 黄金テスト（`npm run geodesic:golden`、geographiclib-geodesic 2.2.0 と Node で比較）

- 72,014 件で、すべての値がビット単位で一致した（`Object.is`）。
  - 逆問題と順問題：無作為 2 万組、短い線（1e-9〜0.1°）、ほぼ対蹠点、極、子午線、赤道、端の場合（同じ点、-0、範囲外の緯度、NaN）。
  - 多角形と折れ線（3〜30 頂点、0.01〜60°、極を囲むもの、時計回りのもの）2,000 ずつ。
  - 点を足した経路 2,000。
- 気づいたこと：Node 22 と Chromium では、`Math` の結果が最後の 1 ビットだけ違うことがある（同じ頂点の長さが …363 と …366）。どちらのエンジンでも、geographiclib の JS と geodesic.wasm は一致する。そこで pack test では、期待値を同じページの中の geographiclib で計算する。

### 確認

- MoonBit のテスト（4 つのバックエンド）：GeographicLib のテストの値（逆問題、ほぼ対蹠点、扁長な楕円体、順問題、極を囲む多角形、`reverse` と `sign`、折れ線）、`measure_path`、`densify`（日付変更線を越える、上限）。
- `npm test`：長さと面積の書き方。
- pack test（3 つの example）：
  - 2 回のクリックとダブルクリックで線を測る。ダブルクリックでズームも識別もしない。
  - 面積をパネルの「終える」で閉じる。
  - どちらの値も、同じページの geographiclib と一致する。
  - 「消す」で描いたものが消え、ダブルクリックのズームが戻る。

### 既知の問題・まだのもの

- 頂点の編集、スナップ、属性は 14.4、描画の道具（矩形・円・フリーハンド）は 14.3。
- 作図中の描き方（`setData` の遅れ）は 14.3 で測る。計測ではマウスの動きごとに `setData` が走るが、頂点が少ないので目立つ遅れはない（数字はまだ取っていない）。
- 楕円体は WGS84 だけを公開している（JGD2011 の GRS80 との差は 0.1mm の桁）。

## 方針の更新：Phase 14（2026-11-03、ユーザー判断）

- 段階：計測を先にする。
  - 14.1：測地線の計測
  - 14.2：断面図（標高）
  - 14.3：描画（点・線・多角形・矩形・円・フリーハンド、取り消し・やり直し）
  - 14.4：編集（頂点、スナップ、属性）
  - 14.5：分割・結合（ジオメトリのモジュール）
- 作図中の図形の描き方：まず GeoJSON ソースの `setData` で作り、ドラッグ中の遅れを測ってから決める。1 フレームに収まらなければ、数字を見せて相談する。
- 測地線：GeographicLib を MoonBit に移植する。置き場所は、大きさを測ってから決めた（下の表）。**決定：新しい入口 `mbmap/geodesic`**（専用の Worker と wasm）。Phase 17 でデータを測るときは、解析の Worker も同じ `geodesic.wasm` を読める。

  | 置き場所 | 大きさ（gzip） | 計測で読むもの |
  |---|---|---|
  | 解析の wasm に入れる | 解析のワーカーが 26.5 → 33.6KB（予算 30KB を超える） | 33.6KB |
  | 解析のワーカーが遅れて読む | 10.9KB | 26.5 ＋ 10.9KB |
  | 新しい入口（採用） | 1.0 ＋ 11.8KB | 12.8KB |

- terra-draw との比較：14.3 で bench の開発用の依存に入れる（AGENTS §8.1 の確認をしてから）。

## リファクタリングとセキュリティチェック：Phase 13 の後（2026-11-03）

状態：**完了**。Phase 13 で足したもの（`mbmap/ui`、`mbmap/search`、ファサードの追加、example）を中心に、AGENTS.md §7 と §8 で見直した。

### セキュリティ（§8）

- 問題がなかった所：
  - 依存の監査（bench、npm、examples/react）と Dependabot は 0 件。
  - 地物の属性、出典、検索結果は、すべて文字列として表示している（textContent、React のエスケープ）。
  - 外部の検索プロバイダの例は、資格情報を送らず、クエリをエンコードしている。
- 直した所（低）：検索の文字列を 256 文字（`MAX_QUERY_LENGTH`）で打ち切ってからプロバイダに渡す。座標の読み取りの正規表現を短い入力に限り、外部 API に渡す URL の長さも抑える。

### 性能

- **凡例とレイヤー一覧**：ズームのたびに `getStyle()` を呼んでいた。`getStyle()` は GeoJSON のデータごとスタイルを複製するので、5 万点の GeoJSON では 1 回 25.8ms かかり、ズーム中の毎フレームに 2 回（約 52ms）走っていた。スタイルが変わったときだけ読み直すようにし、ズーム 1 回あたり 0.08ms（2 つのコントローラ込み）になった。
- **座標**：変換を 1 つずつにし、実行中は最新の位置だけを残す。マウスを立て続けに 100 回動かしたときの解析ワーカーへのメッセージが、202 通から 4 通に減った。最後の表示は同じ。

### 不具合

- レイヤー一覧の `inRange` が表示・非表示の状態まで見ていて、隠したレイヤーが「範囲外」になっていた。ズームの範囲だけを見るようにした（pack test で確かめる）。
- 現在地：位置が変わらずカメラが動かないとき、「自分で動かした」の印が残って追跡が解除されない、と考えて調べた。しかしエンジンはその場合もカメラの移動を始めて `movestart` と `moveend` を出すため、不具合は起きていなかった。`ui:golden` に「同じ位置、ユーザーのパン、追跡に戻る」の手順を足して、回帰を防ぐ（MapLibre と一致）。

### リファクタリング（§7）

- 重複をまとめた：
  - レイヤーがあるズームで表示されるかの判定（MapLibre の `isHidden`）を、`npm/src/attribution.ts` の `inZoomRange` と `layerShown` にまとめた。
  - React の example でコントローラを読むフックを `use-controller.js` にまとめた。
- ファイル分割：ファサードの公開の型を `npm/src/types.ts` に分けた（`index.ts` は 1425 → 1263 行）。
- テストを足した：`inZoomRange` と `layerShown`、レイヤー一覧の `inRange`、現在地の手順。
- 3 行を超えるコメントは、項目の一覧の 4 か所だけのまま。

## Phase 13.4：GeoSearch（`mbmap/search`）（2026-11-03）

状態：**完了**。これで Phase 13 の 4 段階がそろった。

### できたこと

- **`mbmap/search`**（新しい入口 `dist/search.js`、2.8KB）：
  - `createSearch`：入力の間引き（既定 250ms）、古い検索の取り消し（`AbortSignal`）、古い結果の破棄をコントローラが行う。
  - 状態に、矢印キーで選んでいるもの（`active`）と開閉（`open`）を持つ。ARIA の combobox と listbox に使う。
  - 選ぶと地図を動かす（点は `flyTo`、範囲は `fitBounds`）。失敗したプロバイダがあっても、ほかの結果は出る。
- **付いているプロバイダ（サーバーに問い合わせない）**：
  - `coordinates`：10 進の度（どちらの順でも）、度分秒（記号、`'` と `"`、度分秒の漢字、全角）、平面直角座標系（「第IX系 X … Y …」「9系」）、UTM（「54N …」）。投影座標は、渡された `transform` で緯度経度に直す。
  - `datasetSearch`：GeoJSON の属性を、NFKC、大文字と小文字、カタカナとひらがなをそろえて比べる。一致、前方一致、部分一致の順。
- **外部プロバイダの書き方**：example に国土地理院の地名検索（`gsiPlaceSearch`）を置いた。
  - ただし既定では使わず、`?gsi-search=1` で有効にする。この API には公開の利用規約がなく、国土地理院は「主に地理院地図からの利用を想定し、予告なく変更することがある」と答えているため（gsi-cyberjapan/gsimaps issue #113）。
- **example**：同じ検索から 2 通りの見た目を作った。HTML と Web Component はパネルの中のコンボボックス（矢印キー、Enter、Esc）、React は地図の上に浮く検索バーと結果のカード。選んだ場所には緑のピンを `map.track` で立てる。
- **日本語入力（ユーザーの指摘）**：変換を確定する Enter で、検索の結果を選んで地図が動いてしまっていた。
  - 変換中のキー（`isComposing`）と、Safari が確定の直後に送る Enter（`keyCode` 229）は無視するようにした（`examples/shared/search.js` の `onSearchKey`。React はネイティブのイベントを渡す）。
  - pack test で、どちらの Enter でも何も選ばれないことを確かめる。

### 確認

- `npm test`：
  - 座標の読み取り：両方の順、度分秒の 4 通りの書き方、南と西、範囲外の拒否。
  - 平面直角座標系と UTM の読み取り。
  - 文字の正規化と順位、データの検索（範囲の地物は範囲を持つ）。
- pack test（3 つの example）：
  - 「東京」で地点 3 つが一致、前方一致の順に出ること。
  - 10 進の度、平面直角（第IX系、元の点と 1e-6° 以内）、UTM の読み取り。
  - 入力欄からの入力、↓、Enter で東京タワーへ地図が動くこと。

### 予算

- `mbmap/search` は 5KB 以下とした（VISION §2）。いまは 2.8KB。

### 既知の問題・まだのもの

- 地名の読み（「とうきょう」で「東京」を探す）はできない。読みのデータを持たないため。
- 外部プロバイダの結果の出典表示は、作り手が行う。

## Phase 13.3：識別、座標の表示と変換（2026-11-03）

状態：**完了**。

### できたこと

- **`createIdentify`**：クリックした点の周り（既定 3px の四角）の地物を `queryRenderedFeatures` で集める。
  - 一番上を選び、feature-state（既定のキーは `selected`）で強調する。前後に送れる。
  - 遅れて届いた古い問い合わせの結果は捨てる。
- **`createCoordinates`**：マウスの位置（地図の外では中心）の座標を、複数の座標系の文字列にする。
  - 度と度分秒は `ui/format.ts`（import のない純粋な関数）で書く。
  - 投影座標系（`projected`、`utm`）は、渡された `transform` で変換する。そのため `mbmap/ui` に座標系の変換は入らない。古い結果は捨てる。
- **example**：
  - 「クリックした地物」を識別のコントローラにした。HTML と Web Component は前後のボタン、React は見つかった地物の一覧から選ぶ形。選んだ地点は青く大きく強調する。
  - 座標は、HTML と Web Component が地図の右下の欄、React がパネルの表。緯度経度、度分秒、平面直角（近い系、mbmap/analysis で変換）、UTM を出す。

### 予算（ユーザー判断）

- `mbmap/ui` は、コントローラ 1 つあたり 2KB 以下、全部入りで 10KB 以下とする（VISION §2）。13.1 で仮に置いた全部入り 5KB を、13.3 で 5.2KB と超えたため。
- size のスクリプトは、コントローラごとに `dist/ui.js` から tree-shaking した大きさも測る。最大は凡例の 1.5KB、全部入りは 5.2KB。

### 確認

- `npm test`：度分秒の繰り上がり（59.96″）、南半球と西経、UTM の帯（180° の扱いを含む）。
- pack test（3 つの example）：
  - クリックで地物が選ばれ、feature-state で強調されること。
  - マウスを動かすと、4 つの座標系の値が出ること（平面直角は「第IX系 X -35…」、UTM は「54N」）。
- 識別は `queryRenderedFeatures`（MapLibre と一致、query:golden）をそのまま使うので、別の黄金テストは足していない。

### 既知の問題・まだのもの

- 平面直角座標系の系は、原点が最も近い系を選ぶ。公式の系は都道府県の境で決まるので、境の近くでは違う系になることがある（example の簡易な選び方）。
- 文字列の座標の読み取りは、13.4 の GeoSearch で行う。

## Phase 13.2：凡例、レイヤー一覧、背景地図の切り替え（2026-11-03）

状態：**完了**。

### できたこと

- **`mbmap/ui` に 3 つのコントローラを足した**：
  - `createLegend`：レイヤーごとの見本。
    - 色が属性で決まるもの（`match`、`step`、属性の `interpolate`、`==` だけの `case`）は区分に分ける（`npm/src/ui/legend-rules.ts`、import のない純粋な関数）。
    - 区分ごとの色は、エンジンがいまのズームで評価する。描画と同じ `paint_of` を `Map::paint_at` で呼ぶ。
  - `createLayerList`：レイヤー（またはグループ）の表示と非表示。一部だけ表示（`mixed`）と、いまのズームで描かれるか（`inRange`）も持つ。
  - `createBasemaps`：背景地図の切り替え。重ねるレイヤー（既定は `metadata["mbmap:overlay"]`）を、ソースとデータごと残す（`ui/overlays.ts`）。
- **ファサード**：
  - `evaluatePaint(layerId, properties)`：その属性の地物を、いまのズームでどう描くか。
  - `setStyle` の `transformStyle` 選択肢（MapLibre と同じ形）。
- **example**：
  - 「航空写真」をレイヤーの切り替えから背景地図の切り替え（地図・写真）に移した。地点は重ねるレイヤーとして、足した印ごと残る。
  - HTML と Web Component はボタンと一覧（`examples/shared/panel.js`）、React はラジオボタン、チェックボックス、開閉できる凡例の表（`examples/react/src/panel.jsx`）。
  - 凡例のラベルは、GSI の属性の値をそのまま書く（意味を推測で付けない）。

### 黄金テスト

- `npm run ui:golden` に凡例の色を足した。bench/pages/basic のスタイルを 3 つのズームで評価し、MapLibre 6.16 が同じ属性で評価した色と、**57 項目すべて一致した**（1e-6 以内）。
- 既存の縮尺、ズームのボタン、出典、現在地も変わらず一致。

### 確認（pack test）

- 3 つの example で確かめた：
  - レイヤー一覧のコントローラでの非表示。
  - 凡例の区分（道路が `rdCtg` で 3 つに分かれる）。
  - 写真の背景地図への切り替えで、地点と足した印が最上位に残り、地図のレイヤーが消えること。
  - 地図の背景地図に戻せること。

### サイズ

- `mbmap/ui`（全コントローラ）2.3 → 4.1KB（予算 5KB）。13.3 で予算を見直す必要があるかもしれない。
- 表示の入口 70.8 → 71.0KB。

### 既知の問題・まだのもの

- 凡例は、色の式の外側の形しか見ない。ズームの `interpolate` の中の `match` のように入れ子になったもの、線の太さや円の大きさの区分は、1 つの見本になる。
- アイコンや模様（Phase 15）の見本はまだない。

## 方針の更新（2026-11-03、ユーザー判断）

- Phase 12 の完了条件（3 つの example、各 API の黄金テスト、予算）がそろったので、Phase 13 に進む。
- Phase 13 は 4 段階に分ける：
  - 13.1：土台、ナビゲーション、現在地、全画面、縮尺、出典
  - 13.2：凡例、レイヤー一覧、背景地図の切り替え
  - 13.3：識別、座標の表示と変換
  - 13.4：GeoSearch（`mbmap/search`）
- コントローラの共通の形は、`state`（変わるたびに新しいオブジェクト）、`subscribe`（解除の関数を返す）、操作のメソッド、`destroy`。

## Phase 13.1：ヘッドレス UI の土台、ナビゲーション、現在地、全画面、縮尺、出典（2026-11-03）

状態：**完了**。

### できたこと

- **`mbmap/ui`**（新しい入口 `dist/ui.js`）：
  - 公開された `Map` の API だけを使う、見た目を持たないコントローラ。
  - 共通の部分は `Store`（`npm/src/ui/controller.ts`）。コントローラはそれぞれ別のモジュールなので、import したものだけがバンドルに入る。
  - `createNavigation`：ズーム、方位、傾き、ズームできるか。操作はズーム、北を上に、ホーム。
  - `createGeolocation`：MapLibre の GeolocateControl と同じ状態の遷移（`off`、`waiting`、`active`、`background`、それぞれの `-error`、`unavailable`）。精度の範囲へのカメラの合わせ方と、精度の円の半径（画面のピクセル）も同じ。
  - `createFullscreen`：Fullscreen API と、API がないときの「疑似」全画面。
  - `createScale`：MapLibre の ScaleControl の幅とラベル。メートル、ヤード・ポンド、海里に対応する。
  - `createAttribution`：出典の一覧。
- **ファサード**：
  - 出典の表示を MapLibre と同じにした（表示中のレイヤーと地形が使うソースだけ、長さ順、他に含まれるものは除く）。これまでは全ソースを出していた。`getAttributions()` と `styledata` イベントを足した。
  - `getMinZoom(true)`（制約で決まる最小ズーム）を足した。
  - `<mb-map attribution-control="false">` で出典を自分で表示できる。
- **example**：同じコントローラから 2 通りの見た目を作った。
  - HTML と Web Component：右上の縦並びのボタンと、右下の縮尺（`examples/shared/controls.js`）。
  - React：右下の横長の帯（`examples/react/src/controls.jsx`、`useSyncExternalStore`）。
  - どれも現在地の点と精度の円を `map.track` で描き、出典を自分で表示する。
- **以前からの不具合を直した**：React の example では、`?local=1` のタイルの URL が、バンドルの `import.meta.url` を基準にしていたため 404 になっていた（GeoJSON 以外が描かれていなかった）。ページを基準にした。

### 黄金テスト（`npm run ui:golden`、MapLibre 6.16 と Chromium で比較）

- **縮尺**：6 つのカメラ（極地、南半球、傾きを含む）× 3 つの単位で、ラベルと幅がすべて一致した。
- **出典**：3 つのズームですべて一致した。
- **現在地**：差し替えた Geolocation で同じ位置を両方に渡し、12 の手順で状態とカメラ（1e-7 以内）がすべて一致した。手順は、開始、初回の位置、移動、ユーザーのパン、背景での位置、追跡に戻る、ユーザーのズーム、時間切れ、再取得、停止、再開、権限の拒否。
- **ズームのボタン**：一致した。ただし制約で決まる最小ズームでは、MapLibre は `jumpTo` 後のズームが自分の `getMinZoom(true)` と最後の 1 桁ずれ、ボタンが有効のまま残る。mbmap は無効にする。既知の差として記録した。

### 確認

- pack test：3 つの example で、縮尺と出典、コントローラでのズーム、差し替えた Geolocation での現在地への移動と点の描画を確かめた。
- `npm test`：`Store`、縮尺の丸め、距離、精度の範囲、出典の規則、`<mb-map>` の真偽値の属性。

### サイズ

- `mbmap/ui`（全コントローラ）2.3KB（予算 5KB、新設）。
- 表示の入口 70.5 → 70.8KB（出典の規則、`getMinZoom(true)`）。

### 既知の問題・まだのもの

- 方位記号のドラッグでの回転（MapLibre の NavigationControl にある）はない。
- MoonBit から使うコントローラ（VISION §6）はまだない。

## リファクタリングとセキュリティチェック（2026-11-03）

状態：**完了**。全体を AGENTS.md §7 と §8 の観点で見直した。範囲はユーザー判断で「メインの HashMap の置き換え以外すべて」。

### セキュリティ（§8）

- 問題がなかった所：
  - 依存の監査：npm audit（bench、npm、examples/react）と Dependabot がすべて 0 件。依存は版を固定し、CI の Actions も SHA で固定している。
  - 秘密情報はない。出荷コードに innerHTML、eval、new Function はない。
  - fetch は既定で資格情報を送らない。ワーカーのメッセージは形と型を確かめている。線形メモリは入出力の上限と範囲を確かめている。
- 直した所（信頼できないタイルサーバーへの備え）：
  - タイルの応答を 64MB（wasm の入力上限）までしか読まない（`worker/js/body.mjs` の `readCapped`。Content-Length と、読み込み中のバイト数で判断する）。PMTiles の範囲リクエストにも使う。
  - DEM 画像は、canvas を作る前に縦横を確かめる（1024px まで）。ラスタ画像は 4096px まで。
  - PMTiles のアーカイブのキャッシュを 16 個までにした。

### サイズ（gzip）

| 入口 | 前 | 後 |
|---|---|---|
| 表示ワーカー | 75.1KB | 67.2KB |
| GeoJSON ワーカー | 22.8KB | 20.3KB |
| 解析ワーカー | 29.2KB | 26.5KB |
| ジオメトリ | 38.2KB | 35.5KB |
| 表示の入口（メイン） | 70.4KB | 70.5KB |

- **ブラウザの `Math`**：
  - `Trig` が tiler、analysis、proj に別々にあったのを `@core.Trig` 1 つにまとめた（各パッケージは `pub using` で同じ名前のまま公開）。ブラウザの `Math` を受け取る宣言も `@wasmio.host_trig` に共通化した。
  - 表示ワーカーにも渡すようにした（スタイルの指数補間は `FeatureContext::pow`、DEM の陰影の係数、線の丸い継ぎ目）。これで core の算術関数（約 5KB）が表示ワーカーから消えた。補間は MapLibre と同じ `Math.pow` で計算することになる。
  - ジオメトリのモジュールは、Clipper2（C++ の libm）と完全に一致させるため `@math` のままにした。
- **UTF-8 の復号**：標準ライブラリの `decode_lossy` は「厳密版で試し、失敗したら寛容版」なので、復号器が 2 本入る（約 3.4KB）。1 回の走査で同じ結果を出す `@core.utf8_lossy` を書いた。
  - 2 バイト列の全通り、3・4 バイト列の境界値、疑似乱数の列で、4 つの backend とも標準ライブラリと一致することを確かめた。
  - js backend では従来どおり TextDecoder を使う。
- **wasm の分割は見送った**：表示ワーカーの中で使うときだけ要る部分は、問い合わせ 4.7KB、ラベル 2.3KB、押し出し 1.2KB、DEM 1.1KB と小さい。切り出すと mvt の復号とスタイルのフィルタ（約 8〜10KB）を両方に持つことになり、合計が増える。VISION の基準（固有のコードが約 20KB）にも届かない。Phase 15 で大きくなったら測り直す。
- まだのもの：メインの HashMap は値の型ごとに 11 通り複製されている（推定 約 3KB）。ブラウザの Map の包みへの置き換えは別の機会にする。

### 性能

- `npm run worker:browser`（タイル 35 枚の合計、main と交互に 2 回ずつ）：
  - Chromium 219 → 217ms、Firefox 292 → 291ms は誤差の範囲。
  - WebKit は 237 → 231ms で、約 2〜3% 速くなった。
- 描画の CPU 時間（`node render/run.mjs --runs=5`、比較のための計測で結果は残していない）：1 フレームは mbmap 0.42〜0.58ms、MapLibre 0.94〜1.06ms で、Phase 12 での悪化はない。

### リファクタリング（§7）

- **ファイル分割**（論理的な境目で）：
  - `core/transform.mbt` → `constrain.mbt`（MapLibre の制約）、`covering.mbt`（被覆タイル）。
  - `core/camera.mbt` → `animation.mbt`（easeTo、flyTo、ease 曲線）。
  - `style/style.mbt` → `source.mbt`（ソースの解析）。
  - `worker/processor.mbt` → `ranges.mbt`（地物の範囲）、`dem.mbt`。
- **公開範囲とテスト**：
  - `PackedTile` の書き込みメソッドと、core のメルカトル変換 2 つを非公開にした。
  - `Mat4::mul`、`Transform::resize`、`Reader::read_len_start`、`Trig` のメソッドにテストを足した。
  - 依存の向き（core ← pbf、core ← tess、core ← proj）に沿って、足りなかった import を足した。
- **コメント**：3 行を超えるコメントが 105 か所あった（ユーザーの指摘で見つかった）。
  - 移植元のライセンス表示は 3 行にし、著作者の一覧は NOTICE に任せた。関数の説明と bench スクリプトの冒頭も縮めた。
  - 残すのは、型の項目やオプションの一覧の 4 か所だけ。
  - 次から見落とさないよう `node bench/lib/long-comments.mjs` を足し、AGENTS §7.7 から案内した。
- フェーズ番号のコメント、列挙の途中のコメント、非推奨の構文はなかった。

### 確認

- 黄金テストはすべて従来どおりだった：
  - mvt 35/35、tess 35/35、GeoJSON 差 0、解析・proj・clipper は全一致。
  - query 320/320、ラスタ・PMTiles・追跡・書き出し・カメラも変わらず。
- pack test も通った。

## Phase 12.5：画面座標の追跡と画像の書き出し（2026-11-03）

状態：**完了**。これで Phase 12（地図の基本 API）の各項目がそろった。

### できたこと

- **画面座標の追跡**（決めていただいた形）：`map.track(lngLat, (p) => …)` が `{ getLngLat, setLngLat, remove }` を返す。
  - `p` は `{ x, y, covered }`。描画のたび（と登録したとき）に、地図と同じフレームで呼ぶ。登録した点はまとめて 1 回のエンジン呼び出し（`map_locate`）で計算する。
  - 位置は地形の高さを入れたもの。`covered` は MapLibre の Marker が薄くなる判定（`isLocationOccluded`）と同じ。
  - MapLibre 6.16 は地形の当たり判定を CPU のレイの行進で行っていた（`_raycastTerrain`）。これを `core/occlusion.mbt` に移植し、地形付きの `unproject` もこれで地面を探すようにした。`project` も地面の高さを入れる（MapLibre と同じ）。
  - `render` イベントを足した。
- **画像の書き出し**（決めていただいた形）：`map.toBlob({ pixelRatio, type, quality, maxSize })` が Promise<Blob> を返す。
  - `idle` を待ってから、画面外のフレームバッファに描く（画面は変わらない）。
  - GPU が一度に描ける大きさ（`MAX_RENDERBUFFER_SIZE` などの最小）か `maxSize` を超えると、部分ごとに描いて 2D canvas でつなぐ。部分は、画像全体のクリップ空間を部分のものに写す行列（`Window`）で描き、空の地平線の位置も部分の分だけずらす。
- **MapLibre と違っていた所を直した**：
  - 高さ 1m を画素に直す係数：赤道の周長でなく、MapLibre と同じ平均半径 6,371,008.8m の周長にした（0.11% の差。押し出しの高さにも効く）。
  - far plane：MapLibre の `_calculateNearFarZ` と同じ式にした。地平線近くのレイが地面に届く前に切れていた。
  - DEM の高さをタイルの縁で読むとき、隣のタイルの画素を使う（MapLibre の縁の埋め方と同じ）。
  - DEM のない所の地形は 0m の平面として扱う（MapLibre と同じ）。中心の下に DEM がないとき、カメラの中心の高さが前の場所の値のまま残っていた不具合も直した。
  - 押し出しの問い合わせで、屋根と輪郭線のように同じ深さを違う頂点から計算した結果を、丸めの範囲で同点として扱う。係数を直したら query:golden の 1 件で順序が入れ替わったため。
- **example（3 つとも）**：行き先（東京駅、富士山など）の名前を DOM のピンにして `track()` で地図に重ね、地形に隠れると薄くする。「画像を保存」ボタン（`toBlob`、2 倍の解像度の PNG）。

### 黄金テスト

- `npm run track:golden`：富士山の DEM（`gsi-dem-fuji` を Terrarium にして両方に読ませる）で、4 つのカメラ（真上、60°、75°、80°）× 約 340 地点を MapLibre 6.16 と比べた。
  - **`project` の差は最大 3×10⁻⁹px、`covered` は全点一致（隠れている地点 0〜62）、`unproject` の差は最大 1μm**。
  - 比べるのは、MapLibre が DEM から高さを取っている地点だけ。MapLibre は遠くを DEM ソースの minzoom より浅いタイルで覆って平らに描くが、mbmap は読み込んだ DEM の高さを使うため。
- `npm run export:golden`：
  - 分割して描いた画像と一度に描いた画像：3 つのビュー（ラベル付き 60°、地形と空 75°、1.5 倍で回転）で、平均 0.001、99% 点 0。違う画素は 0.03〜0.3% で、行列を一段かける丸めで線の縁が 1 階調ほど動く。
  - `pixelRatio: 1` の画像と画面：3 つとも全画素一致。
  - 2 倍のラスタと、2 倍の画面の MapLibre：平均 0.005、最大 1。
- `npm run query:golden` は 320 件すべて同じ、`npm run raster:golden` と `npm run camera:golden` も変わらず。

### 確認（pack test、CI でも動く）

- 追跡：登録時と移動後の位置、`setLngLat`、`remove` 後は呼ばれないこと、`render` イベント。
- 書き出し：2 倍で分割した画像と一度に描いた画像が同じこと、大きさ、拒む入力（`pixelRatio` が 0、大きすぎる画像）。
- example：ピンが地点の上にあること、「画像を保存」で PNG ができること。

### サイズ

- 表示の入口 67.5 → 70.4KB。`track()` と `toBlob()` で約 1.1KB、地形付きの `project`・`unproject`（レイの行進）と far plane などで約 1.9KB。
- **予算を 70KB → 80KB に上げた（ユーザー判断）**。式の拡充やアイコン（Phase 15）でも増える見込みのため（VISION §2）。
- 表示ワーカーは変わらず 75.1KB。

### 既知の問題・まだのもの

- 遠くの地形の描き方が MapLibre と違う：MapLibre は DEM ソースの minzoom より浅いタイルを平らに描き、mbmap は DEM のない所を描かない。
- 書き出しは今の表示の範囲だけ（幅と高さの指定はない）。出典表示などの DOM は画像に入らない。
- 地図のパディング（`setPadding`）は未対応のまま。

## Phase 12.4：ラスタタイル、TileJSON、PMTiles、transformRequest（2026-11-02）

状態：**完了**。

### できたこと

- **ラスタ**：`raster` のソースとレイヤー。
  - ワーカーが画像を ImageBitmap にし（premultiplied）、メインスレッドがミップマップ付きのテクスチャにする。
  - MapLibre の raster シェーダ（色相の回転、彩度、コントラスト、明るさの範囲、不透明度、`raster-resampling`）でタイルの四角形に描く。フェードはない。
  - 止まっているときは、MapLibre の `alignedProjMatrix` と同じく画素の格子にそろえる（`Transform::tile_matrix(aligned=true)`）。これを入れる前は線形補間で平均 11 の差があった。
- **TileJSON**：`url` で指すソース（vector、raster、raster-dem）を facade が補う（`npm/src/tilejson.ts`、MapLibre の `loadTileJson` と同じキー、ソースに書いた値が優先）。
  - 文書は取得してキャッシュする。`addSource` はすぐソースを足し、文書が届くまではエンジンに渡すスタイルから外す。
  - `bounds` の外のタイルは要求しない（MapLibre の `TileBounds`）。`scheme: "tms"` にも対応した。
- **PMTiles**：`url: "pmtiles://…"` をプラグインなしで読む。
  - ヘッダーは遅延読み込みの `pmtiles.js`（0.5KB）が読む。タイルはワーカーが範囲リクエストで読む（`worker/js/pmtiles.mjs`、pmtiles 4.5.0 のリーダーの移植）。
  - 信頼できない入力として、varint の長さ、エントリ数、展開後のサイズ、リーフの深さに上限を設けた。圧縮は none と gzip に対応する。
- **`transformRequest`**：オプションと `setTransformRequest`。スタイル、TileJSON、タイルの要求に効き、タイルではワーカーに `init`（URL、文字列のヘッダー、`credentials`）を渡す。既定は資格情報なし。PMTiles の範囲リクエストは対象外。
- **example**：「航空写真」レイヤー（国土地理院の全国最新写真。`?local=1` では標準地図の fixture）。最初は隠しておき、表示を切り替えられる。
- **ベンチ**：
  - fixture に国土地理院の標準地図 `gsi-std`（z14、35 タイル）を足した。
  - 開発用サーバーが Range に対応した（`byteRange` とテスト）。
  - PMTiles の書き出し（`bench/lib/pmtiles-writer.mjs`）を足した。
  - 依存に `pmtiles@4.5.0` を足した（bench の開発用のみ、比較の基準。BSD-3、作者は Protomaps。依存は fflate だけで、インストール時のスクリプトなし。npm audit 0 件）。

### 黄金テスト

- `npm run raster:golden`：標準地図を 4 種類の paint × 2 つのビューで MapLibre 6.16 と比べた。**画素の差は平均 0、99% 点 0〜1**。回転したビューの `nearest` で、テクセルの境目の 1 点だけ違う。
- `npm run pmtiles:golden`：
  - fixture から書いた 4 種類のアーカイブ（ルートのみ、リーフあり、タイルを gzip、ラスタ）を、公式の pmtiles 4.5.0 と mbmap のリーダーで読み、全タイルが元と同じだった。
  - Chromium では、PMTiles から描いた mbmap と、ファイルから描いた MapLibre が一致した（問い合わせ 4,852 地物、ラスタの画素差 0）。
  - 最初に自作のライターとリーダーで同じ Hilbert の誤り（桁の重みが 4^a でなく 2^a）を共有していて、公式との比較で見つかった。
- `npm run query:golden` は 320 件すべて同じのまま。

### 確認（pack test、CI でも動く）

- 実行時に書いた PNG、TileJSON、PMTiles の 3 経路でラスタが描かれること、`raster-opacity`、TileJSON の出典の表示、`transformRequest` によるタイル URL の書き換え。

### サイズ

- 表示の入口 65.4 → 67.5KB（予算 70KB）。
  - 削った分（問い合わせの待ち表を 1 つにまとめた、式をたどる処理を共通化）で −0.5KB。
  - 足した分（ラスタ、TileJSON、`bounds`、`transformRequest`）で +2.6KB。
- 表示ワーカー 73.5 → 75.1KB。PMTiles のヘッダー読み込みは 0.5KB（別ファイル）。

### 既知の問題・まだのもの

- ラスタのフェード（`raster-fade-duration`）はない。親タイルとの重ね描きもない。
- PMTiles は brotli と zstd の圧縮、範囲リクエストへの `transformRequest`、ETag の確認に対応していない。
- 表示の入口の残りは 2.5KB。12.5 の後に予算を相談する。

## Phase 12.3b：feature-state（2026-11-02）

状態：**完了**。これで Phase 12.3（問い合わせと feature-state）が終わり。

### できたこと

- **式**：`["feature-state", key]` と、型をそろえる `boolean`・`number`・`string` を足した。
  - `FeatureContext::state` で読み、ワーカーでは常に無い。
  - フィルターでは MapLibre と同じく拒む。`StyleLayer::reads_state` は、paint が状態を読むかを示す。
- **地物の id**：タイルの id、GeoJSON の `id`（列形式タイルに id を足した）、または source の `promoteId`（文字列か、ソースレイヤーごとのオブジェクト）。問い合わせ結果の `id` もこれになる。
- **ワーカー**（決めていただいた方式③）：
  - 状態を読むレイヤーは、エントリごとに地物の id とインデックス範囲を記録する（`feature_ranges`）。グルーがタイルのバイト列と一緒に保持する。
  - 範囲を記録するため、そうしたレイヤーは別レイヤーのバッファを共有しない。
  - メインスレッドから状態を持つ id を受け取ると（`{type: "ranges"}`）、その範囲だけを返す。同じ id の地物が複数あれば、すべてを返す。
- **メインスレッド**：状態を持つ地物の範囲を、その状態で評価した paint で、インデックス順に描き分ける（`draw_by_state`、`Renderer::set_range`）。
  - fill、line、circle、fill-extrusion の色と不透明度、線の太さ、円の大きさに効く。
  - 新しいタイルとスタイルの変更でも範囲を問い合わせ直す。答えを待つ間は `idle` を出さない。
- **npm**：`setFeatureState`、`getFeatureState`、`removeFeatureState`（MapLibre と同じ引数とエラー）。問い合わせ結果の `state`。
- **example**：地点にホバーすると、`feature-state` で強調する（id は `promoteId` で地点名）。3 つとも同じ処理（`examples/shared/pick.js`）。
- **直した不具合**：ワーカーの `unpack` が空の symbol エントリを飛ばすと、メッセージ内の位置とパックされたエントリ番号がずれていた。共有バッファの参照もずれていた。各レイヤーにエントリ番号 `entry` を持たせて直した。

### 黄金テスト（`npm run query:golden`）

- ビュー「state」を足した。GSI の建物（`ftCode`）と道路（`rdCtg`）に `promoteId` を付け、状態で赤くする。
- 問い合わせ結果（`state` と `id` を含む）と、状態のある地物が上にある 7 点の画素を MapLibre と比べた。
- **320 件すべて同じ**。画素は多くの点で値まで一致した。

### 確認（pack test）

- GeoJSON の id と `promoteId` で、状態に応じて色が変わること、`getFeatureState`、問い合わせ結果の `state`、`removeFeatureState`（キーを指定、id なし）、エラー。
- 3 つの example で、東京駅にホバーすると状態が付くこと。

### 計測

- サイズ：表示の入口 62.1 → 65.4KB（予算 70KB）、表示ワーカー 69.5 → 73.5KB（予算 100KB）。
- `process_tile`（状態を読むレイヤーのないスタイル）：Chromium 6.63ms、Firefox 8.60ms、WebKit 7.54ms。前回と同じ範囲だった。

### 既知の問題・まだのもの

- symbol レイヤーの文字には状態が効かない。fill-extrusion の高さにも効かない（ワーカーが頂点に焼き込むため）。
- GeoJSON の `generateId` は未対応。
- 表示の入口は残り 4.6KB。12.4・12.5 の前に、削れるところを探す。

## 表示ワーカーを小さくする（2026-11-02）

### ユーザー判断（2026-11-02）

- 表示ワーカーの予算（100KB）は、まず削り、足りなくなりそうなら引き上げを相談する。

### できたこと

- 内訳を測ると、表示ワーカーの wasm の約 3 分の 1 が、スタイルを読む core の `@json.parse` と、それが引き込む `strconv` だった（外すと 90.0 → 60.3KB）。
- `core/json.mbt`：JSON を `Json` にする小さなパーサー（`parse_json`）を足した。
  - 数値の読み取り（`read_json_number`、Clinger の速い経路）と文字列のデコード（`json_string_text`）は `formats` から移し、GeoJSON の読み込みと共有する。
  - 15 桁を超える数値は `slow_number` に任せる。
- 表示ワーカーは、スタイルと問い合わせのフィルターをこれで読む。長い数値は出力領域に写して、ホストの `Number()`（`host.number`）で読む。
- 結果：
  - 表示ワーカー：95.7 → **69.5KB**（wasm 単体は 90.0 → 62.6KB）。
  - GeoJSON ワーカー：22.5 → 22.7KB。
- 試してやめたこと：
  - 三角関数と `pow` をホストの `Math` にする案は、あと 5.9KB 減るが、tess・style・raster に注入口を足す手間に見合わないので見送った。
  - `wasm-opt -Oz` は 90.0 → 73.2KB だったが、wasm-gc では最適化で遅くなった前例があるため使わない。

### 確認

- `geojson:golden` は差分 0、`analysis:golden` はすべて同じ、`query:golden` は 254 件すべて同じ、pack test も通った。
- GeoJSON の読み込み（`geojson:node`、同じ回に main と比べた）は揺れの範囲だった。
  - 道路：317.0 → 329.0ms
  - 建物：464.1 → 420.2ms
  - 点：14.4 → 13.5ms

## Phase 12.3a：地物の問い合わせとマウスイベント（2026-11-02）

状態：**完了**。feature-state は 12.3b で続けて作る。

### ユーザー判断（2026-11-02）

- feature-state の作り方（作る前に計測した。fixture 35 タイル、basic スタイル、今の出力は 59.4MB、頂点 439 万）：
  - 頂点ごとに地物番号を持たせる案は +17.6MB（+30%）、地物ごとの範囲表をタイルと一緒に送る案は最大 +11.4MB（+19%）。
  - **ワーカーが範囲表とタイルのバイト列を持ち、状態を持つ地物の範囲だけを問い合わせる案**に決めた。タイルの出力は増えず、反映は 1 往復遅れる。
- `queryRenderedFeatures` と `querySourceFeatures` は **Promise を返す**（ジオメトリはワーカーにあり、メインスレッドは持たない。VISION §4-3）。MapLibre は同期。

### できたこと

- **ワーカー**：送ったタイル（ベクタタイルと GeoJSON の列形式タイル）のバイト列を、メインスレッドが `drop` するまで保持する。`query_tile` と `source_features`（`worker/query.mbt`）で問い合わせに答える。
  - 判定は MapLibre の `FeatureIndex.query` の移植。
    - インデックスに入る条件：輪の箱がタイルに重なること。
    - タイルのパディング（線の太さの半分、円の半径と縁取りの最大）に `maxPitchScaleFactor` を掛けて範囲を広げる。
    - レイヤーごとの判定：fill は多角形との交差、line は太さの半分の幅で、circle は画面上で距離に応じて大きさを変えて（`pitch-alignment: viewport`、`pitch-scale: map`）。
    - fill-extrusion は 3D に投影して、屋根と壁の面で交差を調べ、深さを返す。カメラ側に広げた問い合わせ範囲（`getCameraQueryGeometry`）で拾う。
  - 交差判定（`@core.polygon_hits_*`、MapLibre の intersection_tests の移植）は `core` にあり、ワーカーとメインスレッドで共有する。
- **バケツのジオメトリ種類を MapLibre に揃えた**：fill と fill-extrusion は LineString も輪として塗る（GSI の建物には外形線が LineString で入っている）。circle は線や面の頂点にも円を置く。描画も変わる。
- **メインスレッド**（`map/query.mbt`）：前のフレームで描いたタイルごとに問い合わせを送り、答えを集める。
  - ラベルは前回の配置で記録した画面上の箱（`LabelSet.boxes`）で探し、地物番号（ラベルの浮動小数に足した）でワーカーに伝える。
  - スタイルが途中で変わった答えは捨てる。地図を消すと、待っている問い合わせはそこまでの答えで終わる。
- **npm**：
  - `queryRenderedFeatures(geometry?, { layers, filter })`、`querySourceFeatures(sourceId, { sourceLayer, filter })`。並べ方は MapLibre の `mergeRenderedFeatureLayers` と `_flattenAndSortRenderedFeatures`（3D は近い順）を `npm/src/query.ts`（import なし）に移植した。
  - マウスイベント：`mousedown`、`mouseup`、`mouseover`、`mouseout`、`mousemove`、`click`（3px 未満の移動）、`dblclick`、`contextmenu`。`point` と `lngLat` が入る。
  - レイヤーを指定するイベント：`on(type, layerIds, f)` と `mouseenter`・`mouseleave`。`mousemove` の問い合わせは 1 つずつにまとめる。
- **example**：クリックした地物（いちばん上の地物のレイヤーと名前など）をパネルに出す。地点の上ではカーソルを変える。3 つとも同じ。

### 黄金テスト（`npm run query:golden`、`bench/results/query-golden.json`）

- MapLibre 6.16 と同じページで、同じスタイル、fixture、カメラで比べた。
  - ビュー：平面、回転、50° の傾き、建物を押し出して 55° に傾けたもの。
  - 問い合わせ：点 63、範囲 4、画面全体、レイヤー指定、フィルター、ソースの問い合わせ 2。
- **254 件すべて同じ**（22,582 地物。順序と GeoJSON のジオメトリ、プロパティまで同じ）。
- 比べ方で揃えたこと：
  - MapLibre 6 は既定（`zoomLevelsToOverscale: 4`）で、source の maxzoom より深いズームのタイルを子タイルに切り分ける。そのため問い合わせ結果の切り口と重複が変わる（MapLibre 自身がそう書いている）。mbmap は source のタイルのまま描くので、MapLibre はこれを切って比べた。
  - 傾けたビューでは、MapLibre は錐台にバウンディングボックスが触れるだけのタイルも持つ。mbmap の被覆は見える地面で決めるので、画面全体とソースの問い合わせはそのタイルの分だけ違う。この 2 種類は比べていない。
  - 同じ深さで交わる押し出し（同じ建物の面と外形線）の順序は丸め誤差で決まるので、比べる前にそろえた。

### 確認（pack test、Chromium）

- 実行中に足した GeoJSON ソース（面、線、点）で確かめた。CI はタイルの fixture を取得しないので、ベクタタイルの問い合わせは黄金テストで確かめる。
  - 点の問い合わせが上から点・線・面の順で返ること、範囲とフィルター、ないレイヤーの `error`、未対応のフィルターでの reject、ソースの問い合わせ（2 タイルにまたがる面はタイルごとに返る）。
  - 地図のクリック（ドラッグはクリックにならない）と、レイヤーの `click`・`mouseenter`・`mouseleave`。
- 3 つの example で東京駅をクリックすると、地点が出ること。

### 計測

- 表示ワーカーの `process_tile`（`npm run worker:browser`、同じセッションで main → ブランチ → ブランチ）：
  - 中央値：Chromium 6.52 → 6.74 / 6.66ms、Firefox 8.64 → 8.70 / 8.64ms、WebKit 7.02 → 7.22 / 7.62ms。
  - 実行ごとの揺れの範囲で、出力のバイト数は同じ（basic スタイルは種類をフィルターで絞っている）。
- サイズ：表示の入口 56.6 → 62.1KB（予算 70KB）。表示ワーカー 89.7 → 95.7KB（予算 100KB）。
  - ワーカーの増加は問い合わせのコード（約 6.6KB）。プロパティを Map を使わずに書き出して 0.4KB 減らした。
- ワーカーのメモリ：表示中とキャッシュ中のタイルのバイト列を持つ（fixture で平均 370KB/タイル）。

### 既知の問題・まだのもの

- feature-state（12.3b）。
- 表示ワーカーの予算の残りは 4.3KB。式を足す Phase 15 の前に、予算か分け方を相談する。
- タッチのイベント（`touchstart` など）は未対応。`preventDefault` で地図の操作を止めることはできない。
- 地形の上では、問い合わせは地面の高さを考えない（MapLibre は `getElevation` で考える）。
- GeoJSON ソースの地物は、geojson-vt の id を持たない。MapLibre の `promoteId` も未対応。

## Phase 12.2：実行中のスタイル変更（2026-11-02）

状態：**完了**。

### できたこと

- **`map`**：`set_style` は新しいスタイルを前のものと比べ、使えるタイルを残す。
  - タイルを残すソース：`Source::same`（取得と切り方が同じ）で、新しいスタイルでそのソースを使う各レイヤーが、前のスタイルに同じ ID と同じ作り方（`StyleLayer::same_tiles`：種類、ソースレイヤー、ズーム範囲、フィルター、文字と線の layout、押し出しの高さ、paint が読む地物の値）で入っていること。レイヤーの順序は描くときに決まるので見ない。
  - 残したタイルのメッシュは、レイヤー ID で新しい番号に付け替える。消えたレイヤーのメッシュは捨てる（共有のバッファは、残るレイヤーへ持ち主を移す）。
  - 残せないソースのタイルは `Stale` にして描き続け、読み直したものと入れ替える（地図が一瞬空になることはない）。読み込み中の要求は取り消して、新しいスタイルで頼み直す。
  - ワーカーへは `{type: "style"}` を送り、それ以降の要求を新しいスタイルで作らせる。`reload_source` は GeoJSON のデータが変わったソースを読み直す。
  - スタイルを変えるたびに `idle` を出す（paint だけの変更でも。MapLibre と同じ）。
- **npm**：`setStyle`（オブジェクトか URL）、`getStyle`、`addLayer`、`removeLayer`、`moveLayer`、`getLayer`、`getLayersOrder`、`setPaintProperty`・`getPaintProperty`、`setLayoutProperty`・`getLayoutProperty`、`setFilter`・`getFilter`、`setLayerZoomRange`、`addSource`、`removeSource`、`getSource(id).setData`、`setTerrain`・`setSky`・`setLight` とその getter。
  - 編集は `npm/src/style.ts`（import なしの純粋な関数。`npm test` で試す）でスタイルの写しを作り、エンジンの `set_style` に渡す。描けないスタイルになる変更は `error` を出し、元のまま描き続ける。
  - GeoJSON ソースは、最初に GeoJSON を含むスタイルになったときにモジュールとワーカーを読み込む（地図を作った後に `addSource` しても動く）。データは参照で比べ、`setStyle` で同じ内容のデータは前の参照に揃える（読み直さない）。GeoJSON ワーカーは同じ番号の読み込みを順に処理し、`unload` で消したソースを捨てる。
  - `<mb-map>` の `mapStyle` と `style-url` の変更は、地図を作り直さず `setStyle` に渡す。
- **example**：2D と 3D の切り替えを `setStyle` にした（地図を作り直さない）。レイヤーの表示切り替え（陰影、等高線、建物、道路・鉄道、注記、地点。`setLayoutProperty`）と、中心に印を置くボタン（`getSource("places").setData`）を足した。

### MapLibre との違い

- 表示を消したレイヤーは、スタイルを読むときに外すので、消してもタイルは読み直さない（MapLibre は読み直す）。表示し直すと読み直す（MapLibre と同じ）。`moveLayer` と `removeLayer` は MapLibre と同じく読み直さない。
- `setStyle` の `diff: false` は受け付けない（常に差分で切り替える）。
- MapLibre の `Style` は Node で動かせない（ワーカーと WebGL を前提にする）ため、黄金テストの代わりに pack test で振る舞いを確かめた。

### 確認（pack test、Chromium）

- paint の変更、表示を消す・`moveLayer`・`removeLayer` ではタイルを取得し直さないこと、表示し直すと取得し直すこと（タイルの要求数で確認）。
- 描けない変更（ないレイヤー、使われているソースの削除、未対応の式）が `error` を出し、スタイルが元のままであること。
- `setStyle` で背景だけのスタイルにすると画面が背景色になり、タイルを取得しないこと。GeoJSON ソースを後から足すと点が描かれ、`setData` で動くこと。元のスタイルに戻すと元どおりに描くこと。
- 3 つのショーケースで、3D への切り替えが同じ地図のまま地形を持つこと、レイヤーの表示切り替えと印の追加。

### サイズ

- 表示の入口 52.5 → 56.6KB（予算 70KB）。GeoJSON の窓口 0.8 → 0.9KB、GeoJSON ワーカー 22.3 → 22.5KB、表示ワーカー 89.6 → 89.7KB。

## example の整理：1 つのショーケースを 3 通りで（2026-11-02）

### ユーザー判断（2026-11-02）

- examples/ は、同じ地図アプリを素の HTML・Web Component・React の 3 通りで書く形にする。部品ごとに分けず、1 つの画面でいろいろな機能を確かめられるようにする（進捗の確認と、のちの GitHub Pages での公開のため）。
- 地図データは国土地理院の配信タイルを直接読む。CI とベンチは `?local=1` で手元の fixture を読む。
- 今の 7 つの example は 3 つに置き換える。開発用のページは `bench/pages/`、試験用のページは `bench/npm/pages/` に移す。
- 機能は今あるもので始め、Phase が進むたびに足す（各 Phase の完了条件に含める。VISION §8）。

### できたこと

- `examples/{html,element,react}`：2D と 3D（地形・建物の押し出し・空・60° の傾き）の切り替え、地点への移動（`flyTo`：東京駅、富士山、大阪駅、京都、札幌駅）、カメラの状態、最寄りの原点の平面直角座標系での座標（`transform`）、画面の中心から 5 km 以内の地点（`buffer` と `pointsWithin`。移動が終わるたびに計算）、GeoJSON の点とラベル、陰影起伏。
  - 共通部分（スタイル、地点、解析）は `examples/shared/` にあり、3 つが同じものを使う。
  - スタイルを変える API（Phase 12.2）がまだないので、2D と 3D を切り替えるたびに地図を作り直している。
- `<mb-map>` に `mb-movestart`・`mb-moveend` を足した（解析を移動の終わりで行うため）。
- 移動したもの：`examples/basic`・`terrain` → `bench/pages/`、`examples/npm`・`element`・`geojson`・`analysis` → `bench/npm/pages/`。旧 React の例はショーケースの React 版に置き換えた。
- pack test：3 つのショーケースで、同じ結果になることを確かめる（東京駅の 5 km 以内の地点、IX 系の座標が proj4js と同じ、3D で 60°、大阪駅へ移動するとパネルが追従し VI 系になる）。

## Phase 12.1：カメラの API（easeTo・flyTo・fitBounds、制約、操作、イベント）（2026-11-02）

状態：**完了**。Phase 12 は 12.1 カメラ → 12.2 実行中のスタイル変更 → 12.3 問い合わせと feature-state → 12.4 ラスタタイル・TileJSON・PMTiles → 12.5 画面座標の追跡と画像の書き出し、の順に進める。

### ユーザー判断（2026-11-02）

- Phase 12 の分け方：上の 5 段階。完了条件は MapLibre 6.16 と同じ結果になること（黄金テスト）、example、表示の入口の予算。
- feature-state は 12.3 で、問い合わせと一緒に作る（頂点に地物の番号を持たせ、状態をテクスチャで引く。作る前に計測して報告する）。
- 表示の入口（メインスレッド）の予算：50KB → **70KB**（VISION §2）。12.1 で 52.5KB になり、Phase 12 全体で 60〜65KB になる見込みのため。

### できたこと

- **`core`**（全ターゲット）：MapLibre のカメラの計算の移植。
  - 制約（`Limits`：ズームとピッチの範囲、`maxBounds`）。表示が南北の端（85.051129°）や範囲を出ないように、ズームを上げ、中心を動かす。MapLibre と同じく、ズームを先に、中心を後に制約する。移動の行き先は 1 回だけ制約する（`applyConstrain`）。
  - `project`（カメラの後ろの点は、ビューを一回り広げた枠の縁へ）、`unproject`、`bounds`（傾けたときは地平線まで）、`at_point`（`setLocationAtPoint`）、`camera_for_bounds`（パディング、オフセット、方位、最大ズーム）。
  - `ease_to`（中心をズームに合わせて速める）、`fly_to`（van Wijk と Nuij の経路、`curve`・`speed`・`screenSpeed`・`minZoom`）、CSS の `ease` 曲線（`Bezier`、@mapbox/unitbezier の移植）、方位の近い方への回り込み、経度の正規化。
  - 経度と方位は MapLibre と同じく (-180, 180] に折り返す（これまでは [-180, 180)）。
- **`map`**：アニメーションをフレームループで進め、`move_start`・`move_end` を、ジェスチャー・慣性・ホイール（最後のイベントから 200ms）・アニメーションの前後で出す。
  - 操作（`Handler`）：ドラッグ（3px までは動かさない）、慣性（MapLibre の速度の計り方と減速）、ホイール、Shift＋ドラッグのボックスズーム、右ドラッグの回転と傾き、キーボード（矢印、Shift＋矢印、`+`・`-`、300ms の ease-out）、ダブルクリック（Shift で縮小）、2 本指のピンチと回転、2 本指を上下に動かす傾き。1 つずつ有効・無効にできる。
- **npm**：`easeTo`、`flyTo`、`panBy`、`panTo`、`zoomTo`、`zoomIn`、`zoomOut`、`rotateTo`、`resetNorth`、`resetNorthPitch`、`snapToNorth`、`fitBounds`、`fitScreenCoordinates`、`cameraForBounds`、`stop`、`isMoving`、`isEasing`、`isZooming`、`isRotating`、`project`、`unproject`、`getBounds`（`LngLatBounds`）、ズーム・ピッチの範囲と `maxBounds` の setter・getter、`map.scrollZoom.disable()` などのハンドラ、オプションの `bounds`・`interactive`。
  - イベント：`movestart`・`move`・`moveend`、`zoom`・`rotate`・`pitch` とそれぞれの start・end（MapLibre と同じ順）。ユーザーの操作では `originalEvent` が入る。
  - エンジンができる前（スタイルの読み込み中）のカメラの呼び出しは、できてから順に実行する。OS の「視差効果を減らす」では、`essential` でない限りアニメーションしない。

### 黄金テスト（`npm run camera:golden`、`bench/results/camera-golden.json`）

- MapLibre 6.16 の `Camera` を Node で、時刻を止めて（`setNow`）動かし、比べた。対象は 19 の視点（800×600 と 600×900、ズーム 0〜16、ピッチ 0〜80°、方位、日付変更線の近く、南極の近く、`maxBounds`、ズームとピッチの範囲）。
  - 比べたもの：制約、`project`・`unproject`・`getBounds`（各 19）、`cameraForBounds`（57）、`easeTo`（76）、`flyTo`（57。所要時間を含む）、既定のイージング。比べる点は 0〜1 の 7 か所。
- 最大の差：6.5e-9 px、3.9e-8°（約 4mm）、1.4e-9 ズーム、4.5e-7 ms。許容は 1e-6 px、1e-7°、1e-8 ズーム、1e-5 ms。差は、行列の作り方の違いによる丸めで生じる。

### 確認（pack test、Chromium）

- `easeTo` が指定どおりに終わること、イベントの順、`flyTo`、`fitBounds` が `cameraForBounds` と同じ結果になること、`project`・`unproject` の往復、`maxBounds` で表示が範囲を出ないこと、`maxZoom`、範囲外の制限値を拒むこと、`scrollZoom.disable()` でホイールが効かないこと。
- 右矢印でちょうど 100px 動くこと、`+` で 1 段ズームすること、ダブルクリックでクリックした点を動かさずに 1 段ズームすること。

### サイズ

- 表示の入口 43.5 → 52.5KB（エンジン 42.0 → 49.0KB、TS の窓口 2.1 → 4.2KB）。イベントのリスナーを 1 つの表にまとめて 0.4KB 減らした（型ごとに HashMap が作られていたため）。

### 既知の問題・まだのもの

- `create_map` に引数（制限）を足したとき、エンジンを直接呼ぶ `examples/basic`・`examples/terrain`・`bench/render/page.mjs` を直し忘れ、描画されなくなっていた（ユーザーの指摘で修正）。pack test に、この 2 つの example が描画まで進むかの確認を足した。
- 地図のパディング（`setPadding`）は未対応。
- ホイールのズームは、MapLibre のように滑らかには動かさず、その場で変える。タッチのダブルタップのズームはまだない。
- 地形があるとき、`project`・`unproject` は海面の高さで計算する（MapLibre は地形の高さを使う）。

## 方針の更新（2026-11-02、ユーザー判断）

- VISION.md のゴールは変えない。
- UI コンポーネントは、組み立て済みのウィジェットではなく**ヘッドレス**にする。機能を API（状態・操作・購読）として使え、見た目は作り手が自由に作る（VISION §6「ヘッドレス UI」）。
- MapLibre GL JS、ArcGIS Maps SDK for JavaScript、CesiumJS と比べて足りないものを洗い出した（VISION §10）。サーバー側の機能が欠かせないもの以外は、Phase 12〜19 のロードマップにした（VISION §8）。
- 検索（GeoSearch）は既定で用意する。既定のプロバイダは**サーバーに問い合わせないものだけ**（座標の読み取り、読み込んだデータの属性検索）。外部の検索 API はプロバイダとして差し替え・追加できるようにする。
  - 検討した外部 API：国土地理院の地名検索（主に地理院地図からの利用を想定していて、長期の提供は保証されていない。住所は東大 CSIS のシンプルジオコーディング）、OSM の Nominatim（公式サーバーでの入力中の候補表示は利用規約で禁止）。どちらも既定にはせず、example で足し方を示す。
- 印刷はサーバーの印刷サービスではなく、クライアントで完結させる（ユーザーの指摘で「作らないもの」から外した）。高解像度に描いて Wasm で PDF を作り、ブラウザの PDF ビューアなどで印刷する（Phase 19）。
- 順番は、地図の基本 API（Phase 12）→ ヘッドレス UI と GeoSearch（Phase 13）→ 作図・編集 → スタイルの拡充 → データ形式 → 解析の第2弾 → 3D の第2弾 → 時間・比較・印刷。

## Phase 11 の後のリファクタリングとセキュリティチェック（2026-11-02）

### ユーザー判断（2026-11-02）

- enum・struct・TS の interface・配列やオブジェクトのリテラルなど、列挙の途中の行にはコメントを入れない（MoonBit・TS・JS とも）。AGENTS.md §7.7 に書いた。

### リファクタリング（AGENTS.md §7 の順）

- 列挙の途中のコメント：`proj` の `DatumKind` の各値、TS の interface 8 つ（`MapOptions`、`AnalysisOptions`、`BufferOptions` など）、bench とテストのリテラル 9 か所。説明は、型やリテラルの上のコメントにまとめた。そのとき `MapOptions.pitch` の説明が「0〜60」のまま古かったので「0〜85」に直した。
- 定数：`MAX_INPUT_BYTES`（3 つの wasm で同じ値）を `@wasmio` に一つにした。CRS 定義のスロット数（34）は、JS 側で名前を付けて proj/encoding.mbt を指すようにした。
- 重複と不要なコード：
  - f64 の入力の読み方（proj_worker と analysis_worker）を `@wasmio.input_f64s`（線形メモリから f64 のまま読む）にまとめた。
  - 解析 Worker の `input` と `inputTo` を一つにした。
  - `nan2` を common.mbt に移した。`DatumKind` の手書きの `Eq` を `derive(Eq)` にした。
  - `Crs::new` で楕円体の短半径を二度求めていたのをやめた。`Lcc::new` の不要な偽原点の補正を消した。
  - `@overlay.DEGREE_SCALE` を非公開にした。
- ファイルの分割：proj/azimuthal.mbt（956 行）を azimuthal（aeqd、laea、ortho、gnom）、stereographic（stere、sterea）、vincenty に分けた。cylindrical.mbt（582 行）から pseudocylindrical（sinu、eck6、moll、robin、eqearth）を分けた。Clipper2 と earcut の移植は、元のファイル構成に合わせたまま残した。
- 書き方：laea の形を整数の定数から enum（`LaeaMode`）にした。datum の C 形式の for を範囲の for にした。
- テスト：投影が届かない点の扱い（正射図法の裏側、laea の対蹠点と範囲外の逆変換）、Bonne の標準緯線が赤道のときの拒否、`input_f64s` のテストを足した。
- 性能：`npm run proj:node`（`bench/proj/node.mjs`、`bench/results/proj-node.json`）を足した。proj.wasm を、解析 Worker が呼ぶのと同じ形（f64 の組を入れて出す）で動かし、proj4js の 1 点ずつの変換と比べる。Node 22、100 万点の中央値：

| 変換（WGS84 から） | 改善前 | 改善後 | proj4js |
|---|---|---|---|
| 平面直角 IX 系（6677） | 231 ms | 219 ms | 393 ms（1.79×） |
| Web メルカトル（3857） | 87 ms | 69 ms | 200 ms（2.89×） |
| 日本測地系の IX 系（30169、3 パラメータ） | 378 ms | 376 ms | 528 ms（1.40×） |
| lcc、7 パラメータ（PROJ 文字列） | 384 ms | 382 ms | 516 ms（1.35×） |

  - 効いたのは 2 つ：入力を f64 のまま読む（バイトを組み立てない）こと、変換の途中で `Option` を作らず最後に一度だけ確かめること。datum を経由する変換は地心座標の反復が大半で、差は誤差の範囲だった。
  - 試してやめたもの：MoonBit の `@math` で計算すると、ホストの `Math` より遅かった（IX 系 256 ms、3857 88 ms、30169 424 ms）。ホストの `Math` のままにする。
- 変えなかったもの：wasm-gc の入口（geometry_worker、proj_worker、analysis_worker）の export は単体テストがなく、pack test で確かめている（これまでと同じ）。flatbush 4.7.0 は出ているが、黄金テストの基準（4.6.2）なので上げない。clipper の公開 API は、Clipper2 の API に合わせた移植の面なので、外から使っていないものも残す。

### セキュリティチェック（AGENTS.md §8）

- 依存関係：`npm audit` は npm/ と bench/ で 0 件。Dependabot のアラートも 0 件。直接の依存の GitHub Security Advisories を調べ、esbuild（0.28.1 で修正）、maplibre-gl（6.4.1）、playwright（1.55.1）の既知の問題は、どれも固定している版（0.28.2、6.16.0、1.64.1）で直っている。moon は 0.1.20261028。
- 信頼できない入力：
  - CRS の定義は、ちょうど 34 スロット、投影の番号と `towgs84` の個数を確かめる。`Crs::new` は軸の長さ・単位・本初子午線を確かめる。定義の数は 1024 までにしている。
  - 投影と datum の反復は、どれも回数に上限がある（proj4js では上限のない Mollweide の反復にも上限を付けた）。
  - `with_coords` は座標の数がデータセットと合うかを確かめる。
  - PROJ 文字列のパーサは `Map` と `Object.hasOwn` で表を引くので、`__proto__` などのキーでプロトタイプは汚染されない。
- Web：配布物に `innerHTML`・`eval`・`new Function` はない。データ・スタイル・タイルの fetch は `credentials: "omit"`。postMessage のハンドラは、メッセージの形と型を確かめている。秘密情報や個人情報はない。
- 重大な問題は見つからなかった。

## Phase 11.3：PROJ 文字列、投影の追加、7 パラメータの測地系変換（2026-11-02）

状態：**完了**。Phase 11（ジオメトリ演算と座標系）はこれで終わり。

### ユーザー判断（2026-11-02）

- geometry.wasm の予算：45KB → 50KB（11.2 の報告で了承）。
- 座標系の wasm：座標系を geometry.wasm に同居させると 59.4KB（予算 50KB 超え）になったため、proj.wasm に分ける案を選んだ（予算を上げる案、投影を減らす案と比べて）。

### できたこと

- **`proj`**：proj4js 2.22.0 の変換の流れを移植した。
  - 投影 27 種：longlat、merc（球・楕円体、`lat_ts`）、tmerc（etmerc）、utm、lcc（1SP・2SP）、aea、aeqd（Vincenty、極）、stere（極・斜軸）、sterea（ガウス球）、cass、laea（極・赤道・斜軸）、eqc、eqdc、sinu、eck6、moll、robin、cea、mill、poly、omerc（方位角・2 点、`no_uoff`、`gamma`）、somerc、krovak、ortho、gnom、eqearth、bonne。
  - 測地系の変換：`towgs84` の 3・7 パラメータ（Helmert）で、地心直交座標を経て WGS84 を経由する。proj4js の近道（`+datum=WGS84` の判定、途中で高さを捨てること）も同じにした。
  - 本初子午線（`pm`）、単位（`units`、`to_meter`）、`lon_wrap`、`+R_A`。
  - `Definition`（解析済みの PROJ 文字列）から `Crs::new`。EPSG コードの表に日本測地系を足した：4301、30161〜30179（平面直角座標系）、3092〜3096（UTM）。3 パラメータは EPSG:15484（-146.414, 507.337, 680.507）。
  - 計算は `Trig` を通す（既定は MoonBit の `@math`）。proj.wasm はホストの `Math` を渡すので、proj4js と同じ関数で計算する。
  - proj4js が明らかに誤っているところは PROJ に合わせた：`+R_A` で半径を変えない（PROJ 9.9 の `proj` と同じ値を単体テストで確かめた）、sinu の順変換と stere の赤道の場合に偽原点を足さない、gnom の中心で緯度が未定義になる。どれもコードにコメントを残した。
- **PROJ 文字列**：`npm/src/projstring.ts` が proj4js の `projString.js` と同じように読み、楕円体（44）・測地系（17）・単位・本初子午線の表を引いて、34 個の f64（docs/FORMATS.md「CRS definition」）にする。`+nadgrids`（グリッドによる変換）と未対応の投影はエラーにする。`mbmap/analysis` が、初めて PROJ 文字列を受け取ったときにだけ `projstring.js` を読む。
- **`mbmap/analysis`**：`crs` に PROJ 文字列と、`defineCrs(name, projString)` で付けた名前を渡せるようになった。
- **proj.wasm（`proj_worker`）**：`define_crs`、`crs_kind`、`transform_coords`。データセットは座標の f64 の組だけを受け渡す（解析 wasm の `coords_out` / `with_coords` と `@geom.Table::map_coords`）。
- **planar buffer**：解析 Worker がデータセットを座標系の平面に移し（proj.wasm）、その平面で buffer を取り（geometry.wasm）、経緯度に戻す（proj.wasm）。`@overlay.buffer` の `Planar` は「座標そのものの平面で測る」になり、overlay は proj に依存しなくなった。頂点だけを変換するので、辺は投影した平面でまっすぐになる（GIS ソフトで投影したレイヤに buffer を取るのと同じ。以前は経緯度で 0.01° ごとに区切ってから投影していた）。

### 黄金テスト（`npm run proj:golden`、`bench/results/proj-golden.json`）

- proj4js 2.22.0 と、EPSG コード 197（11.2 の 172 に日本測地系の 25 を足した）と PROJ 文字列 43（Lambert 93、NTF のパリ子午線、US フィート、Conus Albers、NSIDC 極ステレオ、RD New、Soldner Berlin、LAEA Europe、EASE-Grid 2.0、Alaska・マレー半島の斜軸メルカトル、スイス LV95、Krovak、英国ナショナルグリッドなど）で比べた。
- 合わせて 240 の座標系、94,600 点（順変換・逆変換・座標系どうし。proj4js が投影できない 1,400 点は除いた）。最大の差は 4.7e-9 m、4.3e-14°（js と wasm-gc。wasm-gc はホストの `Math` で計算する）。許容は 1mm / 1e-8°。
- `+R_A` だけは proj4js が半径を変えないので、黄金テストから外し、PROJ 9.9 の値で単体テストにした。

### サイズ（`bench/results/npm-size.json`）

| 構成 | geometry.wasm | proj.wasm |
|---|---|---|
| 座標系を geometry.wasm に同居 | 59.4KB | ― |
| proj.wasm に分け、表のバイト列で受け渡す | 38.2KB | 35.8KB |
| ホストの `Math` を使う（core の math 約 7KB が外れる） | 38.2KB | 29.4KB |
| 座標の組だけを受け渡す（geom が外れる） | 38.2KB | 21.8KB |

- 最後の構成を採った。proj.wasm の予算は 25KB。
- mbmap/analysis 2.4 → 2.6KB、projstring.js 2.7KB（予算 5KB）、解析 Worker 27.8 → 28.9KB（予算 30KB。`coords_out` / `with_coords` と、モジュールの読み込みの共通化）。

### 確認

- pack test（Chromium）：Lambert 93 の PROJ 文字列でパリが proj4js と同じ（652469.023, 6862035.259）になること、`defineCrs` の名前でも同じこと、日本測地系の IX 系で東京駅が proj4js と同じ（-5701.993, -35723.010）になること、未対応の投影（geos）を拒むこと、IX 系の planar buffer が IX 系で円（誤差 0.7mm）になること、proj.wasm と projstring.js が使うときにだけ読まれること。
- `npm run buffer:check`：測地線の buffer は 11.1 と同じ精度（点 ≤ 0.004%、多角形 ≤ 0.013%、80° の線 ≤ 0.11%）。

### 次にやること

- VISION §8 の次の Phase（Phase 12）。範囲はユーザーと確認する。
- 座標系で残っているもの：グリッドによる測地系の変換（TKY2JGD、NTv2）、WKT・PROJJSON の読み込み、軸の順（`+axis`）。

## Phase 11.2：座標系の変換（平面直角座標系・UTM・Web メルカトル）（2026-11-02）

状態：**完了**。

### できたこと

- **`proj`**（純 MoonBit、全ターゲット）：EPSG コードから座標系を作る（`Crs::from_epsg`）。
  - 経緯度：4326（WGS84）、4612（JGD2000）、6668（JGD2011）。
  - Web メルカトル：3857（3785、900913）。球面の式（proj4js の merc.js）。
  - 平面直角座標系 I〜XIX 系：6669〜6687（JGD2011）、2443〜2461（JGD2000）。
  - UTM：32601〜32660、32701〜32760（WGS84）、6688〜6692・3097〜3101（JGD2011・JGD2000 の 51〜55 帯）。
  - 横メルカトルは proj4js 2.22.0 の `etmerc`（Poder/Engsager の Krüger 級数、6 次）の移植。
  - 投影の範囲外（Web メルカトルの極、横メルカトルの中央子午線から遠い点）は `None` を返す。
  - JGD2000・JGD2011 と WGS84 の間の測地系の変換はしない（proj4js でも towgs84 が 0）。Tokyo 測地系などの 7 パラメータ変換は 11.3 で扱う。
- **`overlay`**：`transform(table, from, to)` を足した。範囲外の点を含む地物は、行を残してジオメトリなしにする。`buffer` の planar は、渡された投影座標系（既定は 3857）の平面で測る。
- **geometry.wasm**：`transform`（表）と `transform_coords`（座標の組。範囲外は NaN）を足した。`buffer` は座標系のコードを受け取り、経緯度や未対応のコードは拒む。
- **`mbmap/analysis`**：`load(data, { crs })`、`toGeoJSON({ crs })`、`buffer(m, { mode: "planar", crs })`、`transform(coords, from, to)`。`crs` は数値、`"EPSG:6677"`、`"urn:ogc:def:crs:EPSG::6677"`、`"CRS84"` を受け付ける。Worker の中のデータセットは常に 4326 で持つ。

### 黄金テスト（`npm run proj:golden`、`bench/results/proj-golden.json`）

- proj4js 2.22.0（bench の devDependency、`--save-exact --ignore-scripts`、npm audit 0 件）と、対応する 172 の座標系すべてで比べた。各座標系の範囲に散らした 200 点の順変換・逆変換と、平面直角 IX 系 → UTM 54 帯、IX 系 → 3857 の変換、合わせて 69,200 点。
- 最大の差：3.7e-9 m、2.8e-14°（js・wasm-gc とも）。許容は 1mm / 1e-8°。

### サイズ（`bench/results/npm-size.json`）

- mbmap/analysis 2.1 → 2.4KB、解析 Worker 27.5 → 27.8KB、geometry.wasm 39.7 → 44.2KB。
- geometry.wasm の予算を 45KB から 50KB に上げた。11.3 で投影を足すと 45KB を超える見込みのため。投影が ~20KB を超えたら、別のモジュールに分けることを検討する（AGENTS §4 の基準）。

### 確認

- pack test（Chromium）で、東京駅の IX 系の座標が proj4js と同じ（-5995.185, -35367.230）こと、IX 系で読んで経緯度に戻ること、IX 系で 100m の planar buffer が IX 系で円（誤差 0.7mm）になること、未対応のコードを拒むことを確かめた。

## Phase 11.1：ジオメトリ演算（Clipper2 の移植、buffer・dissolve・clip・erase・intersect）（2026-11-02）

状態：**完了**。Phase 11 は、11.1（ジオメトリ演算）、11.2（座標系変換：平面直角座標系・UTM・Web メルカトル）、11.3（proj 文字列と投影の追加、7 パラメータの測地系変換）の順に進める。

### ユーザー判断（2026-11-01）

- 進め方：演算 → 座標系の順。
- 答え合わせ：clipper2-wasm（公式の C++ 版 Clipper2 を wasm にしたもの）。
- buffer：現実の距離（測地線）と、投影座標での距離の両方を用意する（GIS をやっていた者のこだわり）。
- 座標系：まずは推奨の範囲（平面直角座標系、UTM、Web メルカトル）。ただし、できるだけ多く対応したい。
- 配り方：解析 Worker が別の wasm（geometry.wasm）を初めて使うときに読み込む。
- API：GIS の定番ツール型（buffer、dissolve、clip、erase、intersect）。

### できたこと

- **`clipper`**（純 MoonBit、全ターゲット）：Clipper2 2.0.1 の移植（コミット 642390d）。
  - ブール演算（交差・和・差・排他的論理和、開いたパス、穴の入れ子の木）。
  - オフセット（4 種類の角、5 種類の端、点）。
  - 交点のリストの並べ替えは、libc++ の `std::sort`（LLVM 21）の手順の移植で行う。C++ 版の `std::sort` は安定ソートではなく、同順位の並びが結果を左右するため。最初に安定ソートで移植したときは、48,560 回中 193 回（0.4%）が食い違った。
  - 深さの上限に達したときのヒープソートへの切り替えだけは、安定ソートで代用した（要素数の対数の 2 倍の深さまで分割したときだけ起きる経路）。
- **`overlay`**（純 MoonBit）：`@geom.Table` に対する演算。
  - `buffer`：geodesic は地物ごとの正距方位図法で、x を楕円体の東西の曲率半径 N、y を南北の曲率半径 M で計る。planar は Web メルカトルのメートル。辺は投影の前に 0.01° 以下に区切る。
  - `dissolve`、`clip`、`erase`、`intersect`：1e-7° の整数で計算する。
  - リングの向きは、地物ごとに偶奇規則で和を取ってそろえる。
- **`geometry_worker`**（geometry.wasm）：表のバイト列を受けて演算し、表のバイト列を返す。解析 Worker が、初めて演算を呼んだときに読み込む。同じ Worker の中で受け渡すので、メインスレッドを通らない。
- **`mbmap/analysis`**：`Dataset` に `buffer(meters, { mode, join, cap, arcTolerance })`、`dissolve()`、`clip(other)`、`erase(other)`、`intersect(other)`、`toGeoJSON()` を足した。GeoJSON への組み立ても Worker の中で行う（`analysis_worker/js/table.mjs`）。
- **example**：`examples/analysis` で、区画を 30m 広げて結合した範囲を地図に重ねた。

### 確かめたこと

- `npm run clipper:golden`：clipper2-wasm 0.4.0（同じコミットの C++ 版）と、点列の順番まで完全一致するかを比べる。
  - 入力は、ランダムな多角形（座標の範囲 100〜2^30、自己交差を含む）、格子の上の長方形、開いたパス、国土地理院の 35 タイルの建物と水域。
  - 4 演算 × 4 塗りつぶし規則 × パス出力と木の出力で、10,000 ケース 160,560 回が js 版・wasm-gc 版とも全件一致した。
  - オフセットは、3,000 ケース 45,000 回（角 3 種類 × 端 5 種類）が全件一致した。clipper2-wasm が Bevel を出していないので、Bevel だけは比べていない。
- `npm run buffer:check`：geodesic buffer の外周の各頂点から元の地物までの距離を、GeographicLib 2.2.0（WGS84 の測地線）で測る。緯度 0〜80°、距離 10m〜50km、点・線・多角形で調べた。
  - 点：誤差は最大 1.9m / 50km（0.004%）。
  - 多角形：最大 0.013%。
  - 線：60° までは最大 0.012%。80° の線だけ 0.08〜0.11%（数 km の長さでも、東西の縮尺が変わるため）。
  - 最初は 1 つの球（ガウス曲率半径）で近似していて、赤道で 0.34% の誤差があった（東西と南北の曲率半径の差）。x を N、y を M で計るように直した。辺を区切る前は、長い線で最大 0.3% の誤差があった。
- ブラウザ（`npm run npm:pack`）：点の buffer、線の clip、dissolve、erase、intersect の属性の付け替え、不正な距離の拒否、geometry.wasm が地図だけのページでは読まれないこと。

### 計測（`npm run geometry:node`、`bench/results/geometry-node.json`）

Node 22、国土地理院の 5 タイルの建物 17,764 棟、5 回の中央値。

| | mbmap | Turf.js 7.4.0 |
|---|---|---|
| dissolve（全建物を結合） | 193ms | 2,333ms（polyclip-ts） |
| buffer（各建物を 10m） | 491ms | 1,177ms（JSTS） |
| clip（建物を水域で切る） | 74ms | 957ms（polyclip-ts） |

- mbmap は、読み込み済みのデータセットへの演算（表のバイト列の受け渡しを含む）。GeoJSON への出力を含めても、ほぼ同じ（199ms / 570ms / 74ms）。
- clip は、どちらも建物の範囲と重なる水域だけを使う。Turf で建物ごとに水域全体と演算すると、5 タイルで 945 秒かかった。

### サイズ（gzip）

- geometry.wasm：39.7KB（予算 45KB。初めて演算を呼んだときだけ読む）。Clipper2 本体が約 25KB、buffer（オフセットと投影の三角関数）が約 10KB。
  - 三角関数を JS の `Math` から借りれば数 KB 減らせる。ただ、C++ 版（musl の libm）との完全一致が保証できなくなるので、見送った。
- 解析 Worker：25.1KB → 27.5KB（演算の受け渡しと GeoJSON の組み立て）
- `mbmap/analysis`：1.8KB → 2.1KB

### 既知の問題・次にやること

- 日付変更線をまたぐ地物の buffer は考えていない。
- intersect の組み合わせの絞り込みは、範囲の総当たり（O(n·m)）。大きなデータでは空間索引を使う。
- dissolve は多角形だけ（線と点は除く）。属性でまとめる dissolve はまだない。
- 次は 11.2（座標系変換）。buffer の planar に座標系を指定できるようにする。

## リファクタリングとセキュリティチェック（Phase 10 のあと）（2026-11-01）

AGENTS.md §7 の観点を順に見て、指摘の一覧を作ってから直した。§8 のセキュリティチェックも行った。

### リファクタリング

- 定数・重複：
  - 地形の誇張率を取り出す式が 3 か所にあったので、`Map::exaggeration` にまとめた。
  - 同じ JS 関数（`f32_index` と `f32_at`）を 1 つにした。
- 未使用：`BBox::union`（テストからしか呼ばれない）を消した。`Transform::mercator_to_screen` もテストからしか呼ばれないが、`screen_to_mercator` と対になり、ファサードの `project()` に使う予定なので残した。
- ファイル分割：
  - `render_webgl2/gl.mbt`（915 行）の 3D 部分（標高テクスチャ、描画先、地形、深度、空、押し出し）を `gl_3d.mbt` に分けた。
  - `renderer.mbt` も同じく `renderer_3d.mbt` に分けた。
  - `gl.mbt` は 626 行のまま。大半は全シェーダーを持つ初期化で、そこは分けない。
- テスト：
  - 照明の向き（`light_direction`、MapLibre の `sphericalToCartesian` と画面の向きでの回転）を純粋な関数に切り出し、値を確かめるテストを足した。
  - `extrusion_runs` にもテストを足した。
- ドキュメント：README のパッケージ表に押し出し・地形・空を足し、`TERRAIN_TEXTURE` の説明を直した。
- コメント：3 行を超えていたシェーダーの説明（線、円、文字、押し出し、地形）を縮めた。

### 速度（§7.5）

| 候補 | 結果 | 判断 |
|---|---|---|
| 地形のテクスチャを、ズーム・方位・重なるタイル・タイルの中身の版（`content_version`）が変わらない間は使い回す | 地形・45° のパンで 1 フレームの CPU（p50）が 0.70〜0.78 → 0.39〜0.44ms（`main` と交互に各 3 回 × 2 巡）。ラベル＋地形のパンも 0.57〜0.83 → 0.27〜0.56ms。ズーム中は毎フレーム描き直すので変わらない（0.73〜0.80 → 0.78〜0.83ms） | 採用 |
| ラベルの遮蔽用の深度パスを、symbol レイヤーがないときは描かない | 上の計測に含む | 採用 |
| 描画先テクスチャ：全ズームのタイル以外は 512 px、予備は 32 → 8 枚 | GPU メモリの削減（下の S1） | 採用 |

- 11 回の計測（`render-chromium-terrain.json`、`-labels-terrain.json`、`render-chromium.json`）は、MapLibre の値も前回より 3〜6 割高く、マシンが遅い状態で取れた。そのため効果は上の交互の計測で判断した。
- 11 回の値は、地形・45° の mbmap が pan 0.71 / pan-back 0.60 / zoom-in 1.32 / zoom-out 1.36ms、MapLibre が 1.66 / 2.72 / 2.25 / 2.62ms。
- 地形なしの描画は変わらない（idle 115ms、p50 0.55〜0.70ms）。
- main バンドル：43.1KB → 43.5KB。

### セキュリティチェック（§8）

| # | 重要度 | 場所 | 内容 | 対応 |
|---|---|---|---|---|
| S1 | 中 | `map/terrain.mbt` の描画先 | dpr 2 では描画先が 1 枚 4MB。高いピッチで地形を見ると、表示中のタイル分に予備 32 枚が加わり、GPU メモリが数百 MB に達しうる | 全ズームのタイル以外は 512 px、予備は 8 枚にした |

- 依存関係：npm audit は bench/・npm/ とも 0 件。Dependabot の未解決アラートなし。固定している版（maplibre-gl 6.16.0、playwright 1.64.1、esbuild 0.28.2、binaryen 132.0.0、typescript 7.0.2、pbf 5.1.2）にも GitHub Advisories の該当なし。moon は 0.1.20261028。
- 信頼できない入力：
  - DEM タイルは一辺 1024 まで。Worker の出力はその範囲で、線形メモリの確保も確かめている。
  - 押し出しの高さは NaN を 0 にして 0〜6553.5m に切る。頂点数は `MAX_PACKED_BYTES` の範囲。
  - `sky`・`light`・`terrain`・`fill-extrusion` の値は不正なら Invalid か Unsupported。ブレンド値は 0〜1 に収める。有限でない誇張率は `with_elevation` が無視する。
- Web：`innerHTML`・`eval`・`new Function` は使っていない。タイルと標高タイルは `credentials: "omit"` で取得。wasm は同一オリジンの URL から読む。開発用サーバーのテスト（`bench/lib/serve.test.mjs`）は通る。

## Phase 10.5：fill-extrusion（建物の押し出し）（2026-11-01）

状態：**完了**。Phase 10（3D：DEM、地形、ピッチ 85°、空と霧、地形上のラベル、押し出し）を終えた。

### ユーザー判断（2026-11-01）

- 高さの渡し方：Worker で頂点に入れる（MapLibre と同じ。PLATEAU のように建物ごとに違う高さも描ける）。
- 地形との組み合わせ：10.5 で、建物を地形の高さに乗せる。

### できたこと

- **`style`**：
  - `fill-extrusion` レイヤー（`-color`、`-opacity`、`-height`、`-base`、`-vertical-gradient`）。`-pattern` と、0 でない `-translate` は Unsupported にした。
  - ルートの `light`（`anchor`、`color`、`intensity`、`position`。既定値は Style Spec のもの）。
- **`tess`**（`ExtrusionTessellator`）：
  - MapLibre の fill-extrusion bucket の移植。壁はリングの辺ごとに 1 枚の四角で、タイルの切れ目に沿う辺（`isBoundaryEdge`）には作らない。タイルの外に丸ごと出ているリングにも作らない。
  - 屋根は塗りと同じく三角形に分ける。
  - 法線と上端の印の詰め方も MapLibre と同じ。重心は閉じる点を除いた点の平均（MapLibre はポリゴンごと、mbmap は地物ごと）。
- **Worker**：
  - 地物ごとの基部と高さを、タイルのズームとその 1 段下で評価して頂点に入れる（`KIND_EXTRUSION` 6、1 頂点 24 バイト、docs/FORMATS.md）。
  - 描くときはズームの小数部で 2 つの値の間を補間する。MapLibre の、ズームと地物の両方を読む式の扱いと同じ。
  - 高さは 0.1m 単位の u16（0〜6553.5m）。グループ分けは色だけで、同じ形のレイヤーとバッファは共有しない。
- **描画**：
  - MapLibre の fill_extrusion シェーダーの移植（照明、壁の上下のグラデーション）。深度テストを使う。
  - 半透明のときは、まず深度だけ、次に一番手前の面の色の 2 パスで描く。
  - 地形があるときも地形のテクスチャには描かず、画面に直接、地形の深度と比べて描く。
  - 地形の上では、各建物を重心の地面の高さに置く。ラベルと同じく DEM が届いたときだけ求め直し、地面の高さの地物（base が 0）は 10m 下まで壁を伸ばす（MapLibre と同じ）。
- **example**：`examples/basic?buildings=1`。国土地理院のタイルには高さがないので、堅ろう建物（ftCode 3103）は 30m、ほかは 8m にした。
- **bench**：`render/run.mjs --extrusion`（同じ建物の押し出しを両方のエンジンで、ピッチ 45°）。
- **NOTICE**：10.1 から移植してきた MapLibre GL JS の部分（hillshade の勾配とシェーダー、空、霧、ラベルの遮蔽と遠近の大きさ、地平線、縦書きの約物、押し出し）の記載が抜けていたので足した。

### 確かめたこと

- 同じスタイル・同じカメラの MapLibre とスクリーンショットで見比べた。壁の明暗の向きと屋根の色はほぼ同じ。
- 地形あり（誇張 8 倍）でも崩れずに描けることを確かめた。

### 計測（`render-chromium-extrusion.json`、`render-chromium.json`）

条件は 10.2 と同じ（Chromium、Metal、1280×800、dpr 2、11 回の中央値）。建物は中心のタイルで約 1,900 棟。

| | mbmap | MapLibre 6.16.0 |
|---|---|---|
| 押し出し・45°：最初の idle | 181ms | 398ms |
| 押し出し・45°：1 フレームの CPU（p50 / p95） | 0.58〜0.91 / 1.19〜1.37ms | 1.34〜2.05 / 2.34〜2.52ms |
| 地形なし・0°：最初の idle | 114ms | 232ms |
| 地形なし・0°：1 フレームの CPU（p50） | 0.58〜0.73ms | 1.48〜1.78ms |

- 地形なしの描画は、pan-back だけ 0.58 → 0.73ms で、ほかの 3 つは変わらない。MapLibre も少し上がっているので揺れとみる。

### サイズ（gzip）

- main バンドル：40.9KB → 43.1KB（増えたのは主にシェーダーの文字列）
- 表示用 Worker：87.3KB → 89.6KB（予算 100KB）

### 既知の問題・次にやること

- 色の不透明度（`fill-extrusion-color` の alpha）は、MapLibre では色を暗くするだけだが、mbmap では全体の不透明度に掛かる。
- ソースの maxzoom より深く拡大したタイルでは、高さは 1 段下の値のまま（補間の係数を 1 で止める）。
- 地形の深度にはまだ建物が入らないので、建物の陰のラベルは隠れない（MapLibre も同じ）。
- Phase 10 の次は、VISION §8 の Phase 11。

## Phase 10.4：ラベルを地形の高さに置く、地形による遮蔽、遠近の大きさ（2026-11-01）

状態：**完了**。

### できたこと

- **地形の高さ**：
  - ラベルの位置の標高は、その地点を覆う読み込み済みで一番細かい DEM タイルから、地形のシェーダーと同じ補間（画素の中心の間の双線形）で求める。
  - 求め直すのは DEM タイルが届いたときだけ（`dem_version`）。
  - 結果（メートル）を頂点ごとの属性にして GPU に送る。シェーダーで「標高 × 1m あたりの世界ピクセル（誇張込み）」だけ持ち上げる。衝突判定も同じ高さで行う。
- **遮蔽**：
  - 毎フレーム、地形の格子を深度テクスチャ（キャンバスと同じ大きさ、深度だけ）にもう一度描く。
  - ラベルのシェーダーで、その深度と比べて地形に隠れるものを薄くし、消す。式は MapLibre の `calculate_visibility` と同じ（NDC で 0.0001 の余裕、500 倍で薄くする、少し上の点も見て平均）。
- **遠近の大きさ**（地形がなくても）：
  - 文字の大きさと衝突用の箱に、MapLibre の perspective ratio（0.5 + 0.5 × 中心までの距離 ÷ ラベルまでの距離）を掛ける。
  - ratio が 0.6 未満（カメラの距離の 5 倍より遠い）のラベルは置かない（MapLibre の `perspectiveRatioCutoff`）。地平線の近くにラベルが密に並ぶ問題が減った。
- **example**：`examples/basic` に `?center=経度,緯度` を足した。

### 試したこと

- 最初は、ラベルのタイルの DEM（そのタイルか祖先）を標高テクスチャとしてシェーダーで引いた。しかし DEM タイル（256 画素なので 1 段深い）のほうがラベルのタイルより細かいと、祖先に DEM が見つからない。標高が 0m になり、ラベルが地中に埋まって、見えている斜面のラベルまで消えた。地点ごとに一番細かい DEM から CPU で求める形に変えた。
- 遮蔽を切ったビルドと見比べて確かめた（配信中のタイル、富士山の南からピッチ 72°）。山の向こう側のラベル（河口湖、吉田口登山道など）は消え、手前の斜面のラベル（富士宮口登山道、新五合、馬返）は地形の高さに出る。

### 計測（`render-chromium-labels.json`、`render-chromium-labels-terrain.json`）

条件は 10.2 と同じ（Chromium、Metal、1280×800、dpr 2、11 回の中央値）。ラベルは examples/basic の symbol レイヤーで、両エンジンともローカルのフォント。地形はピッチ 45°。

| | mbmap | MapLibre 6.16.0 |
|---|---|---|
| ラベル：最初の idle | 198ms | 268ms |
| ラベル：1 フレームの CPU（p50 / p95） | 0.47〜0.58 / 0.94〜1.03ms | 1.30〜1.86 / 2.66〜2.86ms |
| ラベル＋地形：最初の idle | 284ms | 566ms |
| ラベル＋地形：1 フレームの CPU（p50 / p95） | 0.72〜0.80 / 1.33〜1.44ms | 2.17〜3.23 / 3.61〜4.00ms |

- ラベルありの描画を `main` のビルドと交互に測った（各 3 回 × 2 巡）。1 フレームあたり 0〜0.07ms の差で、揺れと区別できない。
- 同じ日の最初の 11 回の計測は、両エンジンとも 5〜6 割高く出た（マシンの状態）。上の表は取り直した値。

### サイズ（gzip）

- main バンドル：39.9KB → 40.9KB
- 表示用 Worker：変わらない（87.3KB）

### 既知の問題・次にやること

- 地形の格子は 4 画素おきの直線補間なので、谷のような凹んだ所では、ラベル（DEM の値そのもの）が描いた地面より少し下になり、余裕（0.0001）を超えると消えることがある。MapLibre も同じ作り。
- 衝突判定では、地形に隠れるラベルも場所を取る（MapLibre も同じで、遮蔽は描くときだけ）。
- 地形の深度を、ラベルのためだけに毎フレームもう一度描いている。テクスチャの使い回しと合わせて、まとめて減らせる。
- 10.5 で fill-extrusion を入れた（10.5 節）。

## Phase 10.3：ピッチ 85°、地平線、空、霧（2026-11-01）

状態：**完了**。

### できたこと

- **`core`**：
  - `MAX_PITCH` を 60° から 85° にした（MapLibre と同じ）。
  - 地平線は MapLibre の `getMercatorHorizon` と同じ位置にした（本当の地平線の 85% の所、真下から 89.25° まで）。70° あたりから画面に入る（`Transform::horizon`）。
  - 地面は地平線の線までで、far 面もその深さに置く。線より上の画面の点は、線上の地面に対応させる（パンやズームの基準点が空にあっても破綻しない）。
  - 遠くのタイル選び：ソースの `minzoom` より `MIN_ZOOM_SLACK`（2）段以上低いズームを望む遠くの地面には、タイルを置かない（MapLibre は 1 段でも下なら置かない）。85° でも、遠くは中心から 2 段下までに収まる。
  - `Transform::fog_range`：MapLibre の fog 行列と同じ深さの範囲（海面までのカメラの距離から far 面まで）。
- **`style`**：ルートの `sky`（`sky-color`、`horizon-color`、`fog-color`、`fog-ground-blend`、`horizon-fog-blend`、`sky-horizon-blend`。ズームの式も可）。省いた値は Style Spec の既定値にする。`sky` がないときは、MapLibre と同じく空も霧も描かない。`atmosphere-blend` は地球儀用なので読まない。
- **描画**：
  - 空：画面全体の四角形で、地平線より上を MapLibre の sky シェーダーと同じ式で塗る。
  - 霧：地形のシェーダーで、MapLibre の terrain シェーダーと同じ式（深さは `gl_Position.w` から fog 行列と同じ値を出す。ガンマ 2.2 で混ぜる）。ピッチ 60° から 70° で効き始める。
  - 地形のない 2D の地図には霧をかけない（MapLibre と同じ）。
- **ピッチの上限**：`<mb-map>` の `pitch` 属性を 0〜85 に、npm の README も更新した。
- **example**：地形の例と `examples/basic?terrain=1` に `sky` を足した。`?pitch=85` で地平線と空が見える。
- **bench**：`render/run.mjs` に `--pitch=N` を足し、`--terrain` のスタイルに `sky` を足した。MapLibre の既定の `maxPitch` は 60 なので、ベンチのページで 85 にした。

### 確かめたこと

- 同じ条件（地形、ピッチ 85°）で MapLibre とスクリーンショットを見比べた。地平線の高さと空のグラデーションは一致した。
- 霧の色を一時的に赤にして、地平線の近くだけに霧がかかり、端で地平線の色に変わることを確かめた。

### 計測（`bench/results/render-chromium-terrain.json`、`render-chromium-terrain-pitch85.json`、`render-chromium.json`）

条件は 10.2 と同じ（Chromium、Metal、1280×800、dpr 2、11 回の中央値）。地形のスタイルには `sky` が付く。

| | mbmap | MapLibre 6.16.0 |
|---|---|---|
| 地形・45°：最初の idle | 164ms | 465ms |
| 地形・45°：1 フレームの CPU（p50 / p95） | 0.77〜0.89 / 1.22〜1.41ms | 1.27〜1.72 / 2.52〜2.77ms |
| 地形・85°：最初の idle | 215ms | 363ms |
| 地形・85°：1 フレームの CPU（p50 / p95） | 1.31〜1.48 / 1.73〜2.00ms | 1.32〜1.78 / 2.18〜2.89ms |
| 地形なし・0°：最初の idle | 116ms | 221ms |
| 地形なし・0°：1 フレームの CPU（p50） | 0.58〜0.71ms | 1.38〜1.70ms |

- 85° では、p50 は MapLibre とほぼ同じ。mbmap は地形のテクスチャを毎フレーム描き直し、遠景もベクトルタイル（z14）を描くが、MapLibre は遠くの地形タイルが z13 以下になり、そこには貼るベクトルタイルがない。
- 地形なしの描画は変わらない（前回は idle 115ms、p50 0.56〜0.69ms）。
- 地形・45° で `main` のビルドと交互に測った（各 3 回 × 2 巡）。1 フレームあたり 0.03〜0.06ms（約 5%）増えた。霧の値の評価など、フレームごとの処理が少し増えたため。なお、同じ日の最初の 11 回の計測は、MapLibre も含めて全体に 2〜4 割高く出た（マシンの状態）。上の表は取り直した値。

### サイズ（gzip）

- main バンドル：38.5KB → 39.9KB
- 表示用 Worker：86.9KB → 87.3KB

### 既知の問題・次にやること

- 地形のテクスチャを毎フレーム描き直している（10.2 から）。高いピッチでは遠くのタイルが増えるので、使い回しの効果は大きいはず。
- 遠くのラベルが地平線の近くに密に並ぶ問題は、10.4 で perspective ratio を入れて扱った（10.4 節）。

## Phase 10.2：3D 地形（地図を地形に貼る、カメラを地面の高さに）（2026-11-01）

状態：**完了**。

### ユーザー判断（2026-11-01）

- 地形の描き方：地図をタイルごとのテクスチャに描いて、起伏に貼る（MapLibre と同じ考え方）。
- ラベル：地形の高さに置き、地形に隠れるものは隠す（遮蔽）までやる。
- ピッチ：85° まで上げる。
- これを受けて、残りを 10.2（地形に貼る、カメラを地面の高さに。ピッチは 60° のまま）、10.3（85° のピッチ、地平線、空、霧、遠景の LOD）、10.4（ラベルを地形の高さに置き遮蔽する）、10.5（fill-extrusion）に分けた。

### できたこと

- **`style`**：ルートの `terrain`（`source` は `raster-dem` ソース、`exaggeration` は 0 以上）。違反は場所付きの Invalid。
- **Worker**：DEM タイルの出力に、標高（f32、データなしは 0m）を足した（docs/FORMATS.md）。
- **`core`**：
  - `Transform` に中心の高さ `elevation`（メートル）を持たせ、ビュー射影で `pixels_per_meter` 倍して持ち上げる。持ち上げても画面の中心は中心のまま（テスト）。
  - `ByteWriter::f32`。
- **描画**（`map/terrain.mbt`、`render_webgl2`）：
  - 地形タイルのズームは、表示のズーム（または DEM のほうが深ければ DEM の）に合わせる。DEM が粗いときは、読み込み済みの祖先の DEM タイルの一部分を使う。
  - 毎フレーム、地形タイルごとに symbol 以外のレイヤーを、512 × 端末のピクセル比（2 まで）のテクスチャに描く。
  - そのあと 65×65 の格子を、標高（R32F のテクスチャ。float は線形補間できないので、頂点シェーダーで手で補間）で持ち上げて描く。深度テストを使い、縁には「スカート」を下げて継ぎ目のすき間を隠す。
  - symbol レイヤーは、その上に画面に重ねて描く（地形の高さに置くのは 10.4）。
  - カメラの中心は、中心の真下の標高（読み込み済みで一番深い DEM タイルから補間）× `exaggeration` だけ持ち上げる。
- **example**：`examples/terrain` を、富士山の陰影起伏を立体の地形に貼る例にした。`examples/basic` は `?terrain=1`（と `&exaggeration=`）で東京を地形に貼る。

### 試したこと

- 地形タイルを DEM タイル（z14、256 画素なので 1 段深く選ぶ）そのものにすると、z15 以上で近くが 512 画素のテクスチャを引き伸ばす形になり、ぼやけた。表示のズームに合わせ、DEM はその一部分を使う形に変えて解消した。
- タイルの境目に点線が出た。地形のシェーダーが、ほかのレイヤーと同じクリップ（`v_pos >= 4096` で捨てる）を使っていたため。地形タイルは重ならないので、クリップをやめた。

### 計測（`node render/run.mjs --terrain`、`bench/results/render-chromium-terrain.json`）

条件：Chromium、Metal、1280×800、dpr 2、11 回の中央値。両方のエンジンに同じ標高タイルを読ませるため、fixtures の国土地理院の標高タイルを Terrarium 形式の PNG に変換し（データなしは 0m）、z13・z12 は z14 を半分に縮めて作った。MapLibre の `custom` エンコーディングでは、国土地理院の負の値とデータなしを表せないため。

| | mbmap | MapLibre 6.16.0 |
|---|---|---|
| 最初の idle | 165ms | 465ms |
| 1 フレームの CPU（p50）：pan / pan-back / zoom-in / zoom-out | 0.83 / 0.93 / 0.95 / 0.96ms | 1.35 / 2.08 / 1.38 / 1.75ms |
| 1 フレームの CPU（p95） | 1.22〜1.48ms | 2.67〜2.89ms |

- ピッチは 45°。60° では、MapLibre は遠くの地形タイルを z13 以下で作り、そこにはベクトルタイル（fixtures は z14 だけ）がないので空白になる。45° でも画面の左右の端は MapLibre だけ描かない。描く量は MapLibre のほうが少ない条件での比較になる。
- 地形なしの描画（`node render/run.mjs`）は変わらない：mbmap の最初の idle は 114 → 115ms、1 フレームの CPU（p50）は 0.55〜0.72 → 0.56〜0.69ms。
- CPU だけの比較。mbmap はテクスチャを毎フレーム描き直すので、GPU の負担は MapLibre（変わらないタイルのテクスチャを使い回す）より大きいはず。

### サイズ（gzip）

- main バンドル：35.4KB → 38.5KB
- 表示用 Worker：86.4KB → 86.9KB

### 既知の問題・次にやること

- テクスチャを毎フレーム全部描き直している。カメラだけが動くときは使い回せる（MapLibre の RTT キャッシュと同じ）。
- 地形タイルのテクスチャは、一番近いタイルでも 512 × ピクセル比。近くを拡大すると、まだ少し粗い。
- hillshade レイヤーの描画の速さは、まだ MapLibre と比べていない（ベンチのスタイルに hillshade がない）。
- 10.3 で、ピッチ 85°、地平線、空、霧を入れた（10.3 節）。

## Phase 10.1：標高タイル、陰影起伏（hillshade）レイヤー、地形解析（2026-11-01）

状態：**完了**。Phase 10 は、10.1（DEM、hillshade、地形解析）、10.2（3D 地形）の順に進め、その先は 10.2 節の分け方に従う。

### ユーザー判断（2026-11-01）

- 進め方：DEM → 3D 地形 → 押し出しの順。
- データ：国土地理院の標高タイル。
- 答え合わせ：GDAL の gdaldem と比べる。

### できたこと

- **`style`**：
  - `raster-dem` ソース。`tiles` と `tileSize`（128 / 256 / 512）を読み、`encoding` は MapLibre の `mapbox`・`terrarium`・`custom` に対応した。
  - さらに mbmap の拡張として `"gsi"` を足した（国土地理院の 0.01m 単位。負の値と、データなしの値 2^23 も扱う）。
  - `hillshade` レイヤー（MapLibre の `standard` 方式の paint）。ほかの方式（`hillshade-method`）は Unsupported にした。
- **`raster`**（純 MoonBit、全ターゲットでテスト）：
  - RGB から標高への変換。
  - MapLibre の hillshade_prepare と同じ勾配（1画素2バイト）。
  - タイルの縁の標高（`dem_edges`）と、隣のタイルを使って縁の勾配を計算し直す `edge_slopes`。テストでは、1枚の大きなタイルで計算した値と一致することを確かめた。
- **表示**：
  - Worker は PNG を `createImageBitmap`（色の変換なし）で画素にし、wasm で勾配と縁の標高を作る。
  - メインスレッドは勾配を RG8 のテクスチャにし、隣のタイルが読み込まれたら縁の行・列だけを差し替える（MapLibre の backfillBorder と同じ考え方）。
  - 256 画素のタイルは1段深いズームで選ぶ（`@core.zoom_shift`）。
  - 富士山の例（`examples/terrain`）を作り、同じタイル・同じ paint の MapLibre とスクリーンショットで見比べた。陰影の付き方はほぼ同じ。縁を計算し直すまでは、タイルの境目に細い筋が出ていた。
- **地形解析**（`@analysis.Grid`、`mbmap/analysis` の `loadDem`）：
  - 範囲を指定して標高タイルを並べ、1つの格子にする（一辺 4096 セルまで、§8.2）。
  - 標高、勾配、斜面方位、陰影起伏を求める。
  - 式は GDAL 3.13.3 の gdaldem_lib.cpp（Horn の方法）を読んで写した。三角関数は `Trig` 経由で、解析用の wasm ではホストの `Math` を使う。
  - はじめは `raster` に置いていたが、MoonBit の `@math` の三角関数が解析用の wasm に入り、29.1KB になった。`analysis` に移して `Trig` を通すようにし、25.1KB にした。
- **fixture**：国土地理院の標高タイル。東京駅周辺 z14 の 35 枚と、富士山周辺 z12 の 16 枚。マニフェストで固定し、取得スクリプトは複数のセットを扱えるようにした。
- **ベンチの道具**：依存を足さずに、Node の zlib で動く小さな PNG デコーダ（`bench/lib/png.mjs`）を書いた。テストあり。

### 黄金テスト（`npm --prefix bench run terrain:golden`、富士山の 1024×1024 セル）

配布する解析用の wasm と GDAL 3.13.3 の gdaldem を比べた。GDAL は縁のセルをデータなしにするので、内側を比べる。

| | 比べたセル | 完全一致 | 最大の差 | 許容 |
|---|---|---|---|---|
| 勾配（度） | 1,044,484 | 5,828 | 0.0005° | 0.01° |
| 斜面方位（度） | 1,032,909 | 202 | 0.04° | 0.01° ＋ float32 の誤差の分 |
| 陰影起伏（1〜255） | 1,044,484 | 1,044,447 | 1 | 1 |

- GDAL は float32 で計算する（標高も float32 で読む）ので、ビット単位では一致しない。
- 斜面方位は、緩い斜面ほど標高の丸め誤差（相対 2^-24）が角度に大きく出る。誤差の上限から、セルごとの許容を出した：0.01° ＋ atan(8 × 最大標高 × 2^-24 ÷ Horn の和)。勾配 0.5° 未満のセルは比べない。
- 陰影起伏は、37 セルだけ 1 違う（GDAL が平方根を近似しているため）。

### サイズ（gzip）

- main バンドル：32.4KB → 35.4KB
- 表示用 Worker：83.6KB → 86.4KB（予算 100KB）
- 解析用 Worker：22.3KB → 25.1KB（予算 30KB）
- `mbmap/analysis`：1.4KB → 1.8KB

### 既知の問題・次にやること

- 角のピクセル（斜め隣のタイルが要る）は、縁を繰り返したまま。
- `hillshade-method` は `standard` だけ。照明の高さ（`hillshade-illumination-altitude`）は読まない。
- 次は 10.2（3D 地形）。

## Phase 9.2：縦書き、`symbol-sort-key`、MapLibre との比較（2026-11-01）

状態：**完了**。Phase 9 を終えた。

### できたこと

- **縦書き**（`text-writing-mode` の最初の値が `vertical` のとき）：
  - 漢字・かななどは立てたまま、右の列から縦に並べる。ラテン文字・数字・長音符（ー）は時計回りに横倒しにする。
  - 括弧と句読点は縦書き用の字形（︵︶︑︒ など）にする。対応表と「隣が横倒しの文字なら置き換えない」という規則は MapLibre と同じ。
  - 立てる文字の判定は、UAX #50 の一部（CJK、かな、ハングル、全角・縦書き用の字形）を範囲で書いたもの。
  - 立てる文字を含まないテキストは横書きのまま。
  - 文字の四角形（クワッド）は4隅で持つようにした。横倒しの文字は四角形ごと回す。
- **`symbol-sort-key`**：Worker が地物ごとに評価する。値の小さいラベルを先に置き、先に描く（同じタイル・同じエントリーの中で）。
- **example**：国土地理院の `arrng` 2 と 4 を縦書きのレイヤーに分け、`annoCtg` を sort key にした。

### 計測の不具合と訂正

- 描画ベンチ（`bench/render/page.mjs`）は、MapLibre に渡すタイルの URL を `new URL()` で解決していた。このとき `{z}/{x}/{y}` の波括弧が `%7B…%7D` に変換され、MapLibre のタイル要求がすべて 404 になっていた。
- そのため **Phase 3 以降の「mbmap と MapLibre の描画の比較」は、空の地図を描く MapLibre と比べていた**。初回描画が「ほぼ同じ」、1フレームの CPU が「約 1/3〜1/4」という結論は無効。該当する表に訂正の注記を付けた。
- 影響しないもの：
  - mbmap 自身の数値。
  - VISION §2 の基準値。これは `bench/maplibre`（Phase 0）で測っていて、正しく描けている。今回の測り直しでも、MapLibre の初回描画は 215ms で一致した。
- URL をそのまま渡すように直し、両方のエンジンがタイルとラベルを描くことをスクリーンショットで確かめた。結果が出ないときに、どちらのエンジンかがわかるエラーにした。

### ベンチ結果（Chromium 156 + ANGLE Metal / M2、1280×800、DPR 2、11回の中央値、`bench/results/render-chromium*.json`）

CPU は1フレームの rAF の CPU 時間で、4つのシナリオの平均（p50 / p95）。

| スタイル | 指標 | mbmap | MapLibre 6.16.0 |
|---|---|---|---|
| `style.json`（ラベルなし） | 初回描画 | **114ms** | 215ms |
| | CPU（vsync あり） | **0.64 / 1.03ms** | 1.63 / 2.23ms |
| | CPU（vsync なし） | 1.21 / 2.70ms | 1.66 / 2.74ms |
| ラベルあり（`--labels`） | 初回描画 | **198ms** | 268ms |
| | CPU（vsync あり） | **0.43 / 0.89ms** | 1.55 / 2.56ms |
| | CPU（vsync なし） | 1.76 / 2.81ms | 1.20 / 2.75ms |

- ラベルありのスタイルは、`style.json` に `examples/basic` のラベルのレイヤー（横書き・縦書き）を足したもの（`render/run.mjs --labels` が実行時に作る）。両方のエンジンとも、文字はローカルのフォントから TinySDF で描く。MapLibre はスタイルに `glyphs` がないので、すべての文字をローカルで描く。
- **初回描画は、ラベルなしで MapLibre の約半分、ラベルありで約 3/4**。VISION §2 の「215ms 未満」は、ラベルありでも満たしている。
- vsync ありの1フレームの CPU 時間は、MapLibre の 1/3〜1/4。代理指標の目標（p95 1.44ms 以下、20ms 超のフレーム 0）も満たした。
- vsync なしでラベルありのときは、CPU の中央値が MapLibre より大きい（1.76 対 1.20ms）。mbmap はカメラが動いている間、100ms ごとにラベルを置き直し、毎フレーム描く。p95 は同じくらい。
- ラベルを入れると、mbmap の初回描画は 114ms から 198ms に延びた（+84ms）。主な原因は、Worker（4つ）がそれぞれ同じ文字の SDF を描くこと（1文字約 0.1ms、約 1,000 字）。Worker の間で分担するか共有すれば短くできる見込みで、次の課題にする。
- サイズ（gzip）：mbmap はメイン 30.7KB・Worker 83.6KB、MapLibre はメイン 295.5KB・Worker 148.0KB。

### リファクタリング点検（同じ PR に追加）

- **重複**：`text.mjs` で、立てた文字の4隅を作る処理が横書きと縦書きの2か所にあったので、1つの関数（`standing`）にまとめた。
- **重複したデータ**：ラベルありのベンチ用スタイル（`bench/maplibre/style-labels.json`）を手で作って commit していた。これは `examples/basic` のラベルのレイヤーの写しで、片方を変えるとずれる。`render/run.mjs --labels` が実行時に作るようにして、ファイルは消した。結果ファイルの `env.style` の書き方だけ、それに合わせた。
- **コメント**：`layoutLabel` の JSDoc を3行以内にした。
- テスト、pack テスト、見た目（スクリーンショット）は変わらない。

### 既知の問題・次にやること

- 4回続けて測ったとき、ラベルありの1回目が 120 秒で止まった（どちらのエンジンかは記録できていなかった）。11回の測定を2回やり直したが、再現しなかった。今はエンジン名を出すようにしてある。
- 同じ文字の SDF を Worker ごとに描いている（初回描画 +84ms の主因）。
- 9.1 からの残り：傾けたときに遠くのラベルを小さくすること、フェード、アトラスが満杯になったときの対応、線に沿ったラベル、アイコン。
- 次は VISION §8 の Phase 10（地形（DEM）、`fill-extrusion`、ラスタ解析）。

## Phase 9.1：点のラベル（横書き）（2026-11-01）

状態：**完了**。国土地理院のラベルが日本語で表示される。重なりは隠し、回転・傾けにも追従する。縦書きと MapLibre との比較は 9.2 で行う。

### ユーザー判断（2026-11-01）

- グリフは Worker の `OffscreenCanvas` で作る。
- 衝突判定は、メインスレッドで全タイルをまとめて行う。
- 範囲は、点のラベルと縦書き。Phase 9 を 9.1（横書きまで）と 9.2（縦書き、`symbol-sort-key`、MapLibre との比較）に分ける。

### できたこと

- **`style`**：symbol レイヤー（`symbol-placement: point`）。
  - `text-field` は `{key}` の書き方、`get`、`concat`、`to-string` を、つなぐ部品の列にする。数値は Worker の JS 側で文字列にする（wasm に浮動小数点数の文字列化を入れないため）。
  - `text-size`（式も可）、`text-anchor`、`text-offset`、`text-max-width`、`text-line-height`、`text-padding`、`text-allow-overlap`、`text-ignore-placement`、`text-color` / `text-opacity` / `text-halo-color` / `text-halo-width` を読む。
  - 線に沿った配置、アイコン、`format` は Unsupported にした。`text-font` は読まない（文字はブラウザにあるフォントで描く）。
- **Worker（wasm）**：点ごとにアンカー、`text-size`、`text-field` の部品を詰める（docs/FORMATS.md の「Labels」）。タイルの外のアンカーは、そのアンカーを持つタイルに任せる。
- **Worker（JS）**：
  - TinySDF 2.3.0 で、SDF グリフを 48px で描く。グリフは Worker ごとに1回だけ送る。
  - `text.mjs` が文字を配置する。改行（行頭・行末の禁則を含む）、アンカー、揃え、オフセットを扱う。テストは `npm test` にある。
  - ラベルは 256 文字まで、角のオフセットは i16 の範囲に収める（§8.2）。
  - Worker が持つグリフは 4096 字まで、1タイルで新しく描くのは 1024 字までにした（§8.2。自動のセキュリティレビューの指摘）。超えた文字は空白になる。
- **メインスレッド**：
  - グリフは 2048×2048 のアトラスに棚詰めする（`label.Atlas`）。
  - 文字の四角形（クワッド）のグリフ番号を、アップロードの前にアトラスの座標へ書き換える。メインスレッドが頂点に触れるのは、ここだけ。
  - 衝突判定は、画面のグリッド（`label.Grid`）で、上のレイヤーから順に行う。新しいタイルが届いたときと、カメラが動いている間は 100ms ごとに置き直し、表示するラベルのインデックスだけを GPU に送る。
  - SDF シェーダーで、縁取り（halo）を描いてから文字を描く。文字は画面上で一定の大きさで、常にこちらを向く。
  - Map のオプション `fontFamily` を足した。
- **example**：basic・npm・element の例のスタイルに、ラベルのレイヤーを足した。pack テストで、パッケージ経由の経路も通している。

### 計測

- **サイズ（gzip）**：
  - main バンドル：27.3KB → 32.2KB（予算 50KB 以内）。
  - 表示用 Worker：76.1KB → 82.2KB。TinySDF と文字の配置で JS が約 3KB、ラベルの取り出しと読み込みで wasm が約 3KB 増えた。VISION §2 の目標（80KB）を超えたので、目標を 100KB に上げた（下記）。
- **描画ベンチ**（`bench/results/render-chromium*.json`、ラベルのないスタイル、5回の中央値）：遅くなっていない。
  - 上限なしのフレーム CPU の中央値：mbmap 1.67 → 1.71ms、MapLibre 0.16 → 0.14ms。
  - 上限ありでは mbmap 0.41 → 0.62ms だが、コードを変えていない MapLibre も 0.88 → 1.39ms だった。MapLibre との比（0.47 → 0.45）は変わらない。
  - （9.2 で訂正：この MapLibre は空の地図を描いていた。上限なしの mbmap の値が変わらないことが、遅くなっていない根拠になる。）
- **見つけて直した問題**：ラベルのないスタイルでも、カメラが動いている間は 100ms ごとに配置を実行し、合間に余分なフレームを要求していた。symbol レイヤーがなければ配置しないようにした。
- ラベルを含むスタイルでの MapLibre との比較（最初の描画、フレーム CPU）は 9.2 で行う。

### 表示用 Worker のサイズ目標（100KB に上げた）

表示用 Worker は 82.2KB で、VISION §2 の目標の 80KB を超えた。選択肢は次のとおり。

- A. 目標を 90KB に上げる。ラベルは表示の基本機能なので、表示用 Worker に入れるのが自然。
- B. 80KB を守る。削れる候補は、TinySDF の距離変換を wasm に移すこと（JS が減り、wasm が増える。差は小さい見込み）くらいで、効果ははっきりしない。

**決定（2026-11-01、ユーザー確認）：目標を 100KB にする**（VISION §2 と `npm/scripts/size.mjs` に反映した）。

### リファクタリング点検（同じ PR に追加）

- **定数**：ラベル1件あたりの浮動小数点数の個数を `LABEL_FLOATS` にした（JS と MoonBit で互いを指すコメント付き）。ラベルのバイト列のヘッダの位置にも名前を付けた（`HEADER`）。
- **重複**：
  - 属性値をタグ付きで書く処理を、MoonBit の `write_value` 1つにまとめた（ラベルとグループの属性で共有）。
  - 読む処理も、JS の `values.mjs` の `readValue` / `readString` 1つにまとめた。
- **ホットパスの割り当て**：ラベル用のバッファがタイルごとに作り直されていた。`@core.ByteWriter::clear` を足して使い回すようにした。
- **テスト**：`buildSymbols` の単体テストを足した。偽のグリフ寸法を使うので、`OffscreenCanvas` がなくても動く。頂点の並び、ラベルの表、文字数の上限、オフセットのクランプを確かめている。
- **コメント**：`text.mjs` の長い JSDoc を縮めた。
- 見た目（スクリーンショット）、サイズ、pack テストは変わらない。

### 既知の問題・次にやること

- 縦書き（GSI の `arrng` 2 と 4）と `symbol-sort-key` は 9.2 で行う。
- 傾けたとき、遠くのラベルも同じ大きさで並ぶ（MapLibre は遠くを小さくし、減らす）。
- フェードはない（ラベルは表示・非表示がすぐ切り替わる）。
- アトラスが満杯になると、それ以降の文字は欠ける（警告を1回出す）。広い範囲を見ると起きうるので、作り直しか追い出しを後で入れる。
- `OffscreenCanvas` のないブラウザ（Safari 16.4 より前）では、ラベルを出さない。

## Phase 8：`mbmap/analysis` 第1弾（空間索引、計測、空間クエリ、集計）（2026-11-01）

状態：**完了**。

### ユーザー判断（2026-11-01）

- 範囲は「標準セット」にした（索引、計測、空間クエリ、集計）。
- データは「データセットのハンドル」で渡す。読み込んだデータと索引は Worker の中に置き、呼び出しでは結果だけを返す。
- 解析の wasm に GeoJSON の読み込みも入れる。
- 長い数の読み込みは、ホストの `Number()` を使う今の形にする（2026-11-01。下の「長い数の読み込み方」）。

### できたこと

- **`analysis`**（純 MoonBit、全ターゲットでテスト）：
  - `Index`：flatbush 4.6.2 の移植。Hilbert 曲線でまとめた R-tree で、矩形検索と近傍検索（flatqueue 3.1.0 の移植）ができる。
  - 計測：`area`、`length`、`distance`、`centroid`、`bbox`。Turf.js 7.4.0 と同じ式で、同じ順に計算する。
  - `contains_point`：point-in-polygon-hao 1.2.4 と同じ判定。境界上は内側として扱う。
    - robust-predicates の `orient2d` は、第3点が原点なので、適応計算の補正項（tail）が必ず 0 になる。そのため、正確な積の展開だけを移植した。
  - `points_within`、`collect`（ポリゴンごとの件数・数値の件数・合計を、点の順に足す）、`grid_count`（上限 `MAX_GRID_CELLS`）。
  - 三角関数は `Trig` で差し替えられる。wasm-gc ではホストの `Math` を使い、Turf とビット単位で一致させる。
- **`analysis_worker`**（wasm-gc）：
  - データセットをハンドルで持ち、索引は最初の検索のときに作る。
  - 結果は線形メモリに f64 / i32 で書く。
  - メッセージの形は docs/FORMATS.md に書いた。
- **`mbmap/analysis`**（`npm/src/analysis.ts`）：
  - `load(GeoJSON | バイト列 | URL)` が `Dataset` を返す。`areas`、`lengths`、`centroids`、`bboxes`、`search`、`nearest`、`pointsWithin`、`collect`、`grid`、`dispose` がある。
  - ほかに `distance`（同期）と `terminate`。
  - Worker は、初めての `load` のときに起動する。表示用の入口は解析のファイルを参照しない（size.mjs と pack test で確かめている）。
- **example**：`examples/analysis`。点をブロックごとに数え、その件数でブロックを塗り分けて地図に出す。pack test で、遅延ロード、結果、エラーの経路を確かめている。
- **GeoJSON の読み込み**：
  - `read_geojson` に `slow_number` を渡せるようにした。これは、Clinger の高速な方法では扱えない数（16桁以上など）を読む関数。
  - wasm-gc の Worker（GeoJSON 用と解析用）は、線形メモリにある数の文字列を、ホストの `Number()` で読む。どちらも正しく丸めるので、結果は変わらない（geojson の黄金テストは差 0 のまま）。
  - こうすると core の strconv がモジュールに入らないので、サイズが約半分になった。
- **サイズ（gzip）**
  - GeoJSON Worker：46.5KB → 22.3KB（予算を 50KB から 30KB に締めた。`wasmio` への整理の後の値）
  - 解析 Worker：22.3KB（予算 30KB）
  - `mbmap/analysis`：1.4KB（予算 5KB）
  - 表示用の main バンドルは 27.3KB のまま変わらない。
- **依存の追加**（bench の devDependencies のみ。§8.1 の確認をした）：
  - flatbush 4.6.2。4.7.0 は公開から1日しか経っていなかったので避けた。
  - @turf/{area, length, distance, bbox, centroid, boolean-point-in-polygon, points-within-polygon, collect} 7.4.0。
  - どれも GitHub の advisory は 0 件、install script はなし（esbuild だけ）、`npm audit` は 0 件。移植したコードのライセンスは NOTICE に足した。

### 黄金テスト（`npm --prefix bench run analysis:golden`）

配布する wasm を直接呼び、Turf.js と flatbush の結果と比べた。**2,783,078 個の値がすべてビット単位で一致した。**

- 計測：buildings・mixed・world・roads・points の全地物の面積・長さ・重心・bbox。
- 索引：各データ 200 個の矩形検索と、400 個の近傍検索（k=10 と 1）。結果の順まで一致した。
- 空間クエリと集計：点の内外判定（建物の 42,515 ポリゴン、世界の 1,000 ポリゴン）、collect、グリッド集計。

### ベンチ結果（`bench/results/analysis-*.json`、JS ms / mbmap ms（JS 比）、5回の中央値）

条件：

- データは東京駅周辺の建物 88,375 地物（32.9MB）、そのうちポリゴンが 42,515、点が 8,018。
- JS は Turf.js と flatbush を、`JSON.parse` 済みのオブジェクトに対して実行した。
- mbmap は、読み込み済みのデータセットに対して export を直接呼んだ。Worker とのメッセージ、結果のコピーは含む。

| 処理 | Node 22 | Chromium 156 | Firefox 157 | WebKit 27.2 |
|---|---|---|---|---|
| 読み込み（`JSON.parse` / mbmap） | 161.0 / 332.0（0.48×） | 82.8 / 267.0（0.31×） | 137.1 / 479.7（0.29×） | 47.0 / 318.7（0.15×） |
| 面積 | 8.5 / 2.4（3.55×） | 9.0 / 3.1（2.87×） | 7.4 / 3.4（2.20×） | 5.6 / 3.0（1.89×） |
| 長さ | 57.7 / 21.7（2.66×） | 68.7 / 30.7（2.23×） | 78.6 / 28.1（2.80×） | 60.9 / 32.3（1.89×） |
| 重心 | 12.9 / 2.4（5.34×） | 10.3 / 2.2（4.60×） | 12.1 / 2.3（5.34×） | 7.0 / 2.3（3.10×） |
| bbox | 14.8 / 4.6（3.22×） | 12.0 / 3.7（3.24×） | 14.2 / 4.0（3.51×） | 10.7 / 4.6（2.33×） |
| bbox＋索引＋1000回の検索 | 24.5 / 11.7（2.08×） | 21.0 / 10.3（2.05×） | 25.7 / 12.1（2.12×） | 18.2 / 10.4（1.75×） |
| 1000回の矩形検索 | 1.7 / 2.0（0.85×） | 1.5 / 1.6（0.93×） | 2.1 / 2.1（1.03×） | 1.8 / 1.6（1.18×） |
| 1000回の近傍検索（k=10） | 3.0 / 3.3（0.91×） | 3.2 / 3.0（1.05×） | 4.1 / 3.6（1.15×） | 3.7 / 3.1（1.19×） |
| 点の内外判定 | 2.0 / 1.6（1.27×） | 1.8 / 1.4（1.28×） | 2.4 / 1.9（1.24×） | 3.3 / 1.5（2.20×） |
| collect | 18.4 / 11.1（1.65×） | 19.3 / 9.3（2.08×） | 26.9 / 12.0（2.24×） | 17.6 / 10.3（1.72×） |
| グリッド 256×256 | 0.2 / 0.4（0.51×） | 0.3 / 0.4（0.79×） | 0.2 / 0.5（0.32×） | 0.3 / 0.3（0.87×） |

- 計測、索引の作成、集計は、どのエンジンでも 1.7〜5.3 倍速い。
- 1回ずつの検索やグリッド集計は同じくらいか、少し遅い。1回あたりの境界越えと結果のコピーが主なコストで、計算の量は小さい。実際の API では、さらに Worker とのメッセージが1往復加わる。
- 読み込みは `JSON.parse` より遅い（Phase 7.3 と同じ傾向）。

### 速度の改善と、その計測

- 優先度付きキュー（近傍検索）を `Array` から `FixedArray` にした。近傍検索は Node で 4.09ms → 3.37ms になった。
- `Index::of_table` で、地物ごとの bbox をタプルにせず、その場で計算するようにした。索引の作成の時間は変わらなかったが、割り当てが減るので残した。
- ホストの数値パーサ（`numberAt`）：
  - 線形メモリのビューを使い回し、メモリが増えたときだけ作り直すようにした。
  - 文字列は `String.fromCharCode.apply` でまとめて作るようにした。
  - 建物の読み込みは Node で 401ms → 332ms になった。
- ベンチの比べ方を直した。最初の計測では、JS の索引の行に bbox の計算が入っていなかった。GeoJSON から使うなら JS も bbox が要るので、「bbox＋索引＋検索」に揃えた。

### 長い数の読み込み方（ホストの `Number()` にすると決めた）

16桁以上の数（full precision の座標など）の読み方を、core の strconv（今まで）からホストの `Number()` に替えた。GeoJSON ベンチ（`geojson-*.json`、建物 32.9MB と道路 30.1MB、read+index、ms）の前後：

| | Chromium | Firefox | WebKit |
|---|---|---|---|
| 道路（full precision） | 319 → 333 | 540 → 451〜608（読み込みだけなら 323 → 380） | 476 → 372 |
| 建物（full precision） | 460 → 447 | 620 → 700〜713（読み込みだけなら 374 → 465） | 815 → 416 |
| 道路（小数 6 桁。遅い経路を通らない） | 280 → 287 | 299 → 295〜436（ばらつき） | 352 → 262 |

- 良い点：Worker の wasm が gzip で約 24KB ずつ小さくなる（GeoJSON 用と解析用の両方）。WebKit では読み込みが最大 2 倍速い。
- 悪い点：Firefox では、full precision のデータの読み込みが 17〜24% 遅くなる。wasm から JS を呼ぶコストのため。
- **決定（2026-11-01、ユーザー確認）：`Number()` を使う**。実際の GeoJSON は小数 6〜7 桁のものが多く、その場合は差が出ない。サイズの効果が大きく、WebKit では速くなる。
- 戻す場合は、`slow_number` を渡さなければ strconv に戻る（`read_geojson` の既定）。

### リファクタリング点検（同じ PR に追加）

- **バグ**：ホストの数値パーサが、線形メモリのビューをモジュール全体で1つ持っていた。同じ JS の中で2つの wasm を動かすと（ベンチがそうしている）、別のインスタンスのメモリを読んでしまう。インスタンスごとに作る `hostNumber`（`wasmio/js/host.mjs`）にして、3か所のコピーを1つにした。
- **重複**：`geojson_worker` と `analysis_worker` の線形メモリの入出力を、wasm-gc 専用のパッケージ `wasmio` にまとめた（wasm-gc 同士なら import できる。テストあり）。`#export_name` は import 先からは出ないので、各エントリには薄い関数だけ残した。全ターゲット向けの `worker` は、今まで通り自分で持つ。サイズは変わらない（±0.1KB）。
- **速度（§7.5）**：`Index::of_table` の bbox の書き出しは、計測で効果がなかったので `bbox()` を使う形に戻した。
- **定数**：計測の種類の番号は MoonBit・TS・ベンチの3か所にあるので、ミラーのコメントを付けた。
- **API**：内部用なのに公開していた `Dataset.idFor` を、private な static メソッドにした。
- **セキュリティ（§8.3）**：Worker 側でも、`load` の URL が http(s) かを確かめるようにした（解析と GeoJSON の両方）。
- **コメントとテスト**：4行を超えていたコメントを3行以内にした。`Index::of_table` を直接確かめるテストを足した。

### 既知の問題・次にやること

- 3ブラウザのベンチの最初の実行で、Chromium が一度 `Failed to fetch` で失敗した。再実行では通った。
- `nearest` の距離は、経緯度の箱の距離（度）。地表の距離での近傍検索（Turf の `nearestPoint` 相当）は、まだない。
- 未対応：ポリゴン同士の交差判定（bbox で絞るまで）、結果を地図のソースに直接渡すこと（VISION §6 の `type: "table"`）。
- 次は VISION §8 の Phase 9（symbol、日本語ラベル）。

## リファクタリングとセキュリティチェック（Phase 7 の後、2026-10-31）

状態：**完了**。プロジェクト全体を AGENTS.md §7 と §8 の順に見直した。重点はコメントの量。

### やったこと

- **コメント**：4行以上のコメントブロックが 57 個あった。ライセンス表記と、中身が3行の JSDoc を除いて、すべて3行以内にした。
  - バイナリの形式と Worker のメッセージは、新しい [docs/FORMATS.md](docs/FORMATS.md) にまとめた。コードには節の名前だけを書く。
  - コードの言い換えだけのコメントは消した（`element/parse.ts` の関数ごとの説明など）。
  - 実装とずれていた説明を直した。`StyleSpecification` の「1つのベクトルソース」、`npm/scripts/build.mjs` の出力の一覧、VISION §4-2 の「8192 に換算」（実装は `TILE_EXTENT` 4096）。
- **重複**：
  - 属性値のバイナリ形式は、4か所で書き方も読み方も別々だった（`geom` の表、`tiler` の列指向タイル、`worker` のグループ属性、`ColumnTile`）。これを `core` の `ByteWriter` / `ByteReader`（エラーは読み手に残る方式）と、共通のタグ `PROP_*` にまとめた。
  - `tiler` の `VALUE_*` と `worker` の `PROPS_*` はなくした。
  - `geom` に `write_prop` / `read_prop` を置いた。
- **定数**：
  - `tiler` の既定の extent は `@core.TILE_EXTENT` を使う。
  - `geojson_worker` のピクセルからタイル単位への換算は `TILE_EXTENT / TILE_SIZE` から求める。
- **ファイルの分割**：
  - `formats/geojson.mbt`（803行）を、JSON の字句解析（`json.mbt`）と GeoJSON の構造に分けた。
  - `worker/processor.mbt` から `Groups` を `groups.mbt` に移した。
- **テスト**：次のテストを足した。
  - `encode_tile` のレイアウトと、タイルにないキーを省くこと。
  - `write_prop` / `read_prop`。
  - `ByteWriter` / `ByteReader`。
  - 列指向タイルの、すべての長さでの切り詰め。
- **試してやめたこと**：線形メモリの load/store を、wasm-gc 専用のパッケージ（`wasmio`）にまとめようとした。しかし、全ターゲット向けのパッケージ（`worker`）は、wasm-gc だけのパッケージを import できなかった（moon がビルド計画を作れない）。他のターゲット向けにスタブを書く方が、重複している約40行より重いので、やめた。AGENTS.md の規則は「wasm-gc 向けのエントリのパッケージ（`worker`、`geojson_worker`、ベンチ）の中に置く」に改めた。

### セキュリティチェック（§8）

- `npm audit` の結果は、`bench/`、`npm/`、`examples/react/` のどれも 0 件。依存は追加していない。
- **直した点（中）**：GeoJSON の属性キーの種類に上限がなかった。キーごとに表と同じ長さの列ができるので、キーが地物ごとに違う入力ではメモリが膨らむ。そこで `MAX_GEOJSON_KEYS`（4096）を超える入力はエラーにした（テストあり）。
- **直した点（低）**：`ByteReader` の範囲チェック `at + n > length` は、n が 2^31 に近いと Int32 で桁あふれして通ってしまう。その後のスライスで panic し、Worker が止まる。メモリ安全性の問題ではないが、`n > length - at` に直し、テストを足した。pbf の読み手と線形メモリの確認は、もともと桁あふれしない書き方だった。
- **ドキュメント**：CSP を使うページでは `'wasm-unsafe-eval'` が要ることを、npm/README.md に書いた。
- `innerHTML`、`eval`、`new Function`、認証情報付きの fetch は使っていない。開発用サーバーは 127.0.0.1 にだけ bind する。
- リポジトリの Dependabot alerts は無効になっている（GitHub の設定）。有効にするかどうかは、リポジトリの所有者が決める。

### ベンチ結果（`npm --prefix bench run worker:browser`、`bench/results/worker-*.json`、ms）

グループ属性の書き出しを `ByteWriter` に替えたので計測した。差はどのブラウザでも計測のばらつきの範囲で、速度は落ちていない。

| ブラウザ | 中央タイル（前 → 後） | タイルの中央値（前 → 後） | 合計（前 → 後） |
|---|---|---|---|
| Chromium 156 | 2.59 → 2.58 | 6.48 → 6.48 | 218.5 → 217.2 |
| Firefox 157 | 3.30 → 3.30 | 8.48 → 8.44 | 283.7 → 280.6 |
| WebKit 27.2 | 2.82 → 2.84 | 7.38 → 7.08 | 239.5 → 232.6 |

サイズ（gzip）は次のとおり。どちらも予算内。

- 表示用 Worker：75.9KB → 76.1KB
- GeoJSON Worker：46.1KB → 46.5KB

黄金テストはすべて変わらない。

- mvt：35/35
- tess：35/35
- geojson：5377 タイル、差 0

## Phase 7.4：GeoJSON ソースの組み込み（2026-10-31）

状態：**完了**（Phase 7 を終えた）。スタイルに GeoJSON ソースを書くだけで描ける。example では、MapLibre と同じスタイルで見た目がほぼ一致した（平面とピッチ 50°）。

### できたこと

- **`style`**：GeoJSON ソース（`data` は必須。`maxzoom` 既定 18、`buffer` 既定 128、`tolerance` 既定 0.375 は MapLibre と同じ。`cluster` は Unsupported）。`VectorSource` を `Source`（`kind` が Vector / GeoJSON）に一般化した。
- **`geojson_worker`**（wasm-gc。gzip 46.1KB、JS グルー込み）：
  - ソースごとに `formats` で読み込み、`tiler` で索引を作る。タイルは `@tiler.encode_tile`（列指向のバイナリ）で返す。
  - 投影の sin と log は、ホストの `Math` を使う（geojson-vt とビット単位で一致）。入力は 256MB まで（§8.2）。
- **列指向のタイルの受け渡し**（ユーザー判断どおり、MVT を挟まない）：
  - 表示用 Worker は、`ColumnTile` として読む。すべての数と長さを入力の範囲と照らし合わせ、不正な入力は「malformed GeoJSON tile」として拒否する。
  - MVT のレイヤーと同じ `Features` 列挙型の裏に入れたので、filter、属性でのグループ分け、三角形分割は共通のコードを使う。
- **`map`**：
  - 複数のソースに対応した（ソースごとに `SourceTiles`。ズームの範囲もソースごと）。
  - GeoJSON ソースのタイルは、ファサードの provider（ソース id、z, x, y → `Promise<ArrayBuffer | null>`）から受け取り、表示用 Worker に `bytes` として渡す。
- **ファサード**：
  - スタイルに GeoJSON ソースがあるときだけ、`import("./geojson.js")` で読み込む。
  - エンジンに渡すスタイルからは、GeoJSON の `data` を除く。巨大なデータを、表示用 Worker まで JSON として運ばないため。
  - `data` が URL ならスタイルの URL を基準に解決し、http(s) に限る。オブジェクトなら UTF-8 にして Worker に渡す。
  - `geojsonWorkerUrl` と `geojsonWasmUrl` のオプションを加えた。
- **描画**：すべてのタイルを、自分の範囲 `[0, 4096)` で切り取るようにした（フラグメントシェーダの `u_clip`）。地物はタイルの周りのバッファにはみ出し、隣のタイルも同じ部分を描くので、半透明の面に重なりの縞が出ていた（example で見つけた）。線は頂点の位置で、円は中心で切るので、継ぎ目は出ない。
- **example**：`examples/geojson`。国土地理院のタイルの上に、URL のソース（面・穴のある面・線・MultiLineString・点。`kind` で塗り分け）と、スタイルに直接書いたソースを重ねる。
- **pack test**：
  - GeoJSON の例で、`geojson.js`・`geojson-worker.js`・`geojson.wasm`・`places.geojson` が読み込まれること、傾けても動くことを確かめる。
  - GeoJSON のないスタイル（`examples/npm`）では、`geojson*` を一切読み込まないこと（遅延読み込み）も確かめる。

### 読み込み方の比較（7.3 で保留した判断）

GeoJSON をどこで読むかを計測で比べた（`bench/results/geojson-*.json`。「索引まで」の時間、ms）。

- A：MoonBit で、テキストから直接読む（本番の方式）。
- B：JS の `JSON.parse` と JS のループで表のバイト列を作り（`bench/geojson/columnarize.mjs`）、wasm で表と索引を作る。B が A と同じタイルを作ることは、ハッシュで確かめた。

| | points | roads（17 桁） | roads6（6 桁） | buildings |
|---|---|---|---|---|
| Node（A / B） | **18** / 31 | **439** / 509 | **346** / 505 | 593 / **510** |
| Chromium | **12** / 24 | **319** / 426 | **280** / 425 | **460** / 951 |
| Firefox | 18 / 18 | 540 / 554 | **299** / 518 | 620 / 587 |
| WebKit | 15 / 14 | 476 / **369** | 352 / 376 | 815 / **329** |

**A を続ける**：V8（Chrome、Edge、Node）では A が速く、Firefox はほぼ同じ。WebKit では、B が速いデータもある。今回の計測は、geojson-vt 自身の時間も実行によって最大 2 倍近く揺れるほど、ばらつきが大きかった。読み込みの改善（数値の解釈、確保の削減）は、引き続きの課題。

### ベンチ結果（Chromium 156 + Metal / M2、`bench/maplibre/style.json`、11回の中央値。GeoJSON は使っていない）

| | mbmap | MapLibre 6.16.0 |
|---|---|---|
| メイン（`mbmap` の入口、gzip） | 27.3KB（7.3 では 26.3KB） | 295.5KB |
| GeoJSON モジュール / GeoJSON Worker（GeoJSON があるときだけ） | 0.8KB / 46.1KB | — |
| 表示用 Worker | 75.9KB（7.3 では 73.8KB。列指向のタイルの読み込みで +2.1KB） | 148.0KB |
| 初回描画 | 98.8ms | 99.2ms |
| 1フレームの rAF の CPU 時間（p50 / p95） | 0.37〜0.46 / 0.75〜0.79ms | 0.78〜0.91 / 1.30〜1.57ms |

- タイルごとの切り取りで、フラグメントシェーダの分岐が全タイルに入った。それでも 1フレームの CPU 時間は 7.2（p95 0.65〜0.76ms）と同程度だった。

### 既知の問題・次にやること

- GeoJSON の読み込みは、V8 以外では geojson-vt（JS）より遅いことがある（7.3 の表）。
- 未対応：`setData`（データの差し替え）、クラスタリング、`promoteId`、`generateId`。データはソースごとに一度読み込むだけ。
- 線形メモリの補助関数のコピーが、`worker`・`geojson_worker`・bench の3か所にある。本番での2つ目の使い手（`geojson_worker`）ができたので、次のリファクタリングで共通化を検討する。
- 次は VISION §8 の Phase 8（`mbmap/analysis` 第1弾：空間インデックス、計測、空間クエリ、集計）。

## Phase 7.3：列指向の表、GeoJSON の読み込み、geojson-vt の移植（2026-10-31）

状態：**完了**（黄金テストは全タイル一致。速度は、Chromium・Node では全体で geojson-vt より速く、WebKit では遅い。下記）。

### ユーザー判断（2026-10-31）

- GeoJSON のタイルは、**列指向のまま**表示用 Worker に渡す（MVT への書き出しと読み込みを挟まない）。表示用 Worker の予算（80KB）は絶対の上限にはせず、超えそうなときは計測を添えて見直す。
- GeoJSON ソースは**スタイルに書くだけ**で使えるようにする（`mbmap/geojson` を動的 import で読み込む）。
- 7.3（純 MoonBit の部分と、黄金テスト・速度比較）と 7.4（組み込み）に PR を分ける。

### できたこと

- **表示用 Worker の削減**（7.4 の準備）：78.8 → **73.8KB**（gzip、グルー込み）。
  - グループの属性を、JSON ではなく小さなバイナリ形式で渡すようにした（`PROPS_*`）。`Json::stringify` が、浮動小数点の文字列化（Ryu）とエスケープの判定を Worker に引き込んでいた（−4.5KB）。JS 側は、プロトタイプのないオブジェクトに戻す（`__proto__` キーでも汚染されない）。
  - 同じジオメトリかどうかの判定（バッファ共有）を、`Expr` の構造比較から、スタイルを読むときに振る `filter_id`（同じ書き方の filter は同じ番号）の比較にした（−0.5KB）。
  - 試していないこと：三角関数をホストの `Math` から借りる案（下記の `Trig`）は、表示用 Worker にも効くはずだが、moonrun のテストでは使えない。今は見送った。
- **`geom`**：列指向の地物の表（`Table`）。
  - ジオメトリは、地物 → パーツ → リング → 点の入れ子のオフセットと、x, y を交互に並べた座標。GeoArrow の multipolygon と同じ形で、点と線も同じ形に揃えた。
  - 属性は、キーごとの列（`Column`。値がない地物は None、明示的な null は `Some(Null)`）。
  - `TableBuilder` で組み立てる。列は値が入るときだけ伸ばし、`finish` で揃える（地物ごとに全列を触らない）。
- **`formats`**：GeoJSON の読み込み（`read_geojson`）。
  - JSON の木を作らず、UTF-8 のバイト列から直接、表に書き込む。
  - FeatureCollection、Feature、単独のジオメトリ、GeometryCollection（メンバーごとに1行にする。geojson-vt と同じ）に対応する。
  - メンバーの順序は問わない（`type` が `coordinates` の後に来てもよい）。
  - エラーは状態に記録して最後に1回だけ raise する。ネストは 64 段まで（§8.2）。型と座標の深さが合わない地物は、ジオメトリなしとして残す。
  - 数値は、有効桁 15 桁以下かつ指数 ±22 以内なら、正確な乗除算で求める（Clinger の高速経路。JS の `JSON.parse` と同じ結果）。それ以外は core の `strconv` に任せる。
  - 入れ子の属性値（オブジェクトと配列）は、空白を除いた JSON 文字列にする。
- **`tiler`**：@maplibre/geojson-vt 6.3.0 の移植（変換、Douglas-Peucker による単純化、クリップ、日付変更線をまたぐ複製、タイル索引と、要求時の細分化）。処理の順序も元のとおりにした。ライセンスは MIT と ISC で、NOTICE に記載した。
  - クリップで作った地物は、クリップごとの `Store` に書き、そのまま残す地物は参照（`FRef`）で共有する。最初は追記だけの共有ストアにしたが、細分化するたびに増え続けてメモリが尽きたので、この形にした。
  - JS の `Math.round` と同じ丸め（0.5 は +∞ 方向）にした。
  - 投影の sin と log は差し替えられる（`Trig`）。wasm-gc ではホストの `Math.sin` / `Math.log` を渡すと、geojson-vt とビット単位で一致する。純 MoonBit の `@math` では最下位ビットが違うことがあり、4,336 タイル中 314 タイルで、丸めた座標や単純化の判定がずれた。moonrun はホストの `Math` を渡せないので、テストは既定値（`@math`）を使う。

### 黄金テスト（`npm --prefix bench run geojson:golden`）

国土地理院の bench タイルから作った GeoJSON（点、道路・鉄道・河川、建物、混在）と、乱数で作った世界中のデータを使う。3つの設定で、データの範囲の全タイルを比べた。設定は、geojson-vt の既定値、MapLibre の GeoJSON ソースと同じ値（maxzoom 18、buffer 1024、tolerance 3。4096 単位）、ラップなしの3つ。

**4,336 タイル、813 万地物が完全に一致した**（地物の順・型・元の行・整数座標）。js ビルドはそのまま比べ、wasm-gc ビルドはタイルごとのハッシュで比べた。

### ベンチ結果：GeoJSON → タイル（`bench/results/geojson-*.json`、MapLibre の設定、z6〜16 のデータ上の全タイル、5回の中央値）

比は「geojson-vt の時間 ÷ mbmap の時間」（1 より大きければ mbmap が速い）。「索引まで」は、最初のタイルを切り出せるようになるまで（JS はデコード＋`JSON.parse`＋索引、mbmap はコピー＋読み込み＋索引）。

| 実行環境 | 全体 | 索引まで | タイルの切り出し |
|---|---|---|---|
| Node 22（V8） | **1.74〜2.47** | 0.49〜0.78 | **3.2〜4.2** |
| Chromium 156 | **1.34〜1.59** | 0.42〜0.65 | **2.3〜2.6** |
| Firefox 157 | 0.79〜1.65 | 0.43〜0.68 | 0.9〜3.2 |
| WebKit 27.2 | 0.38〜0.69 | 0.14〜0.58 | 0.5〜1.3 |

データの大きさ：points 1.5MB（8,018 地物）、roads 30.1MB（105,617 地物）、roads6 25.8MB（roads を小数 6 桁に丸めたもの）、buildings 32.9MB（3×3 タイルの建物）。

- **タイルの切り出しは、V8 では geojson-vt の 2.3〜4.2 倍速い**。全体でも、Node と Chromium では速い。
- **読み込みは、どの環境でも `JSON.parse` より遅い**（Chromium で 2.9〜3.5 倍、WebKit で最大 9 倍）。そのため、最初のタイルが出るまでの時間は geojson-vt より長い。
  - プロファイル（Node、roads）では、数値の解釈が 28%（座標が 17 桁あり、高速経路を外れて `strconv` に回る）、GC が 13% だった。
  - 現実の GeoJSON に多い小数 6〜7 桁では、差は縮まる（roads6 では読み込みが `JSON.parse` の 1.8 倍、索引までで 1.3 倍）。
- **WebKit では全体として geojson-vt より遅い**。Firefox の buildings では、タイルの切り出しも遅かった（904ms。GC が支配的とみられる）。
- 改善の記録：
  - 座標の解析を、要素ごとのクロージャから素のループにした。
  - 読み飛ばしを、括弧の対応だけを見る走査にした。中身のカンマやコロンは検査しないが、括弧の数とネストの上限は守る。
  - キー文字列を、バイト列でキャッシュした（直前のキーの次を先に見る）。
  - 列を、値が入るときだけ伸ばすようにした。
  - 座標を、一時バッファから素のループでコピーするようにした。
  - 以上で、読み込みは roads で 432 → 約 320ms になった。

### 既知の問題・次にやること

- **読み込みの速さ**。候補は次のとおり。
  - 17 桁以上の数値を速く正確に解釈する（Eisel-Lemire。表が大きいのでサイズと比べて決める）。
  - 地物ごとの確保を減らす（`FRef`、属性値、一時バッファ）。
  - または、JS の `JSON.parse` で解析してから列指向に詰め替える方式を、7.4 で計測して比べる。
- **WebKit（JavaScriptCore）での遅さ**。wasm-gc の確保が多いコードが不利とみられる。確保を減らす改善が、どの程度効くかを測る。
- 未対応：geojson-vt のクラスタリング、データの更新（`updateable`）、line metrics、`promoteId` / `generateId`。
- 7.4：GeoJSON 用の入口（専用の Worker と wasm）、列指向のタイルを表示用 Worker で受け取る経路、複数ソースへの対応、スタイルに書くだけでの読み込み、example、MapLibre との比較。

## Phase 7.2：circle レイヤー（2026-10-31）

状態：**7.2 完了**（`bench/maplibre/style.json` に circle レイヤーを2つ加え、平面とピッチ 55° の両方で、MapLibre と位置・色・大きさが一致することをスクリーンショットで確かめた）。

### できたこと

- **`style`**：`circle` レイヤー。paint は `circle-color`、`circle-opacity`、`circle-radius`（既定 5）、`circle-stroke-width`（既定 0）、`circle-stroke-color`、`circle-stroke-opacity`。どれも式で書ける（ズームや属性値に応じて変えられる）。
- **`tess`**：`add_points`。タイル内（`[0, extent)`）の点ごとに四角形を1つ作る（MapLibre と同じく、タイル外の点は捨てる）。頂点の並びは線と同じにしたので、詰め込みとアップロードは線の経路を使い回す。
- **`worker`**：`KIND_CIRCLE`。属性値によるグループ分けと、同じジオメトリのレイヤーでのバッファ共有は、ほかの種類と同じく効く（半径だけが違う2つのレイヤーは、1つのバッファを共有する）。
- **`render_webgl2`**：circle のシェーダ。投影した中心の周りに、画面空間で半径＋ストロークだけ広げ、深さに合わせて縮める（MapLibre の既定 `circle-pitch-alignment: viewport` と `circle-pitch-scale: map`）。塗りとストロークの境と外周は、1ピクセルでアンチエイリアスする。
- **`map`**：メッシュは種類（`KIND_*`）を持ち、circle の半径とストロークを評価して描く。
- **スタイル**：`bench/maplibre/style.json` と `examples/basic/style.json` に、`elevation`（標高点。定数の paint）と `symbol`（地図記号の点。`ftCode` による `match` で色分け、ズームで半径を補間、白いストローク）を加えた。

### ベンチ結果（Chromium 156 + Metal / M2、11回の中央値。スタイルに circle を加えたので、Phase 7.1 とは負荷が違う）

| | mbmap | MapLibre 6.16.0 |
|---|---|---|
| メイン（`mbmap` の入口、gzip） | 25.9KB | 295.5KB |
| Worker（gzip） | **78.8KB**（予算 80KB） | 148.0KB |
| 初回描画 | 97.9ms | 99.1ms |
| 1フレームの rAF の CPU 時間（p50 / p95） | 0.34〜0.44 / 0.65〜0.76ms | 0.80〜0.95 / 1.40〜1.54ms |
| `process_tile`（温まった状態、タイル中央値） | 6.48ms | — |

- **初回描画は、実行によって 98ms 前後と 113ms 前後に分かれる**。差はちょうど1フレームで、最後のタイルが vsync の直前に間に合うかどうかで決まる。同じコードで続けて測ると、circle なしで 11回中1回、circle ありで 11回中4回が遅いほうになった。別の実行では、circle ありで 11回中 6〜7回が遅かった。レイヤーが増えると、間に合わない回が増える。根本的な原因は、Phase 3 から残っている「作成から idle までが遅い」（Worker の最初のタイルが最適化前のコードで動く）こと。
- 1フレームの CPU 時間は、7.1（p95 0.46〜0.59ms）より増えた。circle レイヤーが2つ増え、タイルごと・グループごとの描画呼び出しが増えたため。MapLibre の約半分で、代理指標の目標（p95 1.44ms 以下）は満たしている。
- 試してやめたこと：ANGLE（Metal）がシェーダのパイプラインを最初の描画で作るのが原因と考え、初期化時に3つのプログラムで空の三角形を描いて準備させた。すると、11回中 10回が遅いほうになったので元に戻した。

### 既知の問題・次にやること

- **Worker の予算の残りは 1.2KB**（78.8KB / 80KB）。7.3 で GeoJSON を足す前に、wasm の中で何が大きいかを調べ、削る必要がある。GeoJSON のタイル分割は、表示用 Worker に入れるか、別の入口にするかも、ここで決める（VISION §3 の方針では、入口を分けられる）。
- 初回描画が1フレームずれる問題（上記）。
- 未対応：`circle-blur`、`circle-translate`、`circle-pitch-alignment: map`（地面に寝かせる）、`circle-pitch-scale: viewport`。
- 次は 7.3（列指向データと GeoJSON ソース）。

## Phase 7.1：3D を見越したカメラ（回転・ピッチ）（2026-10-31）

Phase 7 は大きいので、3つの PR に分ける：7.1 カメラ（この PR）、7.2 circle レイヤー、7.3 列指向データと GeoJSON ソース。

状態：**7.1 完了**（回転・ピッチできる example。`examples/basic/?bearing=30&pitch=50`、右ドラッグや2本指で操作できる）。

### できたこと

- **`core`**：
  - `Camera` に `bearing`（北から時計回りの度。-180〜180 に折り返す）と `pitch`（0〜`MAX_PITCH` = 60 度）を加えた。60 度までなら、地平線が画面に入らない（ピッチ＋視野角の半分が 90 度未満）ので、画面のどの点も地面に対応する。
  - `Mat4`（列優先。gl-matrix と同じ定義）と、MapLibre と同じ組み立てのビュー射影：透視投影（視野角 約 36.87°）、y 反転、カメラ距離だけ引く、ピッチ、方位。座標は中心からの相対で、ワールドピクセル単位の倍精度で扱うので、どのズームでも精度が落ちない。
  - `screen_to_mercator` は、画面の点を通る視線と地面の交点として求める。`panned` はつかんだ点がポインタに付いてくるように、`keeping` はズーム・方位・ピッチを変えても指定した画面の点がずれないように、中心を決める。
  - `covering_tiles(min_z, max_z)`：視界の地面上の範囲（凸四角形）について、四分木をたどって選ぶ。カメラからの距離が `LOD_DISTANCE`（1.5）× カメラ距離を超えると、距離が2倍になるごとにズームを1つ下げる。ピッチを付けた遠景は、低いズームのタイルで描かれる。選ばれたタイルは重ならない。
  - テスト：4種類のカメラ（平面、回転、ピッチ、両方）で、往復の一致、パンとズームで点が動かないこと、タイルが画面をちょうど1回ずつ覆うこと、`tile_matrix` と画面座標の一致、方位 90 度で東が上になること、などを全ターゲットで確かめる。
- **`render_webgl2`**：
  - シェーダは、タイルごとの `mat4` を受け取る。
  - 線はタイル単位で押し出すので、ピッチを付けると遠くほど細くなる（MapLibre と同じ）。アンチエイリアスの幅も、深さに合わせて縮める（MapLibre の gamma scale に相当）。
  - 読み込み中のタイルの代わりに描く親タイルは、フラグメントシェーダで切り取る（タイル単位の矩形 `u_clip`）。回転すると、scissor の矩形では切り取れないため。
- **`map`**：右ドラッグか Ctrl＋ドラッグで回転（横）と傾き（縦）。2本指では、ピンチズームに加えて、ひねると回転する。どちらも、ポインタの下の点を基準にする。
- **API**：
  - JS エクスポートにカメラの bearing と pitch を加えた。`map_on_move` は通知だけにし、カメラは `map_camera` で読む。
  - ファサード：`bearing` / `pitch` オプション、`getBearing`、`getPitch`、`setBearing`、`setPitch`、`jumpTo({ bearing, pitch })`。
  - `<mb-map>`：`bearing` と `pitch` の属性・プロパティ。pitch は 0〜60 を厳密に検査し、範囲外は `mb-error` にする。
- **見た目の確認**：方位 30°、方位 -20°・ピッチ 55°、ピッチ 60° の3つのカメラで、MapLibre とスクリーンショットを並べ、道路・河川の位置と遠近がほぼ一致することを確かめた。最初は、遠景の細い線が MapLibre よりざらついていたので、アンチエイリアスを深さで縮めて直した。
- **pack test**：ファサードで bearing が折り返し、pitch が 60 に収まること、要素の属性で回転・傾くこと（61 は拒否）、右ドラッグで方位が -80 度・ピッチが +20 度（60 で頭打ち）変わることを確かめる。

### ベンチ結果（Chromium 156 + Metal / M2、1280×800、DPR 2、`bench/maplibre/style.json`、11回の中央値、カメラは平面）

| | mbmap | MapLibre 6.16.0 |
|---|---|---|
| メインの JS（`mbmap` の入口、gzip） | 25.3KB（7.1 の前は 22.7KB） | 295.5KB |
| 初回描画 | 97.0ms | 99.6ms |
| 1フレームの rAF の CPU 時間（p50 / p95） | 0.25〜0.34 / 0.46〜0.59ms | 0.82〜0.91 / 1.32〜1.49ms |

- 最初の実装では、パンの p95 が 0.52 → 0.95ms に悪化した。次の3つで 0.59ms まで戻した。
  - サイズが同じなら `resize` でビュー射影と逆行列を作り直さない（毎フレーム呼ばれていた）。
  - `tile_matrix` で行列の積を2回作らず、列ごとに直接計算する。
  - uniform の行列は、使い回しの `Float32Array` で渡す（JS の配列だと、毎回変換される）。
- サイズは、ポインタの管理を `HashMap` とソートから挿入順の配列にし、`overlaps` からクロージャをなくして 1.0KB 減らした。それでも、行列の逆行列と四分木で 2.6KB 増えた。
- 11回の初回描画のうち、何回かが1フレーム（約 17ms）遅れることがある。直前の回は 5/11 が 114ms 前後だったが、やり直すと 10/11 が 97ms 前後だった。計測環境のばらつきと見ている。

### 既知の問題・次にやること

- ピッチの上限は 60 度。60 度を超えると地平線が見えるので、空の描画と、地平線より上の扱いが要る（MapLibre は 85 度まで）。
- タッチでの傾き（2本指の上下）は、まだない。キーボード操作もない。
- 世界の複製（経度 ±180 をまたいだ表示）は、引き続き扱っていない。
- 次は 7.2 の circle レイヤー。

## Phase 6.5：入口の分割と Wasm の遅延ロードの試作（2026-10-31）

状態：**完了**（分割の粒度を、計測にもとづいてユーザーが決定した。入口ごとのサイズ予算を CI で確かめる仕組みもできた）。

### 計測したもの（`npm --prefix bench run split`、`bench/results/split.json`）

- `bench/split/analysis`：解析の代わりに置くパッケージ。列指向のポリゴンを受け取り、球面面積（Turf.js と同じ式）、bbox、グリッド集計（`Map`）、面積順の上位（ソート）を計算する。本物の解析と同じく、`Map`、ソート、`@math` を使う。
- 次の4つのモジュールを比べた。
  - 空のモジュール（ランタイムの下限）
  - 解析だけのモジュール
  - 表示用 Worker
  - 表示用 Worker に同じ解析を入れた一体型

**サイズ（gzip -9）**

| モジュール | gzip |
|---|---|
| 空の wasm-gc モジュール | **0.18KB** |
| 解析だけ | 9.37KB |
| 表示用 Worker | 77.18KB |
| 表示用 Worker ＋ 解析（一体型） | 80.49KB（**+3.31KB**） |

- wasm-gc には、アロケータのようなランタイムがないので、モジュールを1つ増やすことの固定費はほぼ 0。
- 解析だけのモジュールの 9.37KB のうち、一体型で増えるのは 3.31KB だけ。差の**約 6.1KB は、表示用 Worker と共通の core のコード**で、別モジュールにすると重複する。中身は主に三角関数（`sin` の引数還元 `rem_pio2`）と整数の文字列化、配列の内部処理（debug ビルドで関数名を比べた。テキスト量で見ると、解析モジュールの 61% が Worker と共通）。

**読み込みと実行（ms、1万ポリゴン、15回の中央値、ローカル配信なのでネットワークの時間は含まない）**

| | Chromium 156 | Firefox 157 | WebKit 27.2 |
|---|---|---|---|
| モジュール Worker の起動 | 2.2〜3.1 | 5.0〜6.1 | 2.1〜3.3 |
| 読み込み：表示用 Worker / 一体型 | 1.96 / 1.92 | 5.96 / 5.94 | 2.70 / 2.76 |
| 読み込み：解析だけ / 空 | 1.31 / 1.05 | 2.48 / 1.42 | 1.94 / 1.74 |
| 解析の初回 / 温まった後：一体型 | 11.4 / 6.3 | 12.8 / 8.9 | 11.7 / 7.1 |
| 解析の初回 / 温まった後：別モジュール | 11.4 / 6.5 | 11.1 / 8.3 | 11.7 / 7.3 |

- 一体型にしても、表示用 Worker の読み込み（コンパイルとインスタンス化）は遅くならない（どのエンジンも遅延コンパイルなので、使わない関数はコンパイルされない）。
- 別モジュールにしても、実行速度は変わらない（初回も温まった後も同じ）。
- 別モジュールの追加コストは、ローカルでは読み込み 1〜2.5ms と Worker の起動 2〜6ms。実際には、これに**最初に使うときのネットワーク往復1回**が加わる（例：遅いモバイル回線で RTT 150ms・1.6Mbps なら、9.4KB で約 200ms）。先読み（アイドル時の fetch や `modulepreload`）で隠せる。
- 一体型の代償は、**表示しか使わない人も含めて、全員が +3.3KB を読む**こと。しかも、表示用 Worker の予算の残りは 1.9KB しかない。

### 分割の粒度の選択肢

| 案 | 内容 | 長所 | 短所 |
|---|---|---|---|
| A. 一体型 | 解析を表示用 Worker の wasm に入れる | 追加の読み込みがない | 全員が払う。予算（残り 1.9KB）を超える。VISION §2 の「表示だけの人は1バイトも増えない」に反する |
| B. 入口ごとに1モジュール（推奨） | `mbmap/analysis` なら `analysis.wasm` 1つ。専用の Worker で遅延ロードする | 単純で、リクエストは1回。重複は1入口あたり約 6KB | 解析の一部しか使わない人も、入口全体を読む |
| C. 機能群ごとにモジュール | 空間インデックス、計測、ジオメトリ演算、座標系変換などを、それぞれ別の wasm にする | 使う分だけを最も細かく読める | モジュールごとに約 6KB 重複する。リクエストも増える |

**ユーザー判断（2026-10-31）：推奨どおり、B を基本にし、規則で C に切り出す**（VISION §3 に反映した）。

- 規則：ある機能群の固有のコードが、gzip で約 20KB（重複分の約3倍）を超えたら、その機能群を別モジュールに切り出す。Clipper2 の移植や座標系変換が、その候補になる見込み。
- 実行場所：解析は、表示用とは別の Worker で動かす。起動は 2〜6ms と安く、長い解析がタイルの処理を待たせない。データは列指向の ArrayBuffer として transfer する。

### できたこと

- **入口ごとのサイズ予算の仕組み**（`npm/scripts/size.mjs`）：入口の一覧（ファイル、予算、参照してよいファイル）を持ち、次を CI で確かめる。
  - 入口ごとの gzip サイズが予算内であること。
  - `dist/` の `.js` と `.wasm` が、どれかの入口に属していること（予算のない新しいモジュールは失敗する）。
  - 各入口の JS が、許されたファイルだけを import や `new URL` で参照していること（表示の入口が、ほかの入口を引き込んだら失敗する）。
  - 参照の抽出（`references.mjs`）には単体テストを付けた。失敗する2つの場合（どの入口にも属さないファイル、表示の入口から別の入口への参照）を、実際に落ちることで確かめた。
- **`bench/split`**：上の計測の一式。

### リファクタリング（同じ PR に追加）

AGENTS.md §7 の観点で、この PR のコード（`bench/split`、`npm/scripts/size.mjs`、`references.mjs`）を点検した。

- 無駄なコード：`Polygons::describe` は、テストからしか呼ばれておらず、計測したモジュールには入っていなかった（使われない関数は除去される）。そのため「文字列の組み立ても使う」という記述は、計測の裏付けがなかった。関数を削除し、記述を直した。
- セキュリティ（§8.2、線形メモリ）：`analyze` の入力サイズの検査 `(n_rings + n_polys) * 4 + n_points * 16 != 入力長` は、32bit の掛け算があふれると、一周して入力長と一致しうる。各カウントを先に入力長で抑えるようにした。このコードは Phase 8 の解析の入口の雛形になるため。あふれる入力を含め、`-1` を返す経路を wasm-gc のテストで確かめる。
- ベンチ：`split/run.mjs` が、ビルドの失敗時にエラーを出していなかった。stderr を表示するようにした。
- 見送り：線形メモリの補助関数（`load_i32`、`ensure_memory` など）は、`worker`、`bench/entry`、`bench/split` に3つのコピーがある。まとめると表示用 Worker のホットパスに手が入るので、本番の2つ目の使い手（解析用 Worker）ができる Phase 8 で、共通のパッケージに移す。
- 再計測：コードが変わったので `npm run split` をやり直し、上の表を新しい結果で置き換えた（サイズの差は +14〜35 バイト、時間は誤差の範囲）。

### 既知の問題・次にやること

- Phase 8 で、線形メモリの補助関数を共通のパッケージにまとめる（上記）。
- 次は Phase 7（3D を見越したカメラ、列指向データの基盤、GeoJSON）。解析用の Worker と、その遅延ロードの実装は、Phase 8 で `mbmap/analysis` を作るときに行う。
- 重複の大部分は三角関数と整数の文字列化なので、解析側で `@math` の `sin` / `cos` を避けられる場面（平面の計算など）では、重複が小さくなる。

## Phase 6：Web Component `<mb-map>`（2026-10-31）

状態：**完了**（完了条件「素の HTML と、主要な JS フレームワーク1つ（React）の example で動く」を満たした。どちらも `npm pack` した成果物を使い、`npm --prefix bench run npm:pack` と CI で確かめる）。

### できたこと

- **`element/element.ts`（`mbmap/element`）**：`<mb-map style-url center zoom worker-count worker-url wasm-url>`。
  - 地図は open な Shadow DOM の中に作る。
  - プロパティ：`map`、`mapStyle`（スタイルのオブジェクト）、`center`、`zoom`。
  - イベント：`mb-load`、`mb-move`、`mb-idle`、`mb-error`。`detail` は `{ map, center, zoom, error? }` で、`bubbles` と `composed` を付けた。
  - 属性は厳密に解釈する。`center` は範囲内の `lng,lat`、`zoom` は 0〜24 の10進数、`worker-count` は 0〜4。不正な値は受け付けず、`mb-error` を出して前の値を保つ（AGENTS.md §8.3）。
  - 文書から外すと地図を解放し、戻すと同じカメラで作り直す。同じタスク内での移動（外してすぐ付け直す）では作り直さない。
  - サーバーでのレンダリング（`HTMLElement` がない環境）でも、import しただけでは落ちない。
  - main の入口を `./index.js` として import するので、`Map` を二重にバンドルしない。`sideEffects` には `element.js` だけを挙げた（import で要素を登録するため）。
- **`examples/element`**：素の HTML と import map。
- **`examples/react`**：React 19.3.1。`<mb-map zoom={...} onmb-move={...} />` のように、props とイベントをそのまま書く。
  - esbuild でバンドルし、`worker.js` と `mbmap.wasm` をバンドルの隣にコピーする（`new URL(..., import.meta.url)` を書き換えないバンドラでの手順の例）。
  - `StrictMode` でも地図は1つだけ作られる。
- **`bench/npm/pack-test.mjs`**：3つの example（ファサード、素の HTML、React）を確かめるようにした。要素については次を確かめる。
  - 属性の変更で `mb-move` が1回だけ出ること、不正な属性が `mb-error` になること。
  - 移動・取り外し・付け直しのライフサイクル。
  - 帰属表示が右下の1行であること。
  - React では、ボタンで props を変えると地図が動くこと、ホイールでのズームが `onmb-move` 経由で React の表示に反映されること。

### 見つけて直した問題

- **React 19 は、要素に同じ名前のプロパティがあると、props を属性ではなくプロパティとして設定する**。そのため `zoom="14.5"` が文字列のままプロパティに入り、検証で弾かれていた。`center` と `zoom` のプロパティは、属性と同じ形の文字列も同じ規則で受け付けるようにした。
- **Shadow DOM のスタイル `div{position:absolute;inset:0}` が、ファサードの帰属表示の `div` にも当たり、半透明の白で地図全体を覆っていた**。箱のスタイルはインラインで指定し、帰属表示は位置を明示するようにした。pack test で、帰属表示が右下の1行であることを確かめる。

### ベンチ結果：配布物のサイズ（`bench/results/npm-size.json`、gzip -9）

| 入口 | サイズ | 予算 |
|---|---|---|
| `mbmap`（`index.js`） | 22.7KB | 50KB |
| `mbmap/element`（`element.js`。`mbmap` に加えて読む分） | **1.3KB** | 5KB |
| Worker（`worker.js` と `mbmap.wasm`） | 78.1KB | 80KB |

- 依存（example のみ）：`react` / `react-dom` 19.3.1（2026-10-14 リリース。依存は `scheduler` だけ。インストールスクリプトなし）。`npm audit` は 0 件。パッケージ本体の実行時の依存は、引き続きない。

### リファクタリング（同じ PR に追加）

AGENTS.md §7 の観点で、Phase 5〜6 の TS 側（ファサード、要素、スクリプト）を点検した。

- 定数：要素のズーム上限を 24 から `MAX_ZOOM` = 22 に直した。core の `Transform` は 22 でクランプするので、23 や 24 が受け付けられたうえで黙って丸められていた（§8.3「丸めずに拒否する」に反していた）。Worker 数の上限も `MAX_WORKERS` として1か所にした。どちらも、MoonBit 側の元の定義を指すコメントを付けた。
- 重複：中心座標の検証を `checkCenter` にまとめ、属性の文字列からとオブジェクトからの両方で使うようにした。
- テスト：純粋な関数（URL の解決と検査、属性の解析）を依存のないモジュール（`npm/src/urls.ts`、`element/parse.ts`）に分け、`node --test` の単体テストを加えた（Node の型除去で TS のまま動かす）。CI でも実行する。
- 却下した候補：イベントごとのカメラの読み取りを1回にする案。`getCenter` と `getZoom` は、どちらも MoonBit 側を1回ずつ呼ぶので、前後で回数が変わらない。

セキュリティ（§8）で見つけて直したもの：

- **中**：`worker-url` 属性や `workerUrl` オプションに、どんな URL でも渡せた。HTML のサニタイザがカスタム要素を通すページでは、`worker-url="data:text/javascript,..."` で任意のコードを Worker として動かせる。Worker はページと同じオリジンの http(s)、wasm は http(s) だけを受け付けるようにした（§8.3）。pack test でも、`data:` の Worker URL が拒否されることを確かめる。
- **低**：`jumpTo({ zoom: NaN })` などの有限でないカメラが MoonBit 側まで届き、経度が NaN のまま地図が壊れていた。ファサードでは TypeError にした。core の `Transform` でも、有限でないカメラは無視するようにした（全ターゲットでテスト）。

サイズ：メイン 22.4 → 22.7KB（URL とカメラの検査）、`mbmap/element` 1.2 → 1.3KB。`npm audit` は `bench/`、`npm/`、`examples/react/` のすべてで 0 件。

### 既知の問題・次にやること

- `mb-map` の属性はカメラの入力だけで、ユーザーの操作で動いたカメラを属性に書き戻さない（書き戻すと、フレームワークとの間でループしやすいため）。現在のカメラは、`mb-move` の `detail` かプロパティで読む。
- `style-url` を変えると地図を作り直す（`setStyle` はまだない）。
- Vite など、`new URL(..., import.meta.url)` を書き換えるバンドラでの動作は、まだ確かめていない。
- Phase 5 からの残り：Worker の予算の残り 1.9KB。作成から `idle` までが MapLibre より約14ms 遅い。

### 次にやること（Phase 6.5）

- 入口の分割と、Wasm の遅延ロードの試作。2つ目の wasm-gc モジュールで、サイズと読み込み時間がどれだけ増えるかを測り、分割の粒度を決める。
- 入口ごとのサイズ予算の仕組み（今の `size.mjs` を一般化する）。

## 方針の更新（2026-10-31、ユーザー判断）

Phase 6 の前に、目標を「サーバーに頼らない WebGIS の実行基盤」に広げた（VISION §1、§3、§5、§8）。

- 位置づけ：表示が入口、データ加工と解析が差別化、3D は表示モードの1つ。
- パッケージ：npm は1つ（`mbmap`）のまま、subpath exports で入口を分ける。解析などの Wasm は別モジュールにして遅延ロードする。入口ごとにサイズ予算を持ち、CI で確かめる。
- データ：内部の受け渡しは、GeoArrow 互換の列指向形式を基本にする（Phase 7 で計測して確定）。
- 進め方：Phase 6（`<mb-map>`）を予定どおり進め、その後に Phase 6.5（入口の分割と遅延ロードの試作・計測）を挟む。回転・ピッチは、3D を見越したカメラとして Phase 7 で作る。

## Phase 5：npm パッケージ（2026-10-31）

状態：**完了**（完了条件「`npm pack` した成果物で example が動く」を満たした。`npm --prefix bench run npm:pack` で確かめ、CI でも同じものを実行する）。

### できたこと

- **`npm/`（パッケージ `mbmap`）**：
  - `src/index.ts`：MapLibre に名前と形を寄せた TS ファサード。`new Map({ container, style, center, zoom, ... })`、`on` / `off` / `once`（`load`、`idle`、`move`、`error`）、`getCenter`、`getZoom`、`jumpTo`、`setCenter`、`setZoom`、`loaded`、`getCanvas`、`getContainer`、`remove`。
  - スタイルは、オブジェクトか URL で渡す。URL は認証情報なしで取得し、タイルの URL はスタイルの URL を基準に解決する。オブジェクトに描けない内容があれば例外を投げ、URL の場合は `error` イベントにする。
  - 帰属表示：ソースの `attribution` を、`textContent` で右下に出す（HTML としては解釈しない）。
  - Worker と wasm は、既定で `new URL("./worker.js", import.meta.url)` で読む。`workerUrl` と `wasmUrl` で差し替えられる。
  - `scripts/build.mjs`：`dist/` に `index.js`（ESM、minify 済み）、`index.d.ts`（tsc で生成）、`worker.js`、`mbmap.wasm` を作る。
  - `scripts/size.mjs`：gzip のサイズを VISION §2 の予算と比べ、超えたら失敗する。
  - `package.json` は `"private": true` にした。npm への公開は、まだ決めていない。
- **CI**（`.github/workflows/ci.yml`）：push と PR ごとに、次を実行する。
  - `moon check --deny-warn`、`moon test`（4ターゲット）、`moon fmt --check`、`.mbti` が最新であることの確認。
  - パッケージのビルド、サイズ予算の確認（結果は Job Summary に出る）、bench ツールのテスト、`npm pack` した成果物での example の確認。
  - MoonBit のツールチェーンは、版を固定して sha256 を確かめてから入れる。公式のインストールスクリプトはハッシュを確かめないうえ、パイプで実行する形なので使わない（AGENTS.md §8.1）。Actions もコミットの SHA で固定した。
- **`examples/npm`**：`import { Map } from "mbmap"` を import map で解決する例。`bench/npm/pack-test.mjs` は、tarball をここに展開してから Chromium で開き、次を確かめる。
  - `load` が来ること、`jumpTo` で `move` が1回だけ出ること（同じ値では出ない）。
  - 帰属表示が出ること。
  - スタイル URL の 404 が `error` イベントになること、描けないスタイルが例外になること、`remove` 後に要素が残らないこと。
- **セキュリティ**：タイル URL のテンプレートは、相対 URL か http(s) だけを受け付ける（`style` で検査。`javascript:`、`data:`、`file:`、`blob:` は `Unsupported`）。

### ベンチ結果：配布物のサイズ（`bench/results/npm-size.json`、gzip -9、1KB = 1000 バイト）

| | サイズ | 予算 |
|---|---|---|
| メイン（`dist/index.js`、ファサード込み） | **22.4KB** | 50KB |
| Worker（`worker.js` と `mbmap.wasm`） | **78.1KB** | 80KB |

- ファサードで、メインは 1.8KB 増えた（`bundle/main` だけを minify すると 20.6KB）。
- 依存パッケージ（devDependencies のみ）：`esbuild` 0.28.2（bench と同じ版）と `typescript` 7.0.2（Microsoft が公開。2026-07 リリースで、インストールスクリプトはない）。どちらも版を固定し、`npm audit` は 0 件。実行時の依存はない。

### 既知の問題・次にやること

- **Worker の予算の残りは 1.9KB しかない**。式や機能を足す前に、wasm の中で何が大きいかを調べる。
- バンドラ（Vite、webpack など）で `new URL(..., import.meta.url)` がそのまま動くかは、まだ確かめていない。動かない場合は `workerUrl` / `wasmUrl` で指定する（README に記載）。
- CI の Chromium は SwiftShader で動くので、CI では描画の見た目や速度は確かめない（性能の数値は手元の M2 で測る）。
- `setStyle`、`addSource`、`flyTo` / `easeTo`、コントロール類は、まだない。
- Phase 4 からの残り：作成から `idle` までが MapLibre より約14ms 遅い。グループ数の上限（64）。半透明の線の join。

### 次にやること（Phase 6）

- Web Component `<mb-map>`（属性で初期化、`mb-move` / `mb-load` の CustomEvent、Shadow DOM 内の canvas）
- 完了条件：素の HTML と、主要な JS フレームワーク1つ（例：React）の example で動くこと

## Phase 4：`style` サブセット（2026-10-31）

状態：**完了**（完了条件「国土地理院の簡易スタイル程度が描ける」を満たした。`bench/maplibre/style.json` を変更せずにそのまま描き、z14.5 と z16.5 のスクリーンショットが MapLibre とほぼ一致した）。

### できたこと

- **`style` の式**（`style/expr.mbt`、`style/eval.mbt`）：filter と paint を `Expr` にコンパイルして評価する。
  - 対応：`literal`、`get`、`has`、`geometry-type`、`zoom`、`!`、`all`、`any`、`==` `!=` `<` `<=` `>` `>=`、`in`、`match`、`case`、`coalesce`、`interpolate`（linear / exponential。数値と色）、`step`。
  - MapLibre と同じく、比較では型を変換しない。色のプロパティでは、文字列の定数をコンパイル時に色に変える。
  - 未対応の式は JSON 上の場所付きで `Unsupported`、形が誤っている式は `Invalid` にする。ネストは `MAX_EXPR_DEPTH`（32）までで、深い入力でスタックを使い切らない（AGENTS.md §8.2）。
  - 評価は `FeatureContext` トレイト（プロパティとジオメトリの種類）に対して行う。`feature_inputs` で、式が読むプロパティを列挙できる。
  - レイヤーの filter・色・不透明度・線幅を `Expr` で持つようにした。Phase 3 の `GeometryFilter` は削除した。
- **地物ごとに変わる paint**（ユーザー判断：属性値でグループ分け）：
  - Worker は、paint が読むプロパティの値の組み合わせで地物をグループに分け、グループごとに別のエントリとして詰める（1レイヤー・1タイルあたり最大 `MAX_GROUPS` = 64）。エントリには、そのグループの値を JSON で付ける（ヘッダは1エントリ9語に増やした）。
  - main は、描くたびに現在のズームでグループごとの paint を評価し、uniform で渡す。頂点属性は増やしていない。
  - filter は Worker で、タイルのズームを使って評価する（MapLibre と同じ）。
- **`map`**：スタイルの JSON は JS の `JSON.parse` で読み、MoonBit の `Json` に変換する（MoonBit の JSON パーサを main のバンドルに入れない）。評価は `JsProps` という1つの型で行い、`Expr::eval` がバンドルに1つだけ入るようにした。
- **ベンチと example**：`bench/render` と `bench/worker` は、`bench/maplibre/style.json` を両エンジンにそのまま渡すようにした。`examples/basic/style.json` も同じレイヤーにした。

### ベンチ結果：描画（Chromium 156 + ANGLE Metal / M2、1280×800、DPR 2、`bench/maplibre/style.json`、11回の中央値）

| | mbmap | MapLibre 6.16.0 |
|---|---|---|
| メインの JS（gzip） | **20.6KB**（minify 後） | 295.5KB |
| Worker（gzip） | **77.1KB**（JS グルーと wasm-gc） | 148.0KB |
| 初回描画（ナビゲーション開始 → 初回 `idle`） | **98ms** | 99ms |
| 　うち import 完了 | 44.3ms | 58.4ms |
| 　うち地図の作成 → `idle` | 46ms | 32ms |
| パン・ズーム中のフレーム間隔の平均 / p95 | 16.67 / 17.3〜17.5ms | 16.67 / 17.4〜17.6ms |
| 1フレームの rAF の CPU 時間（p50 / p95） | **0.24〜0.31 / 0.43〜0.52ms** | 0.88〜1.07 / 1.35〜1.63ms |
| 20ms を超えたフレーム | 0 | 0 |

- 式とグループごとの paint を加えても、1フレームの CPU 時間は MapLibre の約1/3。数値はリファクタリング後のもの。代理指標の目標（p95 が 1.44ms 以下、20ms 超のフレーム 0）は満たしている。

> **訂正（Phase 9.2）**：この表の MapLibre は、タイルが読めずに空の地図を描いていた（`bench/render/page.mjs` のタイル URL の不具合）。MapLibre の列と比較の結論は無効。正しい比較は Phase 9.2 にある。mbmap の数値は有効。
- **5回の中央値では、最初の数回（ブラウザが温まっていない）に引きずられて、mbmap が 116ms になった**。11回では、mbmap 97〜100ms（11回中9回）、MapLibre 99〜102ms で安定したので、既定を11回に変えた。
- vsync なしでは、フレーム間隔の平均が mbmap 1.14〜1.40ms、MapLibre 0.99〜1.35ms だった（`bench/results/render-chromium-uncapped.json`）。Phase 3 と同じく、GPU との同期待ちが支配的。

### ベンチ結果：Worker の `process_tile`（35タイル、ms、`bench/maplibre/style.json`）

| | 温まった状態：中央タイル / タイル中央値 | 冷えた状態：最初の1枚 / タイル中央値 | 同じコードで Phase 3 のスタイル（温まった状態のタイル中央値） |
|---|---|---|---|
| Chromium 156 | 2.53 / 6.82 | 24.3 / 7.54 | 5.83（Phase 3：5.80） |
| Firefox 157 | 3.28 / 8.86 | 22.8 / 9.44 | 7.54（Phase 3：7.42） |
| WebKit 27.2 | 2.80 / 7.20 | 27.2 / 8.26 | 6.16（Phase 3：6.18） |

- Phase 3 のスタイル（定数の paint）では Phase 3 と差がないので、式の評価そのものの負担は誤差の範囲。
- 時間が増えたのはスタイルが重いため。道路の casing と本体は filter が違うのでバッファを共有できず、本体と建物は paint の値でグループに分かれる。

### サイズと速度の改善（計測して判断したもの）

| 候補 | 結果 | 判断 |
|---|---|---|
| Debug 表示（`Repr`）と `@string.parse_double` を、出荷するコードから外す（エラーは `message()` の文字列、色の数値は小さな自前のパーサ） | メインの gzip 49.1 → 20.65KB、Worker の wasm 82.4 → 75.4KB | 採用 |
| main での評価を1つの型（`JsProps`。null のオブジェクトを「地物なし」とする）にまとめる | 20.65 → 20.49KB（minify 後は約 11KB 減） | 採用 |
| ヘッダの大きさを、全レイヤーに64グループ分ではなく、グループに分けるレイヤーだけ64、ほかは1にする | 出力 59.69 → 58.97MB（35タイル）。時間は誤差の範囲 | 採用 |

### リファクタリング（同じ PR に追加）

AGENTS.md §7 の観点で点検した。

- 定数：グループのプロパティでジオメトリの種類を運ぶキー `"$type"` を、`@core.GEOMETRY_TYPE_KEY` にまとめた（Worker と main の両方が使う）。
- 重複・無駄：範囲外で描かないレイヤーの paint を評価していたのをやめた。`tile_transform` をメッシュごとではなくタイルごとに1回にした。
- テスト：`Style::from_json`、`StyleError::message`、`MvtError::message` と、`rgb()` の数値パーサの境界（`.5`、`1.2.3`、空、負、指数表記）を直接テストした。
- セキュリティ（§8）：式のネストに上限を設けた（Phase 4 本体で対応済み）。グループのプロパティは JSON.parse で作り、`Object.hasOwn` で読むので、`__proto__` を含むタイルでもプロトタイプは汚染されない。`npm audit` は 0 件。

速度の候補：

| 候補 | 結果 | 判断 |
|---|---|---|
| P1：`Expr::eval` のクロージャとイテレータをやめ、再帰とループで書く（wasm-gc ではノードごとに確保が起きるため） | Worker のタイル中央値：Chromium 6.54 → 6.60ms、Firefox 8.48 → 8.86ms、WebKit 7.10 → 6.84ms。誤差の範囲 | 元に戻した。filter の評価は Worker の主なコストではない |
| P2：グループごとの paint を、メッシュに評価時のズームと一緒にキャッシュする（パン中は評価しない） | パンの rAF の CPU 時間 p50 / p95：改善前 0.33〜0.36 / 0.58〜0.63ms（3回）、改善後 0.31 / 0.52〜0.56ms（2回）。ズーム中は変わらない。メインは +0.15KB | 採用（効果は小さいが、範囲が重ならない） |

### 既知の問題・次にやること

- **地図の作成から `idle` までが、MapLibre より約14ms 遅い**（Phase 3 から変わらず）。import が速いぶん、初回描画全体ではまだ同等。
- **1レイヤー・1タイルで値の組み合わせが64を超えると、超えた分の地物は64番目のグループの paint で描かれる**。プロパティ値から連続的に変わる paint（例：`["get", "width"]` をそのまま線幅に使う）は、グループではなく頂点属性で扱う必要がある。必要になったときに計測して決める。
- 未対応の式：`to-number` などの型変換、算術（`+` `*` など）、`let` / `var`、`feature-state`。layout プロパティ（`line-join` など）は定数だけ読む。
- 半透明の線で join の内側が重なる件（Phase 2）は、まだ残っている。
- メインと Worker の両方がスタイルの JSON を解析している。スタイルの vector source は1つしか扱わない。

### 次にやること（Phase 5）

- npm パッケージ（TS ファサード、`.d.ts`、ESM）と、サイズ計測の CI
- 完了条件：`npm pack` した成果物で example が動くこと

## Phase 3：`worker` + `render_webgl2` + `map` 最小版（2026-10-31）

状態：**完了**（完了条件「fill / line / background が表示され、パン・ズームできる example」を満たした）。

### できたこと

- **`core`**：`Camera`（中心とズーム。値として受け渡しできる）と `Transform`。テストは全ターゲットで7件。
  - 画面座標とメルカトル座標の相互変換。
  - パン、カーソル位置を中心にしたズーム（その点が動かない）。
  - ズームと緯度の制限、経度の折り返し。
  - タイルズームの決定と、画面を覆うタイルの列挙（中心に近い順）。
  - タイル→クリップ空間のアフィン変換（`TileTransform`）。
  - `TILE_EXTENT`（4096）を定義した。
- **`style`（最小版）**：Phase 3 で描ける範囲だけを読む。
  - vector source（`tiles`、minzoom / maxzoom）。
  - background / fill / line レイヤー。`["==", ["geometry-type"], t]` 形式の filter、定数の色・不透明度・線幅、join / cap / miter-limit / round-limit、`visibility: none`。
  - 色は `#rgb`、`#rgba`、`#rrggbb`、`#rrggbbaa`、`rgb()`、`rgba()` と、名前3つ。
  - 未対応の種類のレイヤーは読み飛ばす。式（配列）や未対応の filter は、JSON 上の場所付きで `Unsupported` エラーにする。
- **`worker`**：
  - `TileProcessor`（純 MoonBit、全ターゲットでテスト）。スタイルのうち、そのソースの fill / line レイヤーを、MapLibre と同じくタイルのズームで判定して処理する。結果を `PackedTile` に詰める。
  - `PackedTile` の中身：ヘッダ（レイヤーごとに7語）、Int16 の座標（`TILE_EXTENT` に換算し、Int16 の範囲にクランプ）、16bit か 32bit のインデックス。上限は 64MB で、超えたらエラーにする。
  - wasm-gc のエクスポート（`linear_memory.mbt`）と、JS グルー（`worker/js/worker.mjs`）。グルーは fetch（認証情報を送らない、`AbortController` 付き）、線形メモリへの入出力、ArrayBuffer の transfer を担う。
- **`render_webgl2`**：
  - WebGL2 の FFI は、少数の高水準な JS 関数にまとめた。
  - fill のシェーダと、line のシェーダを用意した。line は押し出しを画面ピクセルで行うので、ズームしても線幅が一定になる。`length(side, along)` で、アンチエイリアスと丸い cap を描く。
  - 合成は premultiplied alpha。読み込み中の代わりに描く親タイルの範囲は scissor で切り取る。
- **`map`**：公開 MoonBit API（`Map::new`、`camera`、`set_camera`、`on_move`、`on_idle`、`off`、`destroy`）。
  - 入力：ドラッグでパン、複数ポインタでピンチズーム、ホイールでカーソル位置を中心にズーム。
  - タイル：画面を覆うタイルを要求し、不要になった読み込みは取り消す。LRU のキャッシュ（96枚）を持つ。
  - 読み込み中のタイル：読み込み済みの祖先（最大4段上、scissor で切り取る）か、子タイルで代わりに描く。
  - フレームループは、変更があったときだけ描く。DPR に対応し、`ResizeObserver` で大きさの変化を拾う。
  - Worker 数の既定は「ハードウェアスレッドの半分、1〜4」（VISION §4-7）。
  - VISION §6 のとおり、値が変わらない `set_camera` ではイベントを出さない。
- **`bundle/main`**：JS 向けのエクスポート。npm の TS ファサード（Phase 5）がこれを包む。
- **`examples/basic`**：国土地理院のタイル（fixture）を描く例。`npm --prefix bench run example` で配信できる。Playwright で次を確認した。
  - 描画のスクリーンショット。
  - ドラッグでカメラが動き、`move` が5回出ること。
  - ホイール 450px でズームが 14.5→15.0 になること（ズームの中心は固定）。
  - オーバーズーム時の見た目。
- **`bench/render`**：mbmap と MapLibre を、同じスタイル・同じタイル・同じカメラ操作で比べるベンチ（`npm --prefix bench run render`）。

### ベンチ結果：描画（Chromium 156 + ANGLE Metal / M2、1280×800、DPR 2、`examples/basic/style.json`、5回の中央値）

| | mbmap | MapLibre 6.16.0 |
|---|---|---|
| メインの JS（gzip） | **49.0KB**（minify 後） | 295.5KB |
| Worker（gzip） | **71.1KB**（JS グルーと wasm-gc） | 148.0KB |
| 初回描画（ナビゲーション開始 → 初回 `idle`） | **98ms** | 100ms |
| 　うち import 完了 | 45ms | 58ms |
| 　うち地図の作成 → `idle` | 45ms | 33ms |
| パン・ズーム中のフレーム間隔の平均 / p95 | 16.67 / 17.3〜17.5ms | 16.67 / 17.4〜17.6ms |
| 1フレームの rAF の CPU 時間（p50 / p95） | **0.17〜0.23 / 0.29〜0.44ms** | 0.77〜0.92 / 1.30〜1.52ms |
| 20ms を超えたフレーム | 0 | 0 |

- 1フレームの CPU 時間は MapLibre の約1/4。代理指標の目標（p95 が 1.44ms 以下、20ms 超のフレーム 0）は満たした。

> **訂正（Phase 9.2）**：この表の MapLibre は、タイルが読めずに空の地図を描いていた（`bench/render/page.mjs` のタイル URL の不具合）。MapLibre の列と比較の結論は無効。正しい比較は Phase 9.2 にある。mbmap の数値は有効。
- バンドルの目標（メイン 50KB 以下、Worker 80KB 以下）も満たした。ただし、メインは 49.0KB で余裕がない。
- **初回描画は MapLibre とほぼ同じで、「より短い」という目標ははっきりとは達成できていない**。mbmap は import が速く、地図を作ってから `idle` までが遅い（既知の問題を参照）。
- vsync なしで測ると、フレーム間隔の平均は mbmap 1.11〜1.44ms、MapLibre 0.94〜1.27ms だった。どちらも GPU との同期待ちが支配的で、rAF の CPU 時間は比較に使えない（`bench/results/render-chromium-uncapped.json`）。

### 改善と、その計測

- **丸い cap をシェーダで描くようにし、インデックスを可能なら16bit にした**。中央タイルの出力が 2.04MB から 0.79MB に、`process_tile`（温まった状態）が 5.4ms から 3.2ms になった。道路の各レイヤーの頂点数は 4.3万から 1.9万に減った。
- **Worker 数を「ハードウェアスレッドの半分」にした**。2のときは最初のタイルが2つずつ待たされていた。
- **初期化時に合成タイルでウォームアップする案を試したが、効果がなかったので削除した**（4回ずつ2組の比較で、作成→idle の中央値は、あり 60・61ms、なし 54・61ms）。

### リファクタリングと速度改善（同じ PR に追加）

AGENTS.md §7.5 に、リファクタリングのたびに速度を改善できる余地を確かめる観点を加えた（コストを先に測る、効果が誤差を超えたものだけ残す、試してやめたことも記録する）。そのうえで、`bench/worker`（`process_tile` を全 fixture で計測。冷えた状態と温まった状態）を新設し、候補を1つずつ測った。

| 候補 | 結果 | 判断 |
|---|---|---|
| S1：同じジオメトリのレイヤーで、バッファを共有する（道路の casing と本体など。線の押し出しは幅で正規化してあるので、頂点は同じになる） | Chromium のタイル中央値 7.97 → 6.98ms、出力 69.3 → 57.5MB | 採用 |
| S2：線形メモリに直接書き込み、`FixedArray` からのコピーをなくす（wasm-gc では `store_memory.mbt`、ほかのターゲットでは `store_array.mbt`） | Chromium のタイル中央値 6.98 → 5.96ms | 採用 |
| S3：wasm を main で一度だけコンパイルし、`WebAssembly.Module` を各 Worker に配る | 交互に2組ずつ比べて、作成 → idle の中央値は 46 / 46ms で同じ | 元に戻した |

最終の `process_tile`（35タイル、ms）：

| | 温まった状態：中央タイル / タイル中央値 | 冷えた状態：最初の1枚 / タイル中央値 | 改善前（温まった状態のタイル中央値） |
|---|---|---|---|
| Chromium 156 | 2.10 / 5.80 | 16.1 / 6.27 | 7.97（−27%） |
| Firefox 157 | 2.72 / 7.42 | 17.8 / 7.90 | 9.60（−23%） |
| WebKit 27.2 | 2.34 / 6.18 | 20.9 / 6.64 | 8.20（−25%） |

- 描画ベンチの最終値は次のとおり。
  - 初回描画：mbmap 97ms、MapLibre 100ms。
  - 作成 → idle：mbmap 46ms、MapLibre 34ms。
  - 1フレームの CPU 時間（p95）：mbmap 0.28〜0.43ms、MapLibre 1.34〜1.57ms。
  - サイズ（gzip）：メイン 49.1KB、Worker 71.6KB。
- **タイルの処理が速くなっても、作成から idle までの時間は変わらなかった**。ボトルネックはタイル処理以外にある（Worker の起動、最初のアップロードと描画など）。次は、ここを分けて測る。

**その他の変更**：
- example に `?remote=1`（国土地理院のライブ配信、z4〜16）を追加した。fixture は z14 だけなので、ズームアウトすると何も描かれなかった件への対応。
- extent が `TILE_EXTENT` 以外のレイヤーを換算する処理と、バッファ共有のテストを追加した。
- `linear_memory.mbt` を wasm-gc 専用にした。wasm バックエンドでは、線形メモリに MoonBit 自身のヒープがあるため。

### 既知の問題・次にやること

- **地図の作成から `idle` までが、MapLibre より約12ms 遅い**。主な原因は、各 Worker の最初のタイルが最適化前のコードで動くこと（`process_tile` が温まった状態の3〜5倍かかる）。対策の候補は次のとおり。
  - main で一度だけコンパイルした `WebAssembly.Module` を Worker に配る。
  - 最初のタイルを分割して処理する。
  - 本番環境では Chrome の wasm コードキャッシュ（128KB を超えるモジュールが対象）が効くので、それも含めて測る。
- **メインのバンドルは 49.0KB で、目標まで余裕がない**。Phase 4 で式の評価を加える前に、何が大きいかを調べる（JSON パーサ、Debug 表示用のコードなど）。Worker の wasm（157KB、gzip 69KB）も同様に調べる。
- `map` と `render_webgl2` は DOM に依存するので、単体テストがない。カメラの計算は `core` で、タイルの処理は `worker` でテストし、統合部分は Playwright での操作で確かめた。
- スタイルの vector source は1つしか扱わない（レイヤーが最初に参照するもの）。
- 半透明の線で join の内側が重なる件（Phase 2）は、まだ残っている。
- メインと Worker の両方がスタイルの JSON を解析している。

### 次にやること（Phase 4）

- `style` のサブセット：filter（`==` `!=` `in` `all` `any` `get` `has` `match`）と、`interpolate` / `step` によるズーム依存の値
- 地物ごとに変わる paint（`match` による色など）の扱い。Worker で評価して頂点属性にするか、レイヤーを分けるかを、計測して決める
- 完了条件：`bench/maplibre/style.json`（国土地理院の簡易スタイル）がそのまま描けること。そのうえで初回描画とフレームを MapLibre と比べる

## Phase 2：`tess`（earcut の移植、線の展開）（2026-10-31）

状態：**完了**（完了条件「面積一致テスト、JS 版 earcut との速度比較」を満たした）。

### できたこと

- **`Earcut`**：earcut 3.2.4（ISC）の移植（`refine` は除く）。
  - 処理順も JS と同じにしたので、出力の三角形が JS 版と完全に一致する。
  - ノードはオブジェクトにせず、使い回せるプール配列（`FixedArray`）の添字で表す。そのため、2回目以降の呼び出しでは確保が起きない。
  - 面積の相対誤差を返す `deviation` も移植した。
- **`FillTessellator`**：MapLibre の塗りの処理と同じ手順で、ポリゴン地物を三角形分割する。
  - リングは `classifyRings`（BSD-3 の移植）と同じ規則で外周と穴に分ける。穴は面積の大きい順に最大500リングまで残し、面積0のリングは捨てる。
  - 分けたポリゴンごとに earcut をかけ、使い回せる `FillBuffers` に追記する。
- **`LineTessellator`**：線を三角形に展開する。
  - 頂点は x, y、ex, ey（×63 の量子化値）、side（±1 / 0）。
  - join は miter（`miter_limit` を超えたら bevel。上限は Int8 に収まる2）、bevel、round（`round_limit` 未満なら miter）。
  - cap は butt、square、round。
  - 閉じた線は、始点でも join を作り、cap は付けない。
  - ほぼ直線の箇所では、前後の線分で頂点を共有する。
  - 丸い cap・join の扇形は、回転を順に掛けて作る（頂点ごとの三角関数なし）。
- **テスト**：`tess` に17件（全体で47件、全4ターゲットで通過）。
  - earcut：JS 3.2.4 と同じ出力になること。JSDoc の例は古い版の出力なので、JS で実行して確かめた値を使った。
  - 面積：穴あきポリゴンと、80頂点を超えて Z オーダーのハッシュを使う場合の面積が一致すること。
  - リングの分類と、穴を500リングで打ち切る処理。
  - 線：三角形の面積が、直線・90°の miter・bevel・square cap で厳密に一致すること。round の cap・join は円の面積の95〜100%に入ること。
  - インデックスの範囲、Int8 の範囲、重複点・1点だけの線。
- **黄金テスト**：`bench/tess/golden.mjs`（`npm --prefix bench run tess:golden`）。
  - 全35タイル・**142,853のポリゴン地物で、MapLibre の処理（classifyRings + earcut 3.2.4）と頂点・インデックスが完全に一致した**。
  - 同じ三角形分割の **142,925ポリゴンすべてで、earcut の `deviation`（面積の相対誤差）が 0** だった。
  - わざと入れた差分は、どの地物かまで特定して検出できる。
- **ベンチ**：`bench/tess/`（`tess:node` / `tess:browser`）。mbmap の処理と MapLibre `WorkerTile.parse` を、同じ Worker・同じタイル・同じスタイルで測る。
  - `bench/lib` に、計測（`rows.mjs`）、Worker での実行（`worker-bench.mjs`）、esbuild 設定（`bundle.mjs`）、fixture の読み込みをまとめた。
  - mvt ベンチもこれを使うように書き換え、MoonBit 側の公開面は `bench/entry` 1つにした。
- NOTICE と移植したファイルの先頭に、earcut（ISC）と classifyRings（BSD-3）のライセンス全文・出典を記載した。

### ベンチ結果：デコード＋テッセレーション（35タイル、各タイル15反復の中央値、ms）

mbmap の処理は、`bench/maplibre/style.json` が描く内容と同じです。面レイヤー（waterarea / structurea / building のポリゴン）を三角形分割し、線レイヤー（建物の輪郭・contour・river・road の casing と本体・railway・boundary）を、スタイルの filter / join / cap どおりに展開します。

| | Chromium 156 | Firefox 157 | WebKit 27.2 | Node 22 |
|---|---|---|---|---|
| MapLibre `WorkerTile.parse`（中央タイル / タイル中央値） | 6.41 / 16.15 | 10.34 / 28.92 | 6.06 / 15.80 | 9.41 / 23.35 |
| **mbmap wasm-gc デコード＋面＋線** | **2.27 / 5.23** | **3.40 / 7.98** | **2.52 / 5.72** | **2.44 / 5.90** |
| MapLibre 比（中央タイル / タイル中央値） | 35% / 32% | 33% / 28% | 42% / 36% | 26% / 25% |
| （内訳）デコードのみ／＋面／＋線 | 1.38 / 2.59 / 4.00 | 1.76 / 3.52 / 5.90 | 1.86 / 3.08 / 4.44 | 1.57 / 2.88 / 4.59 |

- **目標の「1タイルのデコード＋テッセレーションが MapLibre の1/2以下」を、すべての環境で下回った**。中央タイルは 2.27〜3.40ms で、目標の 4.6ms 以下も満たしている。
- **ただし、この比較は mbmap に有利**です。MapLibre はこのほかに、スタイル式の評価、地物ごとの paint 属性の書き込み、FeatureIndex、GPU 用の詰め込み済みバッファ作成をしています。mbmap の出力はまだ `Array[Int]` です。正式な比較は、Worker が GPU 用のバッファまで出すようになる Phase 3〜4 で行う。

**earcut 単体**（「デコード＋classifyRings＋earcut」から「デコードのみ」を引いたもの。タイル中央値、ms）

| | Chromium | Firefox | WebKit |
|---|---|---|---|
| JS（earcut 3.2.4 + classifyRings） | 1.00 | 2.52 | 1.24 |
| mbmap wasm-gc | 1.21 | 1.76 | 1.22 |

- Firefox では30%速く、WebKit では同等、**Chromium では21%遅い**。
- Node はこの回の JS「デコードのみ」の値がばらついた（2.61ms。前の回は 1.08ms）ので、比較から外した。

### 性能について分かったこと

- **ホットループでは `FixedArray` のほうが `Array` より速い**。`Array` へのアクセスは、長さの読み込みと範囲チェックが1回余分に入る。earcut のノードプールを `FixedArray` にしたら、Chromium で 1.63 → 1.24ms（24%短縮）になった。
- **頂点ごとの三角関数をやめて回転を順に掛けるようにしたら、線の展開が速くなった**。Chromium で 4.01 → 2.44ms（39%短縮）。
- earcut 3.2.4 の `src/earcut.js` の JSDoc にある出力例（`[1,0,3, 3,2,1]`）は古く、実際の出力（`[1,0,3, 1,3,2]`）と違う。テストは JS で実行して確かめた値にした。

### 既知の問題・注意点

- **Chromium では earcut が JS より21%遅い**。node プールへのアクセスがまだ多いので、次に削るならここ。
- 500リングを超えるポリゴンで残す穴の集合は MapLibre と同じだが、MapLibre は quickselect を使うので並び順が違い、三角形の順序も変わりうる。fixture にはそのような地物がないので、黄金テストには影響しない。
- 線の bevel・round join では、内側で前後の quad が重なる。不透明な線では問題ないが、半透明の線では重なった部分が濃くなる（MapLibre も一部で同様）。Phase 3 の描画で目立つようなら、ステンシルなどで対処する。
- 線の頂点は、MapLibre（丸い cap をシェーダで描く）より多い。GPU へ送るデータ量の比較は Phase 3 で行う。
- タイルごとの出力サイズ（頂点数・インデックス数）の上限は、まだ設けていない（AGENTS.md §8.2）。Phase 3 で Worker の出力バッファを作るときに入れる。
- 点・円のテッセレーション（VISION §3 の `tess`）は、circle レイヤーを扱う Phase 7 で入れる。

### 次にやること（Phase 3）

- `worker`：Worker のエントリ、メッセージプロトコル、GPU 用の詰め込み済みバッファ（Int16 の頂点、16/32bit のインデックス）を transfer で渡す
- `render_webgl2`：WebGL2 の FFI、fill / line / background のシェーダと描画パス
- `map`：カメラ、パン・ズーム、タイルの選択とキャッシュ、フレームループ
- example：fill / line / background が表示され、パン・ズームできる。初回描画とフレーム時間を MapLibre と同じ条件で計測する

## Phase 1：`core` / `pbf` / `mvt`（2026-10-31）

状態：**完了**（完了条件「実タイルを JS 実装と同一結果でデコード。デコード速度を計測」を満たした）。

### できたこと

- **`core`**：`LngLat` / `MercatorCoord` と Web Mercator 変換（MapLibre と同じ式）、`TileId`（`new` で範囲を検証、`parent` / `children` / `key` / `mercator_bounds` / `lnglat_bounds`）、`tile_containing`、`BBox`。
  行列は Phase 3 でカメラと一緒に入れる。
- **`pbf`**：ゼロコピーの `Reader`（`BytesView` 上のカーソル）と、テスト用の最小 `Writer`。
  - 読み取りは `raise` せず、最初のエラーを Reader に記録してから末尾に移動する（エラー状態を保持する方式）。そのため、不正な入力でもループは必ず止まる。
  - varint は10バイトまで、長さは残りバイト数以内に制限し、group 型は拒否する。
  - 入れ子のメッセージは、新しいオブジェクトを作らずに範囲を一時的に狭めて読む（`enter` / `exit`）。Reader を別の範囲に移して使い回すこともできる（`reset`）。
- **`mvt`**：MVT 2.1 デコーダ。
  - `Tile::parse` の時点で、レイヤーの keys / values、全地物のヘッダ（id・type・ジオメトリの範囲）、タグを読む。これらは地物ごとのオブジェクトを作らず、列ごとの配列に持つ。タグのインデックス範囲も、ここで一度だけ検証する。
  - ジオメトリは `Layer::decode_geometry(i, out)` を呼ぶまでデコードしない。出力は使い回せるバッファ `Geometry`（x, y を交互に並べた座標と、リングの終端）で、結果は `Bool`、エラーの詳細は `Geometry::error()` で返す。
  - プロパティは `properties(i)`（Map）のほか、確保なしの `key_index` / `property(i, key)` で引ける（スタイル評価用）。
  - 不正なコマンド列はエラーにする。未知のコマンド、MoveTo より前の LineTo、count が2以上の ClosePath、残りバイト数を超える count がこれに当たる。これで、巨大な count による暴走を防ぐ。
- **テスト**：`moon test --target all` で30件（wasm / wasm-gc / js / native すべて通過）。
- **黄金テスト**：`bench/mvt/golden.mjs`（`npm --prefix bench run mvt:golden`）。
  - 35枚の実タイルを js ビルドでデコードし、`@mapbox/vector-tile` の出力と完全に比較する。比べるのは全レイヤーの version・extent と、全地物の id・type・properties・geometry で、**35/35 が一致した（417,636地物）**。
  - wasm-gc ビルドも、点数・プロパティ数・座標の総和が一致することを確認する。
  - 比較処理がわざと入れた差分を検出することも確かめた。
- **デコード速度のベンチ**：`bench/mvt/`（`mvt:node` / `mvt:browser`）。

### ベンチ結果：MVT デコード（35タイル、各タイル15反復の中央値、ms）

処理内容はどの実装でも同じで、タイルをパースし、全地物のプロパティ（Map / object）と全ジオメトリを取り出す。wasm-gc の行には、タイルのバイト列を wasm の中へコピーする時間も含む。

| 実装 | Chromium 156 タイル中央値（合計） | Firefox 157 | WebKit 27.2 | Node 22 |
|---|---|---|---|---|
| JS（`@mapbox/vector-tile` 3.0.0） | 3.20（109.0） | 5.20（176.1） | 2.26（76.1） | 3.31（112.7） |
| **mbt-wasm-gc** | **2.07（71.0）** | **3.02（105.5）** | 2.58（90.6） | **2.33（79.5）** |
| mbt-js（参考） | 6.06（208.3） | 11.96（417.0） | 3.98（136.0） | 6.69（229.9） |

- wasm-gc 版は、Chromium で JS より **35% 速く**、Firefox で **42% 速く**、Node で **30% 速い**。**WebKit では14%遅い**（既知の問題）。
- 中央タイル 14/14552/6451 では、Chromium で 1.04ms（JS は 1.54ms）。
- wasm-gc 版の内訳（Chromium、タイル中央値。どれもコピー込み）：
  - コピーのみ：0.14ms
  - パースのみ：0.68ms
  - パース＋プロパティ：1.44ms
  - パース＋ジオメトリ：1.27ms
- Worker の入力受け渡しは、Phase 0 で持ち越した2案のうち、**線形メモリから GC の `Bytes` へ wasm 内でコピーする方式**に決めた。4バイト単位で読む実装で、1MB あたり 0.3〜0.8ms かかる。生アドレスを直接読む方式は、pbf をバックエンドに依存させてしまうので採らない。
- js ターゲット版はどのブラウザでも遅い。Worker は wasm-gc なので問題にはならない。

### 性能について分かったこと（生成コードと計測で確認）

- **wasm-gc では、`raise` する関数を呼ぶたびに結果オブジェクトが確保される**（成功した場合も `Result.Ok` 構造体を作る）。
  最初の実装は読み取り関数がすべて `raise` していて、JS の 1.3〜2.2倍遅かった。読み取りを `raise` しない形に変え、地物を配列で持つようにしたことで、JS より速くなった。
  そのため、ホットパスでは `raise` を使わず、エラーは境界で返す（`Tile::parse` は `raise`、地物ごとの処理は `Bool` や記録済みのエラーで返す）。
- **wasm-gc に `wasm-opt -O3` をかけると、どのブラウザでも遅くなった**（Chromium で33%、Firefox で12%、WebKit で45%遅い）。Phase 0 の単純なループでは差がなかった。そのため、wasm-gc には使わない。
- `Bytes::makei` は1バイトごとにクロージャを呼ぶので、wasm 内のコピーに使うと遅かった。`FixedArray[Byte]` に4バイトずつ書いてから、`unsafe_reinterpret_as_bytes`（コピーなし）で `Bytes` に変えると、2〜6倍速くなった。

### 既知の問題

- **WebKit では JS より14%遅い**（タイル中央値 2.58ms 対 2.26ms）。JSC の JS 実行が特に速いことと、コピー（0.34ms）が相対的に重いことが効いている。Phase 2 でテッセレーションまで含めて測ってから、手を打つか判断する。
- `moon run` のスクリプトモード（`.mbtx`）が、core の `gzip` パッケージの別名衝突（`async/gzip` と `compress/gzip`）で動かない（moon 0.1.20261028）。自動化は Node スクリプトのままにしている。
- `FixedArray::unsafe_reinterpret_as_bytes` は `#internal(unsafe)` の API で、ベンチの入力受け渡し（`bench/entry`）でだけ使っている。Phase 3 で `worker/` に移すときに、この使い方でよいか見直す。
- 悪意のあるタイルでは座標の累積が Int32 で桁あふれして折り返す。安全性の問題は起きないが、Int16 に量子化するとき（`tess`）にクランプする必要がある。

### 次にやること（Phase 2）

- `tess`：earcut の移植（ライセンスと出典を NOTICE に記載）と、線の展開（join / cap、ミター制限）
- 三角形の総面積が元のポリゴンと一致することのテストと、JS 版 earcut との速度比較
- `WorkerTile.parse` の基準値（中央タイル 9.2ms）との比較を始める。目標は中央タイル 4.6ms 以下（デコード＋テッセレーション）

## Phase 0：環境確認・雛形・ベンチ基盤・Wasm バックエンド比較（2026-10-31）

状態：**完了**（2026-10-31 にユーザー確認済み。決定事項は下の「決定事項」）。

### 環境

| 項目 | 値 |
|---|---|
| マシン | Apple M2, 8 コア, 8GB RAM, macOS 26.6.2 (25G83) |
| moon | `moon 0.1.20261028 (e1e1f15 2026-10-28)`。feature flags: `rr_moon_mod`, `rr_moon_pkg` |
| moonc / moonrun | `moonc v0.10.18+6c83a7f62 (2026-10-28)` / `moonrun 0.1.20261028` |
| 設定ファイル形式 | `moon.mod` / `moon.pkg`（新 DSL。`moon.mod.json` / `moon.pkg.json` ではない） |
| Node / npm / pnpm | v22.23.4（V8 12.4.254.21）/ 10.9.9 / あり |
| ブラウザ（Playwright 1.64.1） | Chromium 156.0.8078.4、Firefox 157.0、WebKit 27.2 |
| インストール済み | Google Chrome、Microsoft Edge、Safari |
| wasm-opt | binaryen 132（`bench/` の devDependency） |

### できたこと

- モジュール `t-ujiie-g/mbmap` と、VISION §3 の構成どおりの空パッケージ：`core` `pbf` `mvt` `tess` `style` `worker`（全ターゲット）、`render_webgl2` `map`（`supported_targets = "js"`）。
  `npm/` `element/` `adapters/` `examples/` は README のみ（MoonBit パッケージではない）。
- `moon check --target all`、`moon test --target all`（wasm / wasm-gc / js / native、2 tests pass）、`moon fmt`、`moon info` が通る。
- `bench/`：再現可能なベンチ基盤（手順は [bench/README.md](bench/README.md)）
  - `backend/`：wasm / wasm-gc / js（＋ wasm-opt 版）の比較。Node と、3 ブラウザの **module Worker 内**で実行。
  - `maplibre/`：MapLibre GL JS 6.16.0 の基準値（バンドルサイズ、`WorkerTile.parse`、初回描画、フレーム時間）。
  - `fixtures/`：国土地理院 `experimental_bvmap` z14 東京駅周辺 35 タイル（sha256 マニフェストのみコミット）。
  - `maplibre/style.json`：background / fill / line だけの共通スタイル。両エンジンで同じものを使う。
- LICENSE（Apache-2.0）、NOTICE（出典表記）。

### MoonBit バックエンドについて分かったこと（生成コードで確認）

- **wasm（線形メモリ）**：`FixedArray[T]` の値はデータ先頭を指す i32 ポインタで、長さはその 4 バイト前にある。
  JS から `new Float32Array(memory.buffer, ptr, n)` でそのまま読み書きできる。メモリ管理は参照カウント＋TLSF で、
  解放もされる（1MiB × 500 回確保しても線形メモリは 4.75MiB のまま）。
- **wasm-gc**：`FixedArray[Float]` = `(array (mut f32))`、`Bytes` = `(array (mut i8))`。JS からは中身が見えない。
  ただし wasm-gc モジュールも線形メモリを 1 ページ持っていて、`extern "wasm"` のインライン wasm
  （`i32.load8_u`、`f32.store`、`memory.grow`）で読み書きできる。`export-memory-name` で JS にも公開できる。
- **js**：`FixedArray[Byte]` / `Bytes` = `Uint8Array`（ゼロコピーで入力できる）。`FixedArray[Float]` = 素の JS `Array`
  （typed array ではない）。`.d.ts` も生成される。
- MoonBit の出力は、小さな関数（`check_range`、`array_length`、インライン extern）を wasm のレベルではインライン化していない。
  新しい V8（Chromium 156）、SpiderMonkey、JSC はエンジン側でインライン化するので問題ないが、**Node 22（V8 12.4）では wasm（線形メモリ）版が 2〜3 倍遅い**。
  `wasm-opt -O3` を通すと解消する。

### ベンチ結果 1：デコード（100 万値、入力 1.35MB → transfer 可能な Float32Array 4MB）

中央値 ms（40 反復、ウォームアップ 15 回）。`total = in + decode + out`。出力は全バリアントで JS 参照実装と一致。

| バリアント | Chromium 156 total（decode） | Firefox 157 total（decode） | WebKit 27.2 total（decode） | Node 22 total（decode） |
|---|---|---|---|---|
| js-baseline（手書き JS） | 5.17（5.09） | 4.52（4.52） | 3.24（3.16） | 4.87（4.83） |
| mbt-js | 7.75（7.13） | 5.94（4.66） | 3.64（3.48） | 7.75（5.64） |
| mbt-js-ffi | 5.14（5.14） | 4.58（4.56） | 3.44（3.36） | 5.52（5.43） |
| mbt-wasm | 3.98（3.61） | 4.16（3.78） | 3.54（3.40） | 9.79（9.63） |
| mbt-wasm-raw | 3.53（3.17） | 3.74（3.38） | 3.30（3.16） | 6.81（6.66） |
| mbt-wasm+opt | 4.08（3.70） | 4.36（3.94） | 3.60（3.48） | 3.80（3.65） |
| mbt-wasm-gc（要素ごとの境界呼び出し） | 16.53（3.45） | 164.70（3.60） | 99.16（3.40） | 48.47（3.62） |
| **mbt-wasm-gc-mem** | **3.54（3.17）** | **3.76（3.40）** | **3.34（3.20）** | 3.57（3.42） |
| mbt-wasm-gc-copy | 5.21（3.43） | 5.42（3.60） | 5.02（3.36） | 5.14（3.62） |
| mbt-wasm-gc-mem+opt | 3.64（3.24） | 3.72（3.36） | 3.24（3.12） | 3.40（3.25） |

- 計算そのもの（decode 列）は、wasm と wasm-gc がほぼ同じ速さ。Chromium / Firefox では JS より **25〜35% 速い**。WebKit では JS と同等。
- 素朴な wasm-gc（要素ごとに export 関数を呼ぶ）は、境界のコストで使い物にならない（Firefox で 165ms）。
  **線形メモリ経由（`-mem`）にすれば wasm と同等**になる。wasm 内でコピーする方式（`-copy`）は 1MB あたり約 0.5ms の上乗せ。
- 出力を transfer するには、どの wasm 方式でも `view.slice()` で 1 回コピーが必要（4MB で約 0.34ms）。
  `memory.buffer` そのものは transfer できないため。つまり wasm（線形メモリ）の「ゼロコピー」の利点は、Worker → メインの経路ではほぼ相殺される。

### ベンチ結果 2：アロケーションの多い処理（10 万特徴量 × 32 点の boxed Point 配列）

| | Chromium | Firefox | WebKit | Node 22 |
|---|---|---|---|---|
| js-baseline | 9.4 | 14.0 | 12.6 | 9.4 |
| mbt-js | 7.2 | 23.3 | 12.7 | 9.0 |
| mbt-wasm | **86.7** | **120.4** | **77.0** | **135.2** |
| mbt-wasm+opt | 90.2 | 112.9 | 85.3 | 106.5 |
| mbt-wasm-gc | 9.8 | 17.3 | 12.0 | 15.6 |

- **wasm（参照カウント＋TLSF）は、アロケーションが絡むと wasm-gc / JS の 6〜9 倍遅い**。wasm-gc はホストの GC を使うので JS と同程度。
- VISION §4-1 のとおり、ホットパスではアロケーションしない方針だが、地物のプロパティ、スタイル式の評価、タイル単位の一時オブジェクトなど、
  アロケーションをゼロにはできない部分が残る。wasm を選ぶと、それらすべてで手動のメモリ管理が事実上必須になる。

### ベンチ結果 3：コードサイズ（bench/backend/entry、release、gzip -9）

| wasm | wasm+opt | wasm-gc | wasm-gc+opt | js |
|---|---|---|---|---|
| 5,025 B | 3,219 B | 2,805 B | 2,152 B | 1,147 B |

- wasm には TLSF アロケータと参照カウントのランタイムが入るぶん、固定の上乗せがある。wasm-gc はそれが要らない。wasm-opt でさらに 23〜36% 縮む。

### MapLibre GL JS 6.16.0 の基準値

**バンドルサイズ**（`dist/`、gzip -9 / brotli）

| ファイル | raw | gzip | brotli |
|---|---|---|---|
| maplibre-gl.mjs（メインスレッド） | 1,108,049 | **295,496** | 241,249 |
| maplibre-gl-worker.mjs | 519,372 | **148,036** | 121,563 |
| maplibre-gl.css | 71,596 | 10,161 | 8,326 |

**Worker 側の処理**（`WorkerTile.parse` = MVT デコード＋スタイル評価＋バケット生成＋テッセレーション。共通スタイル使用、
noSubdivision、Node 22、各タイル 15 反復の中央値）

| | parse | うちジオメトリデコードのみ（参考） |
|---|---|---|
| 中央タイル 14/14552/6451（179KB、23,696 点、10 バケット） | **9.2 ms** | 2.1 ms |
| 35 タイルの中央値 | **23.4 ms** | 3.3 ms |
| 35 タイルの合計（13.3MB） | 784 ms | 113 ms |

**描画**（ヘッドレス Chromium 156、ANGLE Metal / Apple M2、1280×800、DPR 2、タイルはローカル配信、5 回の中央値）

| 条件 | 初回描画（ナビゲーション開始 → 初回 `idle`） | パン中のフレーム平均 / p95 | `_render` の CPU 時間 p50 / p95 | 20ms 超のフレーム |
|---|---|---|---|---|
| 通常（vsync あり） | **215 ms**（import 完了 57ms） | 16.67 / 16.67 ms | 0.78 / 1.44 ms | 0 |
| vsync なし | 232 ms | 1.33 / 2.57 ms | 0.26 / 2.46 ms | 0〜1 |
| CPU 4倍スロットル | 322 ms | 16.67 / 16.67 ms | 0.83 / 1.98 ms | 0 |
| CPU 4倍スロットル、vsync なし | 335 ms | 1.44 / 3.03 ms | 0.97 / 2.86 ms | 0 |

（ズームのシナリオもほぼ同じ値。詳細は `bench/results/maplibre-render-*.json`）

### 提案：Worker のバックエンドは **wasm-gc**（I/O は線形メモリ経由）

理由（すべて上の計測値に基づく）：

1. **計算速度**：wasm と同等、Chromium / Firefox では JS より 25〜35% 速い。
2. **アロケーション**：wasm の 6〜9 倍速く、JS と同程度。style / mvt のコードを、GC 前提の素直な MoonBit で書ける。
   ホットパスだけ事前確保のバッファで書く、という VISION の方針と両立する。
3. **サイズ**：アロケータと参照カウントのランタイムが要らないぶん小さい（Worker の目標は gzip 80KB）。
4. **境界のコスト**：タイルのバイト列と出力バッファは、Worker 側で管理する線形メモリ領域を介してやりとりする。
   この形なら wasm（線形メモリ）と同じ速さで、transfer のための 1 回のコピーもどちらの方式でも同じ。

設計への影響：

- 計算コア（`core` `pbf` `mvt` `tess` `style`）は純 MoonBit のまま（バックエンド非依存。全ターゲットでテストする）。
- wasm-gc 専用の I/O 層（インライン wasm の load/store、領域の確保）を `worker/` だけに閉じ込める。
  `pbf` が入力を読む部分は、`Bytes` / `BytesView` を受ける版と、wasm 内でコピーする版のどちらにするかを Phase 1 で計測して決める。
  `-copy` 方式なら 1MB あたり約 0.5ms で安全、`-mem` 方式なら最速だが生アドレスを扱う。
- リリースビルドでは `wasm-opt -O3` を通す。速度はほぼ変わらないが、サイズが約 23% 減る。

不採用とした理由：

- **wasm（線形メモリ）**：アロケーションが絡む処理が遅いことと、ランタイムのサイズ。境界がゼロコピーという利点は、transfer の都合でほぼ消える。
- **js**：計算が wasm より遅く、`FixedArray[Float]` が typed array にならない（FFI で包む必要がある）。
  ただし、メインスレッド側（`render_webgl2` `map`）は js ターゲットのままでよい。

### 既知の問題・注意点

- **wasm-gc のブラウザ要件**：Chrome / Edge 119+、Firefox 120+、Safari 18.2+（iOS 18.2+）。iOS 18.1 以前は対象外とした。
- **フレーム時間の目標（中級 Android で 60fps）はこの環境では検証できない**（実機計測は当面行わない方針）。M2 では MapLibre でも vsync に張り付き（vsync なしで約 1.4ms/フレーム）、
  CDP の CPU スロットル（4倍）もメインスレッドの描画 CPU 時間にはほとんど影響しなかった。実機（Android Chrome のリモートデバッグ）が必要。
- 基準値の `WorkerTile.parse` は Node 22（V8 12.4）で計測している。mbmap 側も同じハーネスで比べる。
  加えて、Phase 2 でブラウザの Worker 内でも両方を計測する予定。
- MapLibre の初回描画（215ms）にはメインバンドルの import（57ms）が含まれる。ローカル配信なので、ネットワークの時間はほぼゼロ。
- ページ内に直接書いた `<script type="module">` が Playwright 上で実行されない現象があった（原因は未特定）。外部ファイル（`page.mjs`）に分けて回避した。
- wasm（線形メモリ）で JS に返したオブジェクトの参照カウントの扱い（所有権がどちらにあるか）は未調査。ベンチの entry では解放処理が生成されていなかった。wasm を採用する場合は Phase 1 の前に要調査。

### 性能目標の見直し案（VISION §2）

| 指標 | 現行の目標 | MapLibre の実測 | 提案 |
|---|---|---|---|
| メインスレッド側バンドル | gzip 50KB 以下 | 295KB | 据え置き（MapLibre の約 1/6） |
| Worker（Wasm 含む） | gzip 80KB 以下 | 148KB | 据え置き（約 1/2） |
| 1 タイルのデコード＋テッセレーション（z14 都市部） | MapLibre の 1/2 以下 | 中央タイル 9.2ms、35 タイルの中央値 23.4ms | 「中央タイル 4.6ms 以下、35 タイルの中央値 11.7ms 以下（同じハーネス・同じスタイル）」と数値化 |
| フレーム時間 | 中級 Android で 60fps、GC 停止なし | M2 では判定不能 | 実機を用意するまでの代理指標として「`_render` 相当の CPU 時間 p95 が MapLibre（1.44ms）以下、20ms 超のフレーム 0」を追加 |
| 初回描画まで | MapLibre より短い | 215ms（ローカル、M2） | 「同じ条件で 215ms 未満」 |

### 決定事項（2026-10-31 ユーザー確認）

1. Worker のバックエンドは **wasm-gc（I/O は線形メモリ経由）** を採用する。
2. iOS 18.1 以前の Safari（wasm-gc 非対応）は**対象外**。フォールバックは作らない。
3. 性能目標を上の見直し案で更新した（docs/VISION.md §2 に反映済み）。
4. 中級 Android の実機計測は当面行わない。フレーム時間は代理指標（描画 CPU 時間）で見る。

### 次にやること（Phase 1）

- `core`：タイル座標、Web Mercator、BBox
- `pbf`：ゼロコピー・遅延パースのデコーダ（`BytesView` を入力に取る）。入力の受け渡し方式（`-copy` か `-mem` か）を計測して決める
- `mvt`：ジオメトリを遅延展開するデコーダ。`@mapbox/vector-tile` の出力と突き合わせる黄金テストを `test/fixtures/` に置く
- デコード速度を、上の `maplibre-parse` のデコード列（中央タイル 2.1ms、35 タイルの中央値 3.3ms）と比べる
