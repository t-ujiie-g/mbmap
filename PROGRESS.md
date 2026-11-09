# PROGRESS

## 現在の状況（2026-11-08）

- **終わったもの**：Phase 0〜15 と、Phase 15 の後のリファクタリング・セキュリティチェック・計測（#73〜#78）。Phase 16 は 16.1（未対応の扱い、#79）、CSS の色（#80）、16.7（地形の表現、#81）、大きさの対策（スタイルのコンパイルを主スレッドだけに #83、表示ワーカーの JS を分ける #84）、16.2・16.4（線と平行移動、円、#85）、16.6（式、#86 と「Phase 16.6 の残り」）、16.3（並び順、#87）、16.5（文字、#88）と点のラベルの字の位置（#89）、16.8 の OpenMapTiles 系（#90）と Protomaps（#92）。Phase 16 は完了（`style:compat` の残りの警告 28 件は段階案の外として残す、2026-11-04 ユーザー判断）。全体のレビューの R1（セキュリティ、#93）、R2（正しさ、#94）、R3（整理、#95）、R4（文書、#96）。Phase 17（データ形式）は 17.1〜17.7 が終わった（#97〜#105、下の節）。Phase 17 の後の点検（#107〜#113、下の節）。Phase 19 の後：点検（可視域を GDAL と完全一致に #135、上限と整理 #136）、CI の並列化（#137）、速さの比較と改善（#138〜#140、#143）、道路網のつなぎ（`tile` #141、`snap` #144）、GeoJSON の `updateData`（#142、#145、フィールド演算 #146）。
- **次**：Phase 20（3D 第2弾、下の節）の 20.9（3D の計測・見通し・断面）。20.8a・b（太陽の位置と光、影）、20.7a・b（I3S：建物とメッシュ、点群と LEPCC、SLPK）は済んだ。20.1（地球表示のカメラ）、20.2a〜c（地球表示の描画）、20.3（`mbmap/3d` と glTF、meshopt）、20.4a・b（3D Tiles、Draco、i3dm・cmpt、属性とクエリ）、20.5（PLATEAU の example、CesiumJS との比較。GPU の数字は Mac で `npm run cesium -- --gpu`）、20.6（点群：pnts、glTF の点、Draco の点群、LAS）は済んだ。Claude Code on the web で進める（2026-11-08 ユーザー判断）。
  - Web の環境で足りないもの：PLATEAU の 3D Tiles を取りに行く `assets.cms.plateau.reearth.io` と `api.plateauview.mlit.go.jp`（20.4・20.5 で使う。ユーザーが環境の Network access に足す）。このセッションの環境からは公開スタイルのフィクスチャ（`tiles.openfreemap.org`、`build.protomaps.com`、スプライト）が取れず、`style:public` は回らない（GSI のフィクスチャは取れる）。CesiumJS との描画の速さの比較は M2 の GPU で回すので、その段階の報告で「Mac で回すもの」に足す（AGENTS §9）。
- **改名**（2026-11-08 ユーザー判断）：「mb」が Mapbox を思わせるので改名する。3D（Phase 20）が終わったら、新しいリポジトリで文書と CI/CD の整理と一緒にまとめて行う（それまでこのリポジトリでは名前を変えない）。候補は moonmap、moon-rabbit / gyokuto、tsukimi-map（`mbt-map` は MBTiles と紛れる）。rabbita などの MoonBit のフロントエンド向けの入口（mooncakes の MoonBit の API）も考える。
- **Phase 19（解析 第2弾）は完了**：19.1（DE-9IM、#126）、19.2（形の操作、#127）、19.3（分類と統計、#128）、19.4（面と点の集まり、#129）、19.5（可視域と見通し、#130）、19.6（経路探索、#131）、19.7（フィールド演算、#132）、19.8（example の仕上げ、#133）。Phase 18（GIS の Web サービス）は 18.1〜18.7b（#115〜#124）と点検（#125）で完了。
- **Mac で回すもの**（残り。Phase 19 の分は下の節）：
  - `style:public` と `style:compat`（`ofm-planet` と `protomaps` のフィクスチャがまだ Mac にない）、`--labels` などの `render` の変種、`maplibre` の基準の取り直し。
  - 速さ：Phase 17 の読み込みにはベンチがない（`data:node` を足すところから）。17.6c の投影し直しのコストも未計測。点検の性能の候補（`geotiff` の `open` の二度の解析、`Window::copy`、`lzw`、`input_text` など）はそのベンチのあと。
  - 主スレッドの `rafCpuP50` が 11-03 の記録より増えた分（下の節）の切り分け。
- **公開スタイル**（`npm run style:compat`）：Protomaps を足した 9 本すべてが拒まれずに描ける。警告は 16.5 で 321 → 30、16.8 で 27（ズームで変わる `*-translate` に対応）と Protomaps の 1。残りは段階案になかったもの（`symbol-placement` / `text-anchor` / `fill-antialias` の式、線に沿った `text-pitch-alignment` / `text-rotation-alignment`）。
- **開発の場所**：ローカルの Mac（性能ベンチはここだけ）と Claude Code on the web（AGENTS.md「Claude Code on the web」）。
- **入口の大きさ**（予算は VISION §2）：

  | 入口 | 大きさ | 予算 |
  |---|---|---|
  | 表示（メイン） | 157.2KB（地球表示と太陽の位置 1.2KB と影を含む。式の評価 `evaluateExpression` を含む。GeoTIFF のソースは `geotiff-source.js` 0.2KB、画像・動画・canvas のソースは別に `media.js` 2.6KB、カスタムレイヤーは `custom.js` 2.9KB、`toBlob` は `export.js` 0.4KB、TileJSON の取り込みは `tilejson-merge.js` 0.5KB） | 160KB（2026-11-09、ユーザー判断。影のため 155KB から。2026-11-08 に地球表示のため 135KB から。その前は 2026-11-04 に 120KB から） |
  | 表示ワーカー | 85.2KB（地球の細分化を含む。ラベルは別に `worker-labels.js` 9.6KB、PMTiles のタイルは `worker-pmtiles.js` 2.0KB、クエリは `worker-query.js` 0.9KB） | 100KB |
  | GeoJSON ソース | 4.5KB ＋ ワーカー 37.0KB（`clusterProperties` のあるソースは式を持つワーカー 56.5KB） | 5KB ＋ 37KB（57KB。`updateData` の増分のため 2026-11-08 ユーザー判断で 30KB・50KB から） |
  | `mbmap/ui` | 9.0KB（全部入り。属性テーブル単独 2.0KB、フィールド演算 1.1KB） | 10KB（1 つ 2KB、属性テーブルは 2.2KB：2026-11-07 ユーザー判断） |
  | `mbmap/search` | 2.8KB | 5KB |
  | `mbmap/services` | 11.2KB ＋ GML 2.0KB ＋ ワーカー 20.2KB（ArcGIS の `f=json` と `f=pbf`、`services.wasm`） | 12KB ＋ 21KB（2026-11-08 に 20KB から、2026-11-06・11-07、ユーザー判断。18.5 で 10KB から引き上げ） |
  | `mbmap/draw` | 4.9KB（4867 バイト） | 10KB（2026-11-03、ユーザー判断。8KB 以内に収まればなおよい） |
  | `mbmap/geodesic` | 1.1KB ＋ ワーカー 12.0KB | 2KB ＋ 15KB |
  | `mbmap/3d` | 4.9KB ＋ 3D Tiles 9.9KB（`3d-tiles.js`、最初の `tilesLayer` で読み込む。属性の読み出しを含む） ＋ ワーカー 29.9KB（glTF と b3dm・i3dm・cmpt の読み込み、3d.wasm の meshopt と Draco） | 10KB ＋ 10KB ＋ 45KB（2026-11-08 ユーザー判断） |
  | `mbmap/analysis` | 8.3KB（分類と統計 2.3KB を含む） ＋ ワーカー 30.3KB（geometry.wasm 41.7KB、relate.wasm 26.8KB、shapes.wasm 27.9KB、surface.wasm 29.2KB、viewshed.wasm と `analysis-viewshed.js` 10.7KB、route.wasm 16.1KB） | 9KB ＋ 31KB（ワーカーは 2026-11-08 に 30KB から。50KB、30KB、30KB、30KB、12KB、17KB（2026-11-08 に 15KB から）。route.wasm、viewshed.wasm と入口の 9KB（5KB から 7KB を経て）と relate・shapes・surface の wasm は 2026-11-07 ユーザー判断） |
  | `mbmap/data` | 4.7KB ＋ ワーカー 40.6KB（`reprojected` のタイル 1.8KB、`xml.wasm` 26.7KB、GeoTIFF 19.8KB、FlatGeobuf 2.3KB、zip 1.2KB、`.prj` 3.7KB、座標変換 1.1KB ＋ proj.wasm 21.7KB） | 6KB ＋ 41KB（ワーカーは 2026-11-08 に 40KB から。2KB、27KB、20KB、2.5KB、2KB、4KB、1.5KB） |

## Phase 20：3D 第2弾（2026-11-08〜）

範囲・段階・予算の扱いは 2026-11-08 にユーザーが決めた（`AskUserQuestion`）。

- **段階**（1 段階 1 PR、この順）：
  - 20.1：地球表示のカメラ（MapLibre 6.16 の `GlobeTransform` の移植）。
  - 20.2：地球表示の描画。2026-11-08 のユーザー判断で 3 つに分けた：20.2a カメラの配線（スタイルの `projection`、操作・アニメーション、地球上のタイルの覆い方、大気）とラスタ・背景の描画（`raster:golden` に地球の場面）、20.2b ワーカーでのベクトルの細分化（MapLibre の `subdivision.ts`、面・線・円・heatmap、`style:golden` に地球の場面）、20.2c ラベル・クエリ・地形・押し出し・カスタムレイヤー・書き出しを地球に。
  - 20.3：`mbmap/3d` の入口、3D のワーカーと wasm、glTF / glb（`KHR_mesh_quantization`、`KHR_texture_transform`、WebP）、meshopt の移植、glTF モデルの配置。
  - 20.4：3D Tiles 1.0 / 1.1。2026-11-08 のユーザー判断で 2 つに分けた：20.4a（tileset.json、境界、画面上の誤差による詳細度、REPLACE / ADD、外部タイルセット、暗黙のタイリング、glb と b3dm、メルカトルと地球。Draco の移植もここに）、20.4b（i3dm、cmpt、バッチテーブルと `EXT_structural_metadata` / `EXT_mesh_features`、クエリ、地形との重なり）。pnts の描画は 20.6 で。
  - 20.5：PLATEAU の建物を表示する example（専用のページ 1 つ。2026-11-08 のユーザー判断）と CesiumJS との描画・速度の比較。
  - 20.6：点群（3D Tiles の pnts と glTF の点、圧縮なしの LAS）。
  - 20.7：I3S。2026-11-08 のユーザー判断で 2 つに分けた：20.7a（3DObject と IntegratedMesh：node pages、Draco と非圧縮のジオメトリ、JPEG・PNG のテクスチャ、属性とクリック）、20.7b（点群 PCSL：LEPCC の移植、SLPK）。圧縮テクスチャ（KTX2 / Basis、DDS）は読まない。比べるデータは合成と ArcGIS の公開サンプル（`tiles.arcgis.com` を環境に足した）。I3S のコードは遅延読み込みの `3d-i3s.js`（10KB）。
  - 20.8：太陽の位置と光と影（mbmap の拡張として）。2026-11-08 のユーザー判断で 2 つに分けた：20.8a（suncalc の移植とゴールデン、環境光と平行光、時刻の光）、20.8b（影、シャドウマップ。地面・押し出し・3D の層、地球表示にも）。どちらも 3D の層と押し出しに。
  - 20.9：3D の計測・見通し・断面（クリッピング）。
- **決めたこと**：
  - 地球表示は表示（メイン）の入口に入れる（2026-11-08 ユーザー判断：遅延ロードの `globe.js` にすると地図のカメラの処理を差し替え口越しにする大きな改造と core の写しが要るので、メインに入れて予算を 147KB に。20.2a で 149.3KB になったので、20.2b・c の分も含めて 155KB に）。
  - LAZ（COPC）には対応しない（laz-perf 0.0.7 の wasm は gzip 72.6KB）。Draco は当初「対応しない」としたが、PLATEAU の配信 3D Tiles が 2020〜2025 年度のどれも Draco（`KHR_draco_mesh_compression`）だと 20.4 で分かり（当初の調べの誤り）、2026-11-08 のユーザー判断で復号を MoonBit に移植した（draco3d の wasm は gzip 81.4KB ＋ glue 13.1KB）。meshopt も MoonBit に移植した（参照の JS 実装は 472 行、gzip 4.2KB）。
  - 光と影は、Mapbox GL JS v3 とそのスタイル仕様が Mapbox の利用規約のもとにあり（オープンソースでない）、移植もゴールデンもできないので、mbmap の拡張として作る：Mapbox の公開文書のプロパティ名（`lights`、`cast-shadows` など）だけを使い、太陽の位置は suncalc の移植（ゴールデン）、影は解析的な場面（高さ h の箱の影の長さ h / tan(高度)）と CesiumJS との見た目の比較で確かめる。
  - `mbmap/3d` の予算は、入口 10KB ＋ ワーカー 45KB を目安に 20.3 で測ってから決める。
- **比べる相手**（2026-11-08 の調べ）：
  - 地球表示：MapLibre GL JS 6.16.0（BSD-3-Clause）の `src/geo/projection/`（`globe_transform.ts`、`vertical_perspective_transform.ts`、`globe_utils.ts`、カメラの補助、`globe_covering_tiles_details_provider.ts`、細分化の `src/render/subdivision.ts`）。`"globe"` はズーム 11 から 12 で vertical perspective からメルカトルに移る。
  - PLATEAU：配信の 3D Tiles（FY2020〜2023、FME）は 3D Tiles 1.0（b3dm とバッチテーブル）、高さは楕円体高。PLATEAU GIS Converter（MIT）の出力は 3D Tiles 1.1（glb、WebP の地図帳、明示の木、Draco・meshopt なし）。両方を読む。データは CC BY 4.0 などで、出典を付ければ再配布できる。カタログは `api.plateauview.mlit.go.jp/datacatalog/plateau-datasets`、データは `assets.cms.plateau.reearth.io`（東京駅の近くは千代田区 13101 の LOD1・LOD2）。
  - 3D Tiles の選択：loaders.gl 4.5.4 の `@loaders.gl/tiles`（MIT、Node で動く）と 3DTilesRendererJS（Apache-2.0、0.5.4 は新しすぎるので一つ前を固定）。CesiumJS（Apache-2.0）は描画と速度の比較だけ（動的な誤差などで決まった比較ができない）。
  - I3S：`@loaders.gl/i3s` 4.5.4（MIT）。点群（PCSL）は loaders.gl にもほとんどない。
  - 太陽：suncalc（BSD-2-Clause。2.1.2 は新しすぎるので 2.1.1 か 2.0.2 を固定）、CesiumJS の `Simon1994PlanetaryPositions` を二つ目の相手に。
- **20.1 の結果**（地球表示のカメラ）：
  - `globe`（純粋な MoonBit、全バックエンド。まだ `map` からは使わない）：MapLibre の `GlobeTransform`（vertical perspective と、メルカトルと共有するカメラの状態 `TransformHelper`）、地球とメルカトルのカメラの補助（`jumpTo`、`easeTo`、`flyTo`、`cameraForBounds`、操作、慣性）、ハンドラーマネージャーの操作の 1 フレームを、変更のたびに MapLibre と同じく制約をかける 1 つの可変の `Globe` に移した。遷移（`transition`）が 0 より大きい間は地球として、0 では同じ状態の `@core.Transform::exact` で答える。アニメーションは自分の変換を持ち、増える割合で進めると、MapLibre の次のフレームと同じく新しいズームから遷移を取り直すので、メルカトルと地球をまたぐ飛行も同じになる。
  - `core` に足したもの：`Mat4::rotate_y`、制約なしの `Transform::exact`、メルカトルの制約 `mercator_constrain`、箱に合わせる `fit_box`（`camera_for_bounds` はこれを使う）、`Transform::ray_ground` の公開。
  - `npm run globe:golden`（新設）：MapLibre の `createProjectionFromName` の変換をその `Camera` とカメラの補助で動かし、フレームごとにズームから遷移を取り直して比べる。21 の視点（`globe` の z0.5〜14、ピッチ 85° 近くまで、日付変更線、極の近く、ズームとピッチの上限、`maxBounds`、`vertical-perspective`、`mercator`）で 501 の比較（制約、投影と遮蔽、逆投影、地球の行列と射影・近遠面・カメラの位置・地平の面・高度、`getBounds`、`cameraForBounds` 4 種、`easeTo` 6 種と `flyTo` 5 種の各 7 フレーム、操作 7 フレーム、`setLocationAtPoint`、慣性）がすべて許容差（1e-6 px、1e-7°、1e-8 ズーム、相対 1e-6）の中。最大の差は 1.7e-9 px、3.9e-8°、1.3e-9 ズーム。
  - 大きさ：`globe` はまだどの入口にも入らない。表示（メイン）は `fit_box` を分けたぶん 40 バイト増えた（133.8KB のまま）。
- **20.2a の結果**（地球表示の配線、ラスタと背景と大気）：
  - スタイルの `projection`（`mercator`・`globe`・`vertical-perspective`。式は未対応として警告し、メルカトル）と `sky` の `atmosphere-blend`（`sky` がなければ 0、あれば既定 0.8、MapLibre の `Sky.setSky` と同じ）を読む。ファサードに `setProjection` / `getProjection`。
  - `map` は `Globe` を持ち、同じ状態のメルカトルの `@core.Transform::exact` を並べる（地図のほかの部分はこれを読む）。カメラの呼び出し（`jumpTo`、`easeTo`、`flyTo`、`setLimits`、`cameraForBounds`、`getBounds`、`project` / `unproject`）、アニメーション、ドラッグ・ピンチ・ホイール・回転・ダブルクリック・慣性は地球を通る。遷移はフレームごとにズームから取る。
  - `Globe::covering_tiles`（並行のエージェントの移植）：MapLibre の `coveringTiles` と地球の境界の立体（z0・z1 は箱、z2 からは 6 面と極）、可変ズーム、地平の面での切り落とし。`globe:golden` に 7 視点と 125 の比較を足し、タイルの並びまですべて同じ。最初は 256px のタイルの高ズームで 9 タイル違った：MapLibre は逆行列を `mat4.clone`（Float32Array）で写してから視錐台を作るので、同じく Float32 に丸めたら一致した。
  - 描画：シェーダーに `project()` の前置き（MapLibre の `projectTile`：地球の行列、タイルのメルカトルの角と大きさ、地平の面で裏側を切る z、遷移の途中は平面との混合、極の頂点）を入れ、ラスタ・hillshade・color relief・画像・背景の模様をタイルのメッシュ（`@globe.tile_mesh`、z0 で 128、z2 から 32 の分割、北と南の行は極まで）で地球に描く。背景は地球のタイルごと、外の宇宙は透明のまま（コンテキストを `alpha: true` に）。大気は MapLibre の atmosphere シェーダーの写し。ラスタは傾き 20° を超えると異方性フィルタ（MapLibre の `anisotropicFilterPitch`、メルカトルでも同じ）。
  - 地球の間は、面・線・円・記号・heatmap・押し出しのレイヤーと地形・ラベル・クエリ・書き出しはまだ描かない（20.2b・c）。
  - フィクスチャ：国土地理院の標準地図の z0〜z3 の全タイル `gsi-std-world`（85 タイル、3.2MB、マニフェストで照合）。
  - `npm run raster:golden` に地球の場面：`globe` で 6 視点（z0.3、z1、z2.3 の傾き 40°、北米の z5 の傾き 60°、z11.5 の遷移の途中、z12.5）、`sky` あり（大気）と `vertical-perspective` を各 2 視点。10 場面すべて MapLibre と画素で同じ（平均 0、99% 点 0）。地球で要求するタイルの URL も 4 視点で同じ。
  - pack test に `globe`（`bench/npm/pages/globe/`）：地球の外が透明、`project` / `unproject` / `getBounds`、ドラッグで回り、ホイールで寄り、z13 への飛行がメルカトルで終わり、`setProjection(null)` で平らに戻る。
  - example の 3 通りへの地球表示の切り替えは、ベクトルのレイヤーも地球に載る 20.2c で足す。
  - 大きさ：表示（メイン）133.9 → 149.3KB（予算 155KB）。`globe` の関数が多く薄く広い（覆い方 約 5KB、カメラ 約 8KB、シェーダー・大気・配線 約 2KB）。
- **20.2b の結果**（面・線・円・heatmap を地球に）：
  - `tess` に MapLibre の `subdivision.ts` の移植 `Subdivider`（並行のエージェント）：面を格子で切る走査線の三角形化、輪郭の線、極の帽子、z0 の経度の外の切り落とし、`subdivideVertexLine`、地球の粒度（面 128 から 2、線 512 から 0、円 3）。`npm run subdivision:golden`（新設）で GSI の面 300 万件・線 350 万件・乱数の面と線をすべて MapLibre と同じ（頂点・三角形・輪郭の線まで）。
  - 表示ワーカー：タイルの依頼に `globe` を載せ、地球のときは幾何を `TILE_EXTENT` に揃えて（MapLibre の `loadGeometry` と同じ丸め）面を `subdividePolygon`、線を `subdivideVertexLine` で切る。heatmap と `circle-pitch-alignment: map` の円は四角形を 3 × 3 に（MapLibre の円のバケット）。投影が変わったスタイルはベクトルのタイルを読み直す。
  - シェーダー：面・輪郭・模様・線（5 種）・円・heatmap に `project()`。線は `lineThickness`（極に向けて太る）と MapLibre の `getPixelScale` で幅を補正し、地球では gamma scale を投影した長さから取る。円（地図に沿うもの）と heatmap の核は球面の上で回す（`globeRotateVector`）。
  - `npm run style:golden` に地球の場面 6 つ（面・穴・日付変更線・北極までの面・線・点、傾き 45°、heatmap、地図に沿った円、破線・グラデーション・輪郭）。すべて MapLibre と画素で同じ（平均 0〜0.01、99% 点 0）。
  - 地球の間もまだ描かないもの：記号（ラベル・アイコン）と押し出し。`*-translate` は地球では効かない。20.2c で。
  - 大きさ：表示（メイン）149.3 → 149.8KB、表示ワーカー 80.5 → 84.8KB（細分化の移植）。
- **20.2c の結果**（ラベル・押し出し・平行移動・クエリ・地形・カスタムレイヤー・書き出しを地球に、1 つの PR：2026-11-08 ユーザー判断）：
  - 押し出し：壁は細分化した輪郭から、屋根は面として切る（`ExtrusionTessellator` に `subdivide`）。高さは球の法線に沿って上げ（`project3d`）、光は MapLibre の地球の光の向き（`transformLightDirection`）。押し出しの前に地球の面を深度だけに書く（MapLibre の `_renderTilesDepthBuffer`）。`style:golden` に `globe-extrusions`（東京近くの 25 棟、z6.5、傾き 60°）。packed の高さは 6553.5 m までなので場面の高さは 1500〜6000 m。
  - `*-translate`：球の上の点を動かす（`GlobeTile.translate`）。`style:golden` に `globe-translate` と `globe-map-circles`。地球の場面 8 つがすべて MapLibre と同じ（平均 0.01 以下）。
  - クエリ：依頼にタイルの地球の行列を載せ、ワーカーで球を通して画面に投影する。押し出しは地球では当たらない（MapLibre と同じ）。`query:golden` に地球の視点 3 つ（628 の比較で違うのは 1 つ：日付変更線の向こうの世界の写し。MapLibre の `getWrap` を真似ると 9 つに増えたので戻し、既知の差として数えない）。
  - 地形：地形の格子を `project3d` で球に載せ（高さはメートルで）、霧はなし（MapLibre と同じ）。タイルは地球の覆い方で選ぶ。地球では中心を地形の高さに立てない（MapLibre は立てる。未対応）。
  - カスタムレイヤー：地球のあいだは MapLibre と同じ options（`shaderData` は地球の prelude、`modelViewProjectionMatrix` と `projectionMatrix` は地球の、`defaultProjectionData` と `getProjectionData` は地球の行列とメルカトルの fallback・地平の面・遷移）。pack test の `globe` ページで地球の prelude を通した四角形が描けることを確かめる。`custom.js` は 1.8 → 2.9KB（予算 3KB）。
  - 書き出し：地球の行列と大気の光線も分割の窓を通す。画像は不透明に固定せずストレートアルファに（地球の周りの宇宙は透明、キャンバスと同じ）。`export:golden` に `globe`（ラスタの世界、大気）と `globe-terrain`（富士山、z11）。地球では f32 の球面の座標が窓の行列で 1/100 px ほど動くので、分割の比較の許容を平均 0.05・99% 点 1 に。
  - example：3 通りのショーケースに「地球儀」の切り替え（ズーム 2 まで引く）。pack test で投影と中心を確かめる。
  - ラベル・アイコン（並行のエージェント）：配置は地球のあいだ MapLibre と同じく純粋な地球の投影で（`globe/symbols.mbt`：`projectTileCoordinates` と地平の面での隠れ、`getPitchedTextCorrection`、`getCircleRadiusCorrection`、`getWrap`）、地平の向こうの点のラベルは置かない、線のラベルは隠れていない最長の区間を使う。シェーダーは記号とアイコンも `proj` の prelude を通す。`labels:golden` に地球の 11 場面（点、アイコン、可変アンカー、線に沿った文字、傾き 70°、遷移中のズーム 11.3・11.5）、全 67 場面が同じ。`style:golden` に地球の記号の 4 場面（許容の中）。
  - ついでに直したもの（メルカトルでも）：ソースの maxzoom より浅いタイルでもラベルを overscale として配置していたのを、MapLibre の `overscaledZ` と同じく maxzoom を超えたときだけに。
  - MapLibre と違うところ：記号の `*-translate` は地球では効かない。遷移中（0 < t < 1）の可変アンカーのずらしはシェーダーで混ぜたアンカーから（MapLibre は CPU で地球の投影から。配置は同じ）。地球の画面に沿う文字の深度はアンカーの z のまま（MapLibre は 0）。地図に沿う SDF アイコンの縁の gamma がメルカトルでも少し違う（平らな場面で平均 0.078、既存の差）。
  - 大きさ：表示（メイン）149.8 → 151.7KB（ラベル、押し出し、地形、クエリ、書き出しを地球に）、表示ワーカー 84.8 → 85.2KB（押し出しの細分化、クエリの地球）。
- **20.3 の結果**（`mbmap/3d` の入口、glTF / glb と meshopt、モデルの配置）。描き方・比べる相手・配置の API は 2026-11-08 のユーザー判断（`AskUserQuestion`）：カスタムレイヤー経由（地図本体は 3D の入口を読み込まない）、loaders.gl と meshoptimizer と比べる、関数 API と GeoJSON の点：
  - `meshopt`（純粋な MoonBit、並行のエージェント）：meshoptimizer 1.3.0 の復号（頂点コーデックの版 0 と 1、インデックスの三角形と列、フィルター 5 種）の移植。`npm run meshopt:golden`（新設）で npm の `MeshoptDecoder.decodeGltfBuffer` と 12040 件すべてバイト単位で同じ（js と wasm-gc の両方）。Node の復号器は SIMD 版なので、壊れた入力の扱いはそれに合わせた。指数フィルターで仮数 0・指数 -128 の NaN は CPU で違う（x86 は 0xFFC00000）ので、その場合だけ NaN 同士を同じと数える。
  - 3D ワーカー（`model_worker/js/worker.mjs`、wasm は `model_worker` の 3d.wasm）：glTF を取って `npm/src/model/gltf.ts` で読み、meshopt で圧縮されたバッファビューを wasm で解き、画像を ImageBitmap に。`KHR_mesh_quantization`（量子化のまま GPU へ）、`KHR_texture_transform`、`EXT_texture_webp`、`KHR_materials_unlit`、疎なアクセサー、インターリーブ、.gltf の外部ファイル。上限（JSON 64MB、出力 512MB、ノードの深さ 64）と、それ以外の必須拡張（Draco など）は断る。
  - `npm run model:golden`（新設）：gltf-transform 4.5.1 で書いた 8 つのモデル（素のもの、WebP とテクスチャ変換と unlit、9 万頂点、量子化、meshopt の 2 方式と `KHR_meshopt_compression`、.gltf と .bin と画像）を Chromium の `loadModel` で読み、@loaders.gl/gltf 4.5.4 の属性・インデックス・材質・テクスチャ変換と gltf-transform のワールド行列に比べてすべて同じ。壊れたファイル 8 つ（途中で切れたもの、チャンクの長さ、JSON でないもの、glTF 1.0、未対応の必須拡張、ノードの循環、範囲外のアクセサー、壊した meshopt）はすべてエラーで断る。loaders.gl は Node では `EXT_texture_webp` を必須にしたファイルを断るので、比べる側だけ必須から外す。
  - `modelLayer`：GeoJSON の点ごとにモデルを置くカスタムレイヤー（`renderingMode: "3d"`）。`scale` / `rotation` / `translation`（Mapbox の `model-*` の名前、定数か `["get", key]`）は東・北・上のメートル。インスタンスごとに f64 でメルカトルの行列（地球では MapLibre の fallback）と単位球の行列を作り、シェーダーで遷移の割合で混ぜる（MapLibre の `interpolateProjectionFor3D`）。地球の裏のインスタンスは地平の面で外す。光は Mapbox の既定の向きの Lambert、法線がなければ画面の微分から、面は両面、半透明は深度を書かない 2 つ目のパス（並べ替えなし）。
  - pack test に `model` ページ（量子化と meshopt の箱、回転、地球）。3 通りのショーケースに時計塔のモデル（`examples/shared/tower.glb`、4.3KB、`bench/model/example-model.mjs` で作る）。
  - 大きさ：`mbmap/3d` 4.3KB、3D ワーカー 7.4KB（3d.wasm を含む）。予算は 10KB ＋ 45KB（2026-11-08 ユーザー判断：20.4〜20.7 の 3D Tiles・点群・I3S も同じ入口とワーカーに入るので目安のまま。各段階で測り、超えそうなら相談）。表示（メイン）は変わらない。
  - 依存（bench の devDependencies、すべて MIT、install スクリプトなし、2 週間以上前の版）：meshoptimizer 1.3.0、@loaders.gl/gltf と @loaders.gl/core 4.5.4、@gltf-transform/core・extensions・functions 4.5.1。
  - まだないもの：アニメーション、スキン、モーフ、カメラ、`EXT_mesh_gpu_instancing`、PBR の金属・粗さ・法線・発光・遮蔽のテクスチャ、地形の上への配置、クエリ（20.4 以降で 3D Tiles と一緒に）。
- **20.4a の結果**（3D Tiles の選択と描画、Draco）。比べる相手（loaders.gl の Tileset3D）、データ（PLATEAU と合成）、分け方は 2026-11-08 のユーザー判断：
  - `npm/src/tiles/`（import なし）：loaders.gl 4.5.4 が math.gl 4.1 で行う計算（WGS 84 の楕円体、東北上の座標系、`region` から作る向き付きの箱、球、視錐台の平面マスク）、タイル木（外部タイルセットはそれを指すタイルの下に）、`TilesetTraverser` と `Tileset3DTraverser` の選択（画面上の誤差、REPLACE は子がすべて読めるまで親を描く、ADD、視点の要求領域）、暗黙のタイリング（サブツリーのファイル、四分木と八分木。loaders.gl と同じく先に全部広げる。箱は仕様どおり分ける：loaders.gl は分けない）、b3dm（フィーチャーテーブル、RTC_CENTER、バッチテーブル）と glTF の中身（CESIUM_RTC）。
  - `npm run tiles:golden`（新設）：loaders.gl 自身の `Tileset3D` と同じフレーム状態（比較用の 60° のカメラ）で、読み込みがなくなるまで選択を繰り返し、PLATEAU（東京駅まわり）と合成のタイルセット 4 つ（変換つきの箱、ADD の球、空のタイル、視点の要求領域、外部タイルセット、暗黙の四分木と八分木）の 5 視点、計 25 の場面で選ばれるタイルがすべて同じ。b3dm の表は 68 ＋ 5 ファイルすべて同じ。
  - `draco`（並行のエージェント）：Draco 1.5.7 の復号器の移植（ビットストリーム 2.0〜2.2、edgebreaker（standard、predictive、valence）と sequential、属性の復号、予測（difference、parallelogram 系、tex-coords portable、geometric normal）と変換、rANS）。`npm run draco:golden`（新設）で draco3d 1.5.7 と 11668 件（既定）／48280 件（多め）すべて同じ（js と wasm-gc。符号化器が断った 72 件を除く）。PLATEAU の 68 タイルすべてと Draco 自身のテストファイル 8 つも同じ。壊した入力は draco3d が断るものをすべて断る。2.0 より古いビットストリームと点群は対象外。
  - `tilesLayer`：地図のカメラ（カスタムレイヤーの行列。地球では遷移が半分を超えたら単位球のもの）から ECEF の視錐台を作り、選んだタイルの中身を 3D ワーカー（`tile`、同時に 6 つ、近い順）で読み、タイルの境界の中心の東北上のメートルでモデルの描画（`npm/src/model/draw.ts`、20.3 と共通）に渡す。`height` で楕円体高を地図の地面に合わせる（PLATEAU は東京駅で -36.7 m）。読み込んだ中身は既定 256 まで。
  - PLATEAU のフィクスチャ（並行のエージェント、`plateau-chiyoda`）：2025 年度 千代田区 LOD2 テクスチャなしの tileset.json はそのまま、東京駅まわりの箱にかかるタイルと祖先、その兄弟だけ（b3dm 68、28MB）。兄弟を入れないと REPLACE の根が置き換わらない。出典は PLATEAU のサイトポリシー（PDL1.0、CC BY 4.0 互換）の書き方に合わせ、抜き出したことも書いた。
  - pack test に `tiles` ページ（合成の b3dm：近くで 4 タイル、遠くで根、地球。PLATEAU：東京駅で 24 タイル）。
  - 大きさ：`mbmap/3d` は 10.6KB になり予算の 10KB を超えたので、ユーザー判断（2026-11-08）で 3D Tiles を `3d-tiles.js` に分けて最初の `tilesLayer` で読む（入口 4.6KB、`3d-tiles.js` 6.9KB / 10KB）。3D ワーカーは Draco で 7.4 → 26.7KB（45KB）。
  - 依存（bench の devDependencies）：@loaders.gl/tiles と @loaders.gl/3d-tiles 4.5.4（MIT）、draco3d 1.5.7（Apache-2.0、install スクリプトなし）。@loaders.gl/compression が引く fflate 0.7.4 に中程度の脆弱性（壊れた ZIP64 で無限ループ、GHSA-px8p-9vwx-vf98）があるので、`overrides` で 0.8.3 に固定（`npm audit` 0 件）。
  - まだないもの（20.4b 以降）：i3dm、cmpt、pnts（20.6）、バッチテーブルとメタデータの利用、クエリ、地形の上への配置、半透明の並べ替え、画面上の誤差の動的な調整。
- **20.4b の結果**（i3dm と cmpt、属性、クエリ、地形との重なり。並行のエージェント 2 本と本線）：
  - i3dm と cmpt（`content.ts`、エージェント）：i3dm は各インスタンスの行列を loaders.gl と同じ作り方で（RTC を含める）、cmpt は中のタイルを平らにして（pnts は飛ばす）。`npm run tiles:contents`（新設）で loaders.gl と 42 件すべて同じ（インスタンスの行列とバッチ ID 13、loaders.gl が向きを読まない NORMAL_UP/RIGHT と oct 符号化の法線は Cesium の作り方と比べて 2、ENU と RTC の組み合わせ 1、cmpt 3、壊したファイルを断る 23）。loaders.gl と違うところ：明示の法線と oct の法線を使う（loaders.gl は使わない・投げる）、ENU は RTC を足した位置で取る、入れ子の cmpt をその byteLength で進む。
  - 属性（`properties.ts`、`gltf.ts` の `featureIds` と `metadata`、エージェント）：b3dm のバッチテーブル（JSON とバイナリ）と 3D Tiles 1.1 の `EXT_structural_metadata` のプロパティテーブル（すべての型、配列、文字列、真偽、列挙、offset/scale/normalized、noData/default）。`npm run tiles:properties`（新設）で PLATEAU 68 を含む b3dm 71 の 47,784 値が `Tile3DBatchTable` と同じ、プロパティテーブル 130 件が書いた値と同じ（loaders.gl が仕様から外れるところ：可変長配列のオフセットをバイトで読む、ベクトルの配列、真偽と文字列の配列を読まない、64 ビットのオフセット、値の変換をしない、などは書いた値と比べる）。壊した入力 23 件はすべて断る。
  - クエリ（本線）：`tilesLayer.queryFeature({x, y})`。選んだタイルの部分ごとの番号と地物の番号（`_BATCHID`、`_FEATURE_ID_0`、i3dm のインスタンスのバッチ ID）を画面外の RGBA8 に描いて、次のフレームのあとに 1 画素を読む。PLATEAU で東京駅をクリックすると `city_code` 13101 や `gml_id` などの建物の属性が返る。
  - i3dm の描画（本線）：インスタンスごとに 1 回描く（数が多いときは 20.6 以降で instancing に）。pack test のタイルセットに b3dm と i3dm の木 12 本の cmpt を足し、木が立って描けクリックで `kind: "tree"` が返ることを確かめる。
  - 地形：地形を入れても深度を共有して建物が地面に立つ（誇張 1 のとき。誇張が 1 でないと高さがずれる）。
  - 大きさ：`3d-tiles.js` 6.9 → 9.9KB（予算 10KB。次に足すときは相談する）、3D ワーカー 26.7 → 29.9KB（45KB）。
  - まだないもの：pnts（20.6）、`3DTILES_batch_table_hierarchy`、地物 ID のテクスチャとプロパティテクスチャ、`EXT_instance_features`、暗黙の地物 ID でのクリック、地形の誇張への追従。
- **20.5：PLATEAU の example**（2026-11-08 のユーザー判断：3 通りの見本ではなく専用のページを 1 つ、PLATEAU を出すあいだは地図の押し出しの建物を隠す）：`examples/plateau/` は千代田区の LOD2（2025 年度、テクスチャなし）を PLATEAU の配信元（`assets.cms.plateau.reearth.io`、CORS は `*`）から直接読み、`tilesLayer({ height: -36.7 })` で国土地理院のベクトルタイルに重ねる。クリックで `queryFeature` の属性（名称、用途、計測高さ、階数、耐火構造、用途地域、LOD、建物 ID、浸水ランク、すべての属性）を出す。チェックで地図の押し出しの建物（`building-3d`）と入れ替え、東京駅・丸の内・大手町・皇居外苑へ `flyTo`。出典は PLATEAU のサイトポリシーの書き方。`?local=1` はフィクスチャ。pack test の `plateau`（フィクスチャで 33 タイル、東京駅のクリックで「13101-bldg-」の建物 ID と用途、切り替えと戻し。CI ではフィクスチャがないので読めないと出ることだけ）。配信元から読んでも東京駅まわりで 72 タイルを描けた。
- **20.5：CesiumJS との比較**（並行のエージェント。比べる項目は 2026-11-08 のユーザー判断：選ぶタイル、読むバイト、落ち着くまでの時間、画面の見比べ、配る大きさ、フレームの CPU）：
  - `npm run cesium`（新設、`bench/cesium/`）：PLATEAU の東京駅まわり（`plateau-chiyoda`）を mbmap/3d の `tilesLayer`（`height: -36.7`、白い背景だけのスタイル）と CesiumJS 1.146.0（`CesiumWidget`、Ion・画像・地形・空・霧なし、白い楕円体、`maximumScreenSpaceError: 8`、動的・foveated な誤差なし、`skipLevelOfDetail: false`、`cullRequestsWhileMoving: false`、タイルセットを中心の法線に沿って 36.7 m 下げる `modelMatrix`、光は mbmap と同じ向きの `DirectionalLight`）で、800 × 600、dpr 1 の Chromium に描く。カメラは MapLibre のもの（縦の画角 36.87°、中心まで 1.5 画面高を中心の緯度のメートルに）を Cesium の `lookAt`（heading = bearing、pitch = pitch − 90°、中心の 0 m のまわり）にし、`frustum.fov` は横の画角に直す。画面の見比べで同じ建物が同じ所に来る。127.0.0.1 の外への要求があれば失敗にする（どちらもなし）。
  - 結果（`bench/results/cesium.json`、**SwiftShader** の Chromium 156、3 回の中央値。フレームの数字は M2 の GPU（`-- --gpu`）で取り直すのが本当）：

    | 視点 | 選んだタイル mbmap / Cesium（共通） | b3dm の要求 | 読んだ MB | 落ち着くまで ms | 回転 120 フレームの CPU p50 / p95 ms |
    | --- | --- | --- | --- | --- | --- |
    | z17、傾き 50°、方位 -20° | 24 / 23（22） | 53 / 50 | 21.7 / 21.0 | 917 / 4043 | 2.27 / 3.85 ・ 2.76 / 5.50 |
    | z16、真上 | 27 / 27（27） | 49 / 49 | 20.5 / 20.5 | 892 / 4119 | 2.34 / 4.34 ・ 2.02 / 2.94 |
    | z18、傾き 60°、方位 30° | 14 / 17（12） | 47 / 46 | 19.1 / 19.1 | 800 / 3713 | 2.35 / 4.28 ・ 2.65 / 5.20 |

  - 配る大きさ（この場面で読んだ .js / .wasm の gzip）：mbmap 284.5KB（`index.js` 151.7、`mbmap.wasm` 80.3、`3d.wasm` 21.5、`3d-tiles.js` 9.9、`3d-worker.js` 8.4、`worker.js` 4.9、`3d.js` 4.9、`custom.js` 2.9）、CesiumJS 1870.7KB（ワーカーを抱えた `Cesium.js` 1782.2、`draco_decoder.wasm` 88.5）＋ 資産 136.3KB（`approximateTerrainHeights.json` など）。
  - 違い：Cesium は PBR と環境光で青みがかった陰影、mbmap は Lambert の灰色。z18 では Cesium が深く選び、フィクスチャにないタイルを 8 つ求める（フィクスチャは loaders.gl の 60° のカメラで選んだもの）。mbmap と loaders.gl は画面上の誤差の分母を 1.15（60° の画角）に固定し、Cesium は 2 tan(縦の画角 / 2)（36.87° で 0.667）を使うため。
  - 依存（bench の devDependency）：cesium 1.146.0（Apache-2.0、2026-10-01。1.147.0 は 2 週間たっていない）。その依存の `@cesium/engine` 26.5.0・`@cesium/widgets` 16.3.1・`@cesium/core` 0.1.1・pako 3.0.3 が新しすぎるので `overrides` で 26.4.0・16.3.0・0.1.0・3.0.2 に固定。install スクリプトなし（cesium 自身の `prepare` は npm のレジストリからの導入では走らない）、`npm audit` 0 件。比べるのは配布済みの `Build/Cesium` だけ。
  - Mac で回すもの：`npm run cesium -- --gpu`（フレームの CPU と落ち着くまでの時間）。
- **20.6：点群**（2026-11-08 のユーザー判断：1 つの PR で、点群の Draco の復号も移植、LAS は `mbmap/3d` の点群の層、`3d-tiles.js` は超えたら 12KB に。超えなかった）：
  - pnts（本線、`content.ts`）：1 つの POINTS の primitive（+Z が上）。POSITION と POSITION_QUANTIZED（体積のオフセットは f64 の RTC に寄せる）、RGBA・RGB・RGB565、NORMAL と NORMAL_OCT16P、CONSTANT_RGBA（材質の色）、BATCH_ID、またはバッチテーブルが点ごと（`_BATCHID` に点の番号）、`3DTILES_draco_point_compression`（feature table の意味と、バッチテーブルの Draco の属性も）。cmpt の中の pnts も描く（これまでは飛ばしていた）。glTF の点（mode 0）も描き、Draco の点の primitive は索引なしで描く。点は丸く、`pointSize` CSS ピクセル（既定 2）、法線がなければ光を当てない。クリックで点の属性が返る。
  - `npm run tiles:contents`：52 件すべて同じ（pnts 4 件と cmpt の pnts、壊した pnts 6 件を足した）。loaders.gl と違うところ：RGB565 は Cesium と同じく 255 倍に広げる（loaders.gl はビットをずらすだけ）、NORMAL_OCT16P は Cesium と同じく 255 の範囲で読む、BATCH_ID のある pnts は loaders.gl がバッチテーブルの `dimensions` から色を取ろうとして落ちるので、BATCH_ID とバッチテーブルは書いた値と比べる。
  - Draco の点群（並行のエージェント、`draco/kd_tree.mbt`・`point_cloud.mbt`）：Draco 1.5.7 の逐次と kd-tree の点群の復号（`DynamicIntegerPointsKdTreeDecoder` の 0〜6、`KdTreeAttributesDecoder`、ビットストリーム 2.3 未満の古い整数と浮動小数の kd-tree）。`@draco.decode` がヘッダーでメッシュか点群かを選ぶ。`MAX_KD_DIMENSIONS`、kd-tree の仕事量の上限（ノード × 次元 ≤ 2^30、Draco にはない）。`npm run draco:golden`：12515 件で 0 differ（点群 109 件、古い枠組み 75 件、Draco の試験ファイル 3 件、壊したもの）。
  - LAS（並行のエージェント、`npm/src/model/las.ts`、3D ワーカーの `las`）：LAS 1.0〜1.4、点の形式 0〜10、座標系は GeoTIFF のキーか WKT、`crs` で上書き（EPSG か PROJ 文字列）、proj.wasm で経緯度に。LAZ は断る。`npm run las:golden`（新設）：@loaders.gl/las 4.5.4 と 348 件、PDAL 2.8.0 の試験ファイル 6 つ（sha256 で固定）で 0 differ、3D ワーカーの `las` は proj4js と 5 mm 以内（最大 0.5 mm）。依存：@loaders.gl/las 4.5.4（MIT、install スクリプトなし、laz-perf 0.0.6 は `prepare` だけでレジストリからの導入では走らない）、`npm audit` 0 件。
  - `pointCloudLayer`（本線）：1 つの POINTS のメッシュをモデルのプログラムで描く。色は RGB・高さ・強度・ASPRS の分類（`setColor`）、`bounds` と `counts`。
  - pack test：`tiles` に pnts の市松模様（点ごとの `kind`）、glTF の点の輪、Draco の pnts の四角（バッチの `height` も Draco）を足し、色とクリックを確かめる。`pointcloud`（新設）は合成の LAS（EPSG:6677、47010 点）を読み、東京駅のまわりに来ること、分類での色替え、`crs` の手書きと間引き、無いファイルで `ready` が失敗することを確かめる。
  - 大きさ：`3d.js` 4.9 → 6.1KB（10KB）、`3d-tiles.js` 9.9KB のまま（10KB）、3D ワーカー 29.9 → 38.0KB（45KB。Draco の点群 +3.8、LAS と座標変換 +3.3）。proj.wasm と prjwkt.js は点群で初めて読む。
  - まだないもの：LAZ・COPC、点の大きさを距離で変える（attenuation）・EDL、点群のクリック（LAS）、多数の点の詳細度（LAS は間引きだけ）、高さの単位と鉛直の座標系。
- **20.7a：I3S の建物とメッシュ**：
  - 選択（本線、`npm/src/i3s/scene.ts`）：レイヤー（SceneServer の `…/layers/0`、またはファイルに書き出した `….json` とその横の資源）、node pages は走査が子を求めたときに読む（`Traversal.expand`）。ノードはタイル（OBB は loaders.gl の `createBox` と同じく四元数で各軸を回す、`mbs` の半径は OBB の外接球、`maxScreenThresholdSQ` は直径に直す）。詳細度は loaders.gl の `getLodStatus` / `getProjectedRadius` の移植で、フレームの `view`（元の行列）から deck.gl の `viewport.project` と同じく画面に投影する。3D Tiles の描画エンジンを `TileSource`（根、走査、中身の読み込み、子の読み足し）で共有し、`3d-i3s.js` は `3d-tiles.js` を読み込んで使う。
  - `npm run i3s:golden`（新設）：Esri のサンフランシスコの建物のサンプル（`i3s-sf-pages`、レイヤーと node pages 780 枚、27MB、sha256 で固定）で、loaders.gl の `Tileset3D`（@loaders.gl/i3s 4.5.4）と同じフレームで node pages を読み、中身は読み込み済みにして、選ぶノードが 5 視点すべて同じ。
  - 中身（並行のエージェント、`npm/src/i3s/content.ts`、3D ワーカーの `i3s`）：Draco のバッファを優先（loaders.gl と同じ）、なければ非圧縮。位置はノードの中心からの度とメートルを math.gl と同じ演算で ECEF にし、中心の東・北・上の f32 メートルに。法線（earth-centered は ENU に回す）、uv、色、地物の番号（`_BATCHID`）、テクスチャのアトラスの `_UV_REGION`（シェーダーで領域の中に繰り返す）。属性は主スレッドで読み（`readI3sAttribute`）、地物の行は OBJECTID で探す（loaders.gl と同じ）。WGS 84 だけ（loaders.gl も同じ）。`npm run i3s:contents`（新設）：Esri の公開サンプル（SanFrancisco_Bldgs 3DObject 36 バッファ、Frankfurt2017_vi3s_18 IntegratedMesh 12 バッファ）と合成で 0 differ、壊したもの 18 件を断る。位置は loaders.gl の ECEF を同じ枠に取って f32 にしたものとビットまで同じ。`geo.ts` の `toCartesian` は math.gl と最後の 1 ビット違うことがあるので、中身は math.gl と同じ `cartesian()` を使う。
  - `i3sLayer`（本線）：クリックで属性（OBJECTID、名前など）。公開サンプルのサンフランシスコをそのまま描け、アトラスのテクスチャも出る。
  - pack test の `i3s`（新設）：合成のレイヤー（東京駅のまわりの 12 棟、根と子 4 つ、Draco と非圧縮、PNG のアトラス）が近くで子 4 つ、遠くで根になり、色の建物とテクスチャの建物のクリックで属性が返る。
  - 依存：@loaders.gl/i3s 4.5.4（bench の devDependency、MIT、install スクリプトなし、`npm audit` 0 件）。公開サンプルのデータは比べるためだけに取り、コミットしない（Esri の利用条件。ライセンスの欄は www.arcgis.com がこの環境から読めず未確認）。
  - 大きさ：`3d-tiles.js` 9.9 → 10.1KB（2026-11-08 のユーザー判断で予算を 12KB に）、`3d-i3s.js` 6.6KB（10KB）、`3d.js` 6.2KB（10KB）、3D ワーカー 38.0 → 41.0KB（45KB）。
  - まだないもの：DDS・KTX2 のテクスチャ、I3S 1.6 以前（node pages なし）、WGS 84 以外、`vertex-reference-frame` の法線、点群（20.7b）、SLPK（20.7b）。
- **20.7b：I3S の点群と SLPK**（2026-11-08 のユーザー判断：LEPCC は 3d.wasm に入れて 3D ワーカーの予算を 45 → 50KB、SLPK は範囲リクエストで部分読み、点群の比較は Esri の LEPCC の C++ 実装）：
  - 点群（本線、`i3s/scene.ts`・`3d-i3s.ts`、3D ワーカーの `pcsl`）：PointCloud レイヤーの node pages（`store.index`、`resourceId`・`firstChild`・`childCount`）、詳細度は仕様の `density-threshold`（点の面積密度 `vertexCount / lodThreshold` を画面に投影した 1 平方ピクセルあたりの点が `POINT_DENSITY` 0.5 を下回る間は子へ）。xyz は絶対座標（経緯度と高さ）で、ノードの中心の東・北・上の f32 メートルに。色は RGB・分類・強度・高さ（`pointCloudLayer` と共有の `model/cloud.ts`、高さは根の箱の範囲で）。
  - LEPCC（並行のエージェント、`lepcc/`）：Esri の lepcc（commit 63a30e2、Apache-2.0）の xyz・rgb・intensity の復号を移植（Fletcher-32、BitStuffer2、カラーマップ、拡大）。RGB の Huffman と FlagBytes は Esri の既定のビルドにもないので移植しない。`npm run lepcc:golden`（新設）：Esri の C++ を g++ でビルドし、その符号化器で作った 2237 件を js と wasm-gc でビット一致（0 differ）。壊したものでは C++ が範囲外を読み書きする（AddressSanitizer で 263 件）・点を書き残す（27 件）ところも、移植は断る。
  - SLPK（並行のエージェント、`i3s/slpk.ts`、`3d-slpk.js`）：末尾 128KB の範囲リクエストで中央ディレクトリ（zip64 も）を読み、入らなければ Esri のハッシュ表、なければディレクトリ全体。範囲を断られたら（200、416）全体を一度だけ読む。各エントリは範囲で取り、gzip を解く。`npm run i3s:slpk`（新設）：合成とサンフランシスコのサンプル（node pages 780 枚を含む 11.8MB）を 4 通りに詰め、元のファイルと loaders.gl の `parseSLPKArchive` に 0 differ、壊したもの 12 件を断る。開いて最初のノードページまでの読み込みはファイルの約 5%。開発用サーバー（`bench/lib/serve.mjs`）は接尾の範囲（`bytes=-n`）に答えるようにした。
  - pack test の `i3s`：合成の点群レイヤー（LEPCC、根 5000 点と子 4 つ各 1 万点）が近くで子 4 つ、遠くで根になり、合成の建物を SLPK に詰めたものが同じノードと属性を返す。
  - 大きさ：3D ワーカー 41.0 → 43.8KB（50KB）、`3d-i3s.js` 7.9KB（10KB）、`3d-slpk.js` 4.5KB（新しい行、6KB）、`3d.js` 6.4KB。
  - まだないもの：PCSL のクリック（点の属性）、統計（`statistics`）、WGS 84 以外の点群、RGB の Huffman、DDS・KTX2、SLPK の CRC の検査。
- **20.8a：太陽の位置と光**（2026-11-08 のユーザー判断：20.8 を 2 つに分け、20.8a は太陽の位置と光、20.8b は影。光と影は 3D の層と押し出しの両方に。suncalc は 2.1.1 に固定。表示（メイン）は要れば 160KB まで）：
  - 太陽（並行のエージェント、`npm/src/sun.ts`、import なし）：suncalc 2.1.1 の `getPosition` の移植 `sunPosition`（度、方位は北から時計回り）、東・北・上の向き `sunDirection`、時刻の光 `timeOfDayLights`（夜・薄明・昼の 3 つの点の間を smoothstep で。高度が負のあいだ方向は 90° に留める）。`npm run sun:golden`（新設）：1900〜2100 年の日時と場所（極、日付変更線を含む）28944 件で suncalc と全部同じ（`Object.is`）、CesiumJS 1.146.0 の `Simon1994PlanetaryPositions`（ICRF から地球固定へ、東・北・上へ）とは 1975〜2050 年で最大 0.017°（許容 0.05°）。
  - 光（本線）：スタイルの `lights`（mbmap の拡張、Mapbox の公開文書の名前：`ambient` と `directional`、`color`・`intensity`、`direction` [方位, 天頂からの角]）を style が読み（ほかの種類は Unsupported として報告して外す）、`setLights` / `getLights` で変える。押し出しは `lights` があれば MapLibre の光の代わりに `色 × (環境光 + 太陽 × ランバート)`（模様の押し出しも）。カスタムレイヤーの数の末尾に環境光・太陽の色と向きを足し（`renderInput` の `lights`）、`modelLayer`・`tilesLayer`・`i3sLayer`・点群はモデルのプログラムで同じ式で描く（`lights` がなければ今までの固定の光）。
  - pack test の `model`：GeoJSON の押し出しを足し、環境光 1 で屋根が色そのまま（32,128,192）とモデルの赤、環境光 0.25 ＋ 太陽 0.5 を真上近くから当てると両方ほぼ半分（16,64,96 と 115）、東京の正午の `timeOfDayLights` でモデルが赤いまま。
  - 依存：suncalc 2.1.1（bench の devDependency、BSD-2-Clause、install スクリプトなし、NOTICE に追記）。CesiumJS は 20.5 からの devDependency。
  - 大きさ：表示（メイン）151.7 → 153.9KB（155KB。`sun.ts` 1.2KB を含む）、`custom.js` 2.9 → 3.0KB（3KB）、`3d.js` 6.4 → 6.5KB、`3d-tiles.js` 10.1KB のまま。
  - `style:golden` の `extrusion-patterns` は main でも同じ 0.215（限度 0.2）で、この変更によらない（Web の SwiftShader。記録済みの結果も false）。
  - まだないもの：影（20.8b）、点光源、`lights` の式（ズームで変わる色など）、地形とラスタへの光。
- **20.8b：影**（2026-11-09 のユーザー判断：地面・押し出し・3D の層のすべてに落とす、地球表示にも、深度テクスチャは 1 枚を視界に合わせる、表示（メイン）は超えたら 160KB に）：
  - 作り：スタイルの `lights` の平行光に `cast-shadows`（と `shadow-intensity`、0〜1）があり太陽が地平線より上なら、毎フレーム太陽から見た正射影で深度テクスチャ 2048 px を 1 枚描く（`@core.Transform::shadow_view`：中心のまわりの地面、カメラが傾くほど広く、1000 m までの高さ。地球表示で遷移が半分を超えたら単位球の上で `shadow_sphere_view`）。押し出しは自分のプログラムの 4 番目の描き方で、カスタムレイヤーは mbmap の拡張 `renderShadow`（行列が光のもの）で書く。受ける側（押し出しと 3D の層のプログラム）は太陽の項に 4 点の比較の平均を掛ける。平らな地面は、最初の押し出しかカスタムレイヤーの下で画面のタイルに暗さを重ねる（太陽が地面の光に占める割合 × 強さ。地形の上はまだ）。
  - 20.8a の直し：`lights` の向き（方位）の東西・南北が逆だった（MapLibre の `light_direction` は西と北に向かう軸で、押し出しの法線もその軸）。20.8a の確かめは真上からの光の明るさだけで、向きを見ていなかった。
  - カスタムレイヤーに渡す数を固定の並びにした（地球表示でなくても地球の分を 0 で埋め、光、影を続ける。`CUSTOM_*`）。`renderInput` は `lights` と `shadow`（光から見た Mercator 0〜1 と単位球の行列、強さ、1 テクセルの深さ）を返す。モデルのプログラムは `begin` に描画の入力をそのまま取り、`draw` は Mercator と球への枠（`mercatorFrame`・`sphereFrame`）を取る。
  - pack test の `model`：北 45° からの太陽（環境光 0.5、太陽 0.5）で、20 m の押し出しとモデルの南の地面が 255 × (1 − 0.354 / 0.854) = 149 に、離れた所は白のまま。押し出しの影にかかる 5 m の屋根は影の中が環境光だけ（16,64,96）、外は太陽も（27,109,164）。地球表示（ズーム 11、球の上の深度テクスチャ）でも 500 m の押し出しの南が 149。どれも計算どおり。
  - 大きさ：表示（メイン）153.9 → 157.2KB（予算を 160KB に）、`custom.js` 2.97KB（3KB。Mercator の前置きの空白を詰めた）、`3d.js` 6.5 → 6.9KB。
  - まだないもの：地形の上の地面の影、点群の影（点は落とさない）、半透明のモデルの影（落とさない。半透明の押し出しは落とす）、カスケード（遠くの影は粗い）、ラスタやラベルへの影。性能は Mac で測る（深度テクスチャを毎フレーム描き直す分）。

## Phase 19 の後の点検（2026-11-08、Mac）

Phase 19 で足したものを中心に、プロジェクト全体との重なりも見ながら AGENTS §7・§8 で見直した。ユーザーの判断（2026-11-08）で、見つけたものは速さの比較を除いてすべて 1 PR で直した（可視域と GDAL の突き合わせは #135）。ワーカーが持つデータセット・格子・網の数には上限を設けない（同日ユーザー判断。代わりに古い番号を断る）。

- **セキュリティ（中）**：
  - 自然分類（jenks）は O(k·n²) の表を主スレッドで作るので、100 万値 × 256 級でタブが止まった。`MAX_JENKS_WORK`（値² × 級、1e9）と `MAX_CKMEANS_CELLS`（値 × 級、1e7）を超えると断る。
  - k-means は反復 1 万回 × n × k に上限がなかった。実際に計算した距離の数で `MAX_KMEANS_DISTANCES`（1e10）まで。最初に n·k·反復で断ると、既定の k で 1 万 3 千点ほどしか通らないので、数えながら止める。
  - DBSCAN は距離が大きいと O(n²)。近傍を調べた数で `MAX_DBSCAN_CANDIDATES`（1e9）まで。
  - 密度の等値線は線分の数に上限がなかった（`bandwidth` 0 で数 GB）。`MAX_CONTOUR_SEGMENTS`（400 万）と、穴の入れ子の判定の `MAX_CONTOUR_NESTING_TESTS`（1e8）。
  - `relate_worker` は書き出す組だけを数えていた。調べる組を `MAX_RELATE_CANDIDATES`（1000 万）、その点の合計を `MAX_RELATE_TESTED_POINTS`（1e9）まで。
- **セキュリティ（低）**：`simplify` に点の上限（`MAX_SIMPLIFY_POINTS`、100 万）。`surface_worker` の長さの和の Int32 のあふれ（`@wasmio.lengths_fit`）。DBSCAN・k-means・`nearest_on_line` の出力と可視域の入力の写しを、確保の前に大きさで確かめる（`@wasmio.output_fits`、`@viewshed.grid_fits`）。`terminate()` のあとの古い `Dataset`・`DemGrid`・`Network` は、新しいワーカーの同じ番号のものを読まずに断る（`WorkerClient` の `generation`）。`Network.dispose` の拒否を握りつぶす、wasm の読み込みの失敗をキャッシュしない、知らない操作に答えを返す（約束が残らない）、見通しの始点と終点が同じとき、`lineOfSight` の点と各引数の有限性、`evaluateExpression` の `$id`・`$type` を常に置く（属性の同名のものが代わりに入らない）、example の表の見出しの `constructor`。
- **正しさ**：`classStep` は同じ区切りが続くと後の級を取り、順でない区切りは断る（MapLibre の `step` が断る式を作らない）。`dissolve` などは捨てたデータセットで同期的に例外を投げず、ほかと同じく拒否する。
- **整理**：
  - `core` に Turf の地球半径（`TURF_EARTH_RADIUS`）と `PI`、`turf_radians`・`haversine`・`turf_ring_area`・`js_round`（`Math.round` の −0 も。`style` の `round` も同じになった）・`js_min`/`js_max`・`stable_sort`、`geom` に `Table::feature_points`。それぞれ 2〜5 か所にあった写しを消した。
  - 上限を通らない公開の入口（`delaunay.triangles`、`clusters.dbscan`・`kmeans`）を消し、上限つきのものを元の名前に。`hull` の `concave`・`convex` は `Table?` を返し、`shapes_worker` の二重の確かめを消した。使われない `pub using Trig` 4 つを消した。
  - `analysis_worker/js/worker.mjs` の繰り返し（モジュールの URL、テーブルの受け渡し、f64 の結果、データセットの答え）を補助関数に、DEM の格子の `res` を持たせて `viewshed.mjs` のメルカトルの計算を消した。`analysis.ts` の haversine を `sight.ts` の 1 つに、点と範囲の確かめを `isPoint`・`isBox` に。`addColumn` の `getData` を 1 回に。example の解析のタブで、失敗しても `dispose` する。
  - MoonBit の 3 行を超えるコメントはなくなった（`long-comments.mjs` の残り 12 件は TS・JS の API の説明とゴールデンの冒頭）。上限の None のテストを足した（`MAX_GRID_POINTS`、`MAX_CELL_BREAKS` ほか）。
- **見送ったもの**：4 つの優先度つきキュー（flatqueue、tinyqueue 3 と 2.0.3、MapLibre の比較）は同点の扱いが違うのでまとめない。点と環の判定（analysis の `orient_origin` と isolines の `orient2d`）は、まとめると解析ワーカーに `robust` が入る。DBSCAN の距離は Turf と同じ `pow(sin, 2)` のまま。proj・clipper・geodesic・overlay の定数の写しはそのまま。大きな移植のファイル（rbush、delaunator、`viewshed/executor.mbt` など）は行数だけでは分けない。
- **依存**：`npm audit` は `npm/`・`bench/`・`examples/react/` とも 0 件、Dependabot の警告 0 件。ゴールデンのための依存は MIT・ISC・BSD・Unlicense・EDL/EPL で、NOTICE にある。Mac の `bench/node_modules` が古かった（jsts 2.7.1）ので `npm ci` し直した。
- **大きさ**：解析ワーカー 29.9 → 29.7KB、relate.wasm 26.5 → 26.8KB、surface.wasm 28.1 → 28.7KB（線分の予算）、`mbmap/analysis` 7.7 → 7.8KB、表示ワーカー 80.5KB、表示（メイン）133.7KB。
- **確認**：`moon check --target all --deny-warn`、`moon test --target all`、`npm test` 341、`npm --prefix bench test`、ゴールデン（viewshed・relate・shapes・surface・route・analysis・classify・fields・expression・geojson・cluster・style・labels・query・color）すべて同じ、`npm:pack` 通過。
- **残り**（振る舞いの候補の扱い、2026-11-08 ユーザー判断）：
  - フィールド演算が編集のたびにデータ全体を `getData`/`setData` する：GeoJSON ソースに MapLibre の `updateData(diff)` を足す。@maplibre/geojson-vt 6.3.0 の更新できる索引（`difference.ts`、`invalidateTiles`、`updateIndex`）まで移植し、更新のあとの全タイルをゴールデンで比べる。段階は、主スレッドの差分と変わったタイルだけの読み直し、ワーカーの増分、フィールド演算の切り替えの 3 つ。予算は GeoJSON のワーカー 30 → 34KB、`clusterProperties` のモジュール 50 → 54KB。
    - 1 段目（済み、主スレッド）：MapLibre 6.16 の `GeoJSONSourceDiff`（`removeAll`・`remove`・`add`・`update`）を `geojson.js` 側の `npm/src/geojson-diff.ts`（`toUpdateable`・`applySourceDiff`・`mergeSourceDiffs`・`getGeoJSONBounds`・`shouldReloadTile` の移植）に。id のない・重なる地物は MapLibre と同じ文言の `error` で断る（約束は解決する）。ソースごとに読み込みは 1 つずつで、その間の差分は 1 つにまとめる。`setData` は待っている差分を捨てる。URL のソースは読み込みを待ち、ワーカーが取ってきたバイト列を返すので、その上に差分を当てる。スタイル文書（`getData`・`getStyle`）は変わった地物だけを写して書き換え、`sourcedata` を出す。タイルは差分が触れた形の範囲にバッファ（`buffer` / 512 タイル）を足して交わるものと読み込み中のものだけを読み直す（`Map::reload_tiles`、判定は `geojson.js` から渡す。クラスタと `removeAll` は全部）。（2 段目でワーカーには差分だけを送るようにした。）`npm run geojson:update`（MapLibre の関数そのものと、GSI 地物と日付変更線をまたぐ地物の乱数の差分 180 回、合併 60 回、タイル 18 万）はすべて同じ。pack test の `geojson` で、描画とクエリが変わること、`setData` の 6 タイルに対し 2 タイルだけ読み直すこと、URL ソースと拒否を確かめる。大きさは表示（メイン）133.7 → 133.8KB、GeoJSON ソース 1.8 → 3.9KB、GeoJSON ワーカー 29.5 → 29.6KB（式を持つもの 49.4KB）。判定を MoonBit（core）に置くとメインが 0.24KB 増えたので JS に置いた。
    - 2 段目（済み、ワーカーの増分）：ワーカーには差分だけを送る（docs/FORMATS.md「GeoJSON diff」、`geojson.js` で `geojson_worker/js/diff.mjs` の `encodeDiff`）。`tiler` が geojson-vt 6.3.0 の `updateable` の索引を移植：変換した地物（`source`）と座標のない地物（`unlocated`）を持ち、`applySourceDiff`（同じ id の地物の置き換え、更新した地物は末尾に、`removeAll`、id のない地物は `null` として扱う）、`invalidateTiles`、最上位タイルの切り直し、クラスタは木の作り直し（`clusterProperties` も）。地物の行は `@geom.Table` に足し（`Table::push_row`）、使われない行が半分を超えたら詰める（形は捨てる）。属性だけの更新は地物の行を置き換える（古い地物を持つタイルはすべて捨てられるので写さない）。`promoteId` は読み込みの入力の先頭で渡し、表の id をその値にする（geojson-vt と同じく、タイルやクラスタの葉の id も昇格した値）。読み込みに失敗したソースへの差分は空の索引に当てる（MapLibre のワーカーと同じ）。`@formats.read_geojson_features` は地物ごとの行の終わり（GeometryCollection は要素ごとに行）も返す。`npm run geojson:diffs`（GSI 地物 11 万 6844 と日付変更線をまたぐ 3004 の地物に 5 つのオプション、promoteId、クラスタ 2 種と `clusterProperties`、乱数の差分 510 回：追加・置き換え・重複・id なし・削除・`removeAll`・形の更新・空の形・座標のない地物の位置づけ・属性の追加と削除・promoteId の属性の変更）で、毎回範囲のすべてのタイル 19 万を js は全部、wasm-gc はハッシュで比べ、0 件違う（クラスタの葉と展開ズーム 4 万 9 千も同じ）。速さ（`npm run geojson:update-node`、M2、Node 22.23.4、11 万 6840 地物、z15 の 100 タイルを切り直すまで）：属性 10 地物の更新は `setData` 1200.8 ms に対し `updateData` 340.9 ms（geojson-vt は 1141.2 → 679.0 ms）、1 地物の形は 1305.8 → 274.0 ms（geojson-vt 1371.6 → 534.8 ms）。残りの多くは最上位タイルを全地物から作り直す geojson-vt の作り。大きさは GeoJSON ワーカー 29.6 → 37.0KB（式を持つもの 49.4 → 56.5KB）、GeoJSON ソース 3.9 → 4.5KB（`encodeDiff`）。ワーカーの増分の大半は差分の適用・詰め直し・タイルの無効化のコードで、文字列の id のキーに `Map[String, Int32]` を 1 つだけ使う、反復子を通常のループに、属性の写しをやめるなどで 40.9KB から縮めた。
    - 3 段目（済み）：フィールド演算（`createFieldEditor`）は、変わった地物の属性だけを `updateData`（`removeAllProperties` と、キーの順のままの `addOrUpdateProperties`）で書く。地物に一意の id がない（`promoteId` か地物の id）か、編集で id が変わる（`promoteId` の列の名前を変えるなど）ときは、これまでどおり `setData`。example の地点（`promoteId: "name"`）の列の計算・名前の変更・削除が通る（pack test）。`createFieldEditor` 単独 1.4KB / 2KB。
  - タイルの境の道路のつなぎ：`querySourceFeatures` の地物に MapLibre と同じ `tile: {z, x, y}` を付け、example は線を各タイルの範囲で切ってから網にする（ズームが混ざれば最も深いもの）。`network({ snap })`（メートル、既定は使わない）で、線の端から snap 以内の別の線の途中を分けてつなぐ。route.wasm の予算は 15 → 17KB。
    - 1 段目（済み）：`querySourceFeatures` の地物に MapLibre と同じく元のタイル `tile: {z, x, y}` を付けた（`query:golden` も比べて 447 すべて同じ）。example の経路は各道路を自分のタイルの範囲で切り（`examples/shared/tile-lines.js`、緩衝帯の重なりを除く）、ズームが混ざるときはいちばん深いタイルだけを使う。pack test で切り方と経路（572 m）を確かめる。表示（メイン）133.7KB（+21 バイト）。2 段目は `network({ snap })`。
    - 2 段目（済み）：`Dataset.network({ tolerance, snap })`（メートル、既定 0 でいままでと同じ網。`route:golden` 1400 すべて同じ）。網を作る前に線を節で分ける（`@route.snap_lines`、pgRouting の `pgr_nodeNetwork`・GRASS の `v.clean tool=snap,break` と同じ考え）：線の端は `snap` 以内の最初の端の組に入り、組はそこから `snap` 以内のいちばん近い線分上の点へ動いて、その線分にその点を頂点として足す（別の組の端に寄るときはその組と同じ所へ）。距離は端の緯度の正距円筒（Turf の地球半径）。自分の線は端から線に沿って 2 × `snap` 以内を除く。線分は `snap` と線分の平均の大きさの大きい方の格子に入れ、`MAX_SNAP_CELLS`（800 万）と `MAX_SNAP_TESTS`（2 億）を超えると断る。`npm run route:snap`（新設）：総当たりの検算で、`snap` 以内に相手のある端 17,633 がすべて頂点を共有し、動きは 2 × `snap` 以内、足した頂点は元の線分の上。GSI z14 の 2 × 2 タイルで、タイルで切った道路（`tileLines`）に `snap: 2` の経路は、切らない道路（2 × 2 の範囲で）がつなぐ 285 組のどれも失わず、97 が同じ、161 が短く（最大 3.0 km：GSI の道路は端が別の道路の線分の途中に載るだけで頂点を共有しないことが多く、geojson-path-finder ではつながらない）、27 が端の移動のぶん長い（最大 3.8 m）。T 字路とタイルの境でずれた端は `snap` でだけつながる。端からいちばん近い別の線分までの距離は、0 m（線分の途中に載る）のほかは 0.5 m 以下 9、1 m 以下 5、2 m 以下 8、2〜5 m 42 なので、example は `snap: 2`。route.wasm 13.0 → 16.2KB。網を作る時間（`route:node`）は測っていない。 網づくりの費用は `route:node` で GSI の道路 13008 線が 6.45 → 13.7 ms（`snap` 2 m）。
  - 自然分類の最大の級が 1 つの値だけになる：いまのまま（外れ値を級にするのは jenks の答え）。

### Phase 19 の速さの比較（2026-11-08、M2、Node 22.23.4）

`npm run {relate,shapes,surface,route,classify,viewshed}:node`、結果は `bench/results/*-node.json`。各ゴールデンの入力（GSI の z14 4 タイル、乱数）を大きくしたもの。1 回の呼び出しの中央値（300 ms 温めてから、50 ms 以上の標本 7 つ）。mbmap の時間は解析ワーカーと同じ道すじで、データセットのテーブルを analysis.wasm から出して各モジュールに入れ、export を呼び、テーブルの結果を analysis.wasm にデータセットとして読み戻すまで（ワーカーのメッセージは含まない）。JSON には写しだけの時間（`tablesIn`）と export までの時間（`exportOnly`）もある。比は mbmap / JS で、1 未満なら mbmap が速い。

| 処理 | JS（ms） | mbmap（ms） | 比 |
|---|---|---|---|
| relate：intersects、GSI 建物 × 道路（JSTS、候補は flatbush） | 248.8 | 121.7 | 0.49 |
| relate：intersects、道路 × 道路 200 | 26.4 | 10.1 | 0.38 |
| relate：touches、ランダムな 60 × 60 を 20 組 | 701.9 | 251.8 | 0.36 |
| relate：DE-9IM 行列 100 組（1 組 1 呼び出し） | 0.99 | 0.40（最初 8.95） | 0.40 |
| GeoJSON 43847 地物の読み込み（JSTS の reader 対 `load`） | 27.4 | 183.3（うち `JSON.stringify` 51.2） | 6.7 |
| simplify：GSI 道路 13004 | 1.94 | 2.33（最初 9.52） | 1.20 |
| simplify：GSI 建物 30758 | 56.8 | 21.9（最初 53.1） | 0.39 |
| 凸包（建物 8000）／凹包（58177 点） | 25.1／65.2 | 17.3／43.7（最初 22.3／48.7） | 0.69／0.67 |
| ドロネー 10 万点（d3-delaunay の三角形まで） | 87.2 | 71.7（最初 158.9） | 0.82 |
| ドロネー 10 万点（delaunator、添字だけ） | 59.3 | 70.6（最初 172） | 1.19 |
| ドロネー 1000 点／ボロノイ 10 万点 | 0.372／72.2 | 0.455／91.8（最初 1.33／178.7） | 1.22／1.27 |
| nearestPointOnLine（1522 線 × 10 点）／lineSlice（1502 線 × 10） | 101.5／192.9 | 22.6／42.3（最初 29.3／52.4） | 0.22／0.22 |
| 点の格子 0.1 km（10192）／三角形の格子（20384） | 0.20／1.58 | 0.389（最初 2.28）／1.56（最初 9.63） | 1.94／0.99 |
| 六角形の格子（3747）／正方形の格子（12321） | 0.895／0.982 | 0.395／1.00（最初 2.67／6.75） | 0.44／1.02 |
| IDW 200 点、0.25 km の正方形 | 60.9 | 21.8（最初 22.7） | 0.36 |
| 等値線／等値帯（6497 点の格子、7 区切り） | 0.863／1.66 | 0.699／1.31（最初 2.19／2.88） | 0.81／0.79 |
| 密度（6000 点、d3-contour） | 14.6 | 9.1（最初 11.4） | 0.62 |
| DBSCAN 6000 点 2 km／k-means 既定の k | 1974.3／132.5 | 896.7／56.6 | 0.45／0.43 |
| 経路：網を作る（GSI 道路 13008 線）／800 経路 | 98.0／476.7 | 6.45／78.5（最初 17.8／79.7。`snap` 2 m で網づくり 13.7） | 0.07／0.16 |
| 経路：100 × 100 の格子の網／200 経路 | 71.6／560.8 | 3.8／131.9（最初 5.48／129.4） | 0.05／0.24 |
| 分類：統計／等量 7 級（100 万値） | 14.0／16.0 | 12.4／17.2 | 0.89／1.08 |
| 分類：等間隔 7 級（100 万値） | 1.32 | 2.97 | 2.2 |
| 分類：標準偏差 7 級（100 万、geostats）／ckmeans 7 級（10 万）／jenks 7 級（5000） | 663.4／62.1／255.0 | 5.72／41.5／269.6 | 0.009／0.67／1.06 |
| 可視域 1024²、範囲なし（GDAL の正味、プロセスは 153.5） | 20.5 | 45.6（最初 69.4） | 2.2 |
| 可視域 4096²、範囲なし（同 469.8） | 342.5 | 650.4（最初 1091.5） | 1.9 |
| 可視域 4096²、5 km（同 136.8） | 4.03 | 3.59（最初 50.2） | 0.89 |

- **可視域の測り方**：`gdal_viewshed` は 1 回ごとのプロセスなので、2 × 2 の DEM での実行（起動、ドライバ、小さな入出力。132 ms）を引いた正味と比べる。1024² では正味が起動より小さく揺れるので、起動が目立たない 4096²（富士山の DEM を 4 × 4 に鏡映）も測った。GDAL の CPU 時間は壁時計とほぼ同じ（ほぼ 1 スレッド）で、MEM ドライバに書いても GTiff と変わらない。mbmap は 1 スレッドで、格子の値を analysis.wasm から出して入れ、出力を読むまで。
- **速いもの**：述語（0.36〜0.7）、経路（0.08〜0.21）、IDW・DBSCAN・k-means（0.3〜0.56）、線の操作（0.27〜0.29）、凸包・凹包・密度・建物の simplify（0.75〜0.91）。
- **分類は直した**：毎回 `x.slice().sort((a, b) => a - b)` で並べていた（100 万値で約 330 ms、統計 349.2 ms、等間隔 344.1 ms）。有限の値を `Float64Array` に集め、統計と等間隔は最小・最大を走査、中央値と等量は simple-statistics の quickselect と multiselect をそのまま移し（ゼロの符号まで同じになる）、jenks と ckmeans は `Float64Array` の `sort()` で並べて -0 と 0 だけ元の順に戻す。標準偏差は中央値を求めない。`classify:golden` に符号つきゼロの 20 組を足し、すべて同じ。`[-0, 0]` の最大は前は 0 で、simple-statistics と同じ -0 になった。入口は 7.8KB → 8.3KB（分類は 1.9KB → 2.4KB）。等間隔に値を写さず走査だけする版は速くならず（2.75 → 3.0 ms、有限の判定が費用）、戻した。
- **直したもの**（2026-11-08、表の「直す前」と同じ測り方）：
  - DE-9IM 行列 8.95 → 0.46 ms（JSTS の 0.46 倍）：時間のほとんどは 1 組ごとのテーブルの写しと `Table::from_bytes` で、relate の計算は 1 組 4.5 µs ほど。relate.wasm が最後の組のテーブル（と 2 つめの索引）を持ち、ワーカーは同じデータセットの組なら `len_a` -1 で写さずに呼ぶ（データセットは変わらず番号も使い回さない。`dispose` で `forget_tables`）。
  - 等値線 2.19 → 1.7、等値帯 2.88 → 2.38 ms：格子の点の並べ替え（`sort_by`、計算の 2 割弱）を、行か列の順に並んだ格子（Turf の `pointGrid` は列の順）なら 1 回の走査で確かめて済ませる（`lat_lng_order`。順序は全順序なので確かめた候補が並べ替えの答えと同じ）。
  - ボロノイ 10 万点 178.7 → 169.7 ms：セルごとの配列の伸長と写しを減らす（容量を見込み、重なる点を除くのはその場で）。
  - 試して戻したもの：ドロネーの点の取り出しを `FixedArray` に直接、delaunator の結果を `blit_to` で写す（10 万点で差が雑音の内）。
- **テーブルの写しと可視域を速くした**（2026-11-08。表は relate・ボロノイ・等値線の直しと合わせたあとに取り直した値）：
  - 調べると、道路の simplify の約 7 割が `Table::to_bytes`（`ByteWriter` に 1 バイトずつ足し、伸びる `Array[Byte]` を写す）、`from_bytes`（`ByteReader` で 1 バイトずつ）、`write_bytes` / `input_bytes` の写しで、simplify 自体は 1 割だった。テーブルの形式を `@geom.TableSource` / `TableSink` に通して読み書きする `Table::read_from` / `write_to` にし、wasm-gc のモジュールは線形メモリの上でそのまま読み書きする（`@wasmio.input_table` / `write_table`：f64 は 1 命令、中間の `Bytes` なし）。`to_bytes` / `from_bytes` は同じ形式のまま。道路 4 タイルのテーブルの受け渡しは 2.4 → 0.12 ms。格子は `TableBuilder::reserve` で配列を先に取る（三角形の格子の export が 1.26 → 0.90 ms）。
  - 可視域：ソフトウェアの `fma` が組（タプル）を返す `split` / `two_sum` を呼び、wasm-gc では呼ぶたびに確保していた。展開し、`c` が 0 のときは積がそのまま答え、北が上の格子では列ごとの `dx * dx` とその誤差を先に作り（行によらない）、曲率の係数の分割も 1 回にした（4096² で 1271 → 707 ms、出力は GDAL とビット単位で同じまま）。範囲つきでは読む窓（`viewshed_window`）だけを analysis.wasm から出して入れる（`grid_window`、`viewshed` の `cells`）。
  - 試して残さなかったもの：`Cursor::ends` を `Array::makei` で読む（差が揺れの内）、`write_bytes` を 4 バイトずつ（テーブルが通らなくなり、大きさだけ増えた）。
  - 大きさ：線形メモリで読み書きする版がモジュールごとに入るので、解析ワーカー 29.7 → 30.2KB、データワーカー 39.9 → 40.6KB、services 20.0 → 20.2KB で予算を超えた（xml 26.7 / 27、shapes 27.9、surface 29.0、viewshed 9.9 は収まる）。予算を 1KB ずつ上げた（解析ワーカー 31KB、データワーカー 41KB、services 21KB。2026-11-08 ユーザー判断）。解析ワーカーは relate の直しと合わせて 30.3KB。
- **残る遅いもの**（Phase 20 の前の直しのあと）：
  - 可視域（範囲なし）：GDAL の約 2 倍。残りは `adjust_height` の曲率の `fma`（セルごとに 1 回）と `line_right` の `height_edge`。
  - ドロネー・ボロノイの小さな入力（1000〜1 万点）：d3-delaunay の 1.1〜1.6 倍。呼ぶごとの固定費（テーブルの読み書き、モジュールの境）。10 万点のドロネーは d3 より速い。
  - 点の格子：Turf の 1.9 倍（0.39 ms）。残りは `TableBuilder` の地物ごとの `push`。
  - 等間隔の分類：simple-statistics の 2.2 倍（3 ms、有限の値の確かめ）。
  - GeoJSON の読み込み：JSTS の reader の 6.4 倍。半分強は `JSON.stringify` と文字列からの解析で、Phase 17 の `data:node` と合わせて見る。

## Phase 19：解析 第2弾（2026-11-07〜11-08）

範囲・段階・予算の扱いは 2026-11-07 にユーザーが決めた。VISION §8 の Phase 19 の項目のうち、測地線の計測は Phase 14 で済んでいるので除く。

- **段階**（1 段階 1 PR）：
  - 19.1：空間関係（DE-9IM）。JSTS 2.12.1 の `RelateOp`（GeometryGraph 方式）と `Geometry` の述語を移植し、`Dataset.relate(other, relation)` と `relateMatrix` にする。
  - 19.2：単純化、凸包・凹包、ボロノイ・ドロネー、線の分割と線上の最近点。
  - 19.3：分類（自然分類、等量、等間隔、標準偏差）と統計、凡例とのつなぎ。
  - 19.4：カーネル密度、六角形の集計、DBSCAN・k-means、IDW、等高線。
  - 19.5：可視域と見通し。
  - 19.6：作り手のデータの道路網での経路探索。
  - 19.7：フィールド演算（属性テーブルの列の追加・削除・名前の変更と、スタイルの式による値の計算）。
  - 19.8：example の仕上げ。
- **予算**：解析ワーカーは 28.6 / 30KB、geometry.wasm は 41.8 / 50KB で余裕がないので、機能のまとまりごとに wasm を分け、解析ワーカーが初めて使うときに読み込む。予算は各段階で測ってから決める。
- **比較の相手**（2026-11-07 の調べ。すべて MIT・ISC・BSD・Unlicense・EDL/EPL）：
  - 19.1：`jsts` 2.12.1（EDL-1.0 / EPL-1.0。依存は `fastpriorityqueue` だけ、インストール時のスクリプトなし。`npm audit` 0 件）。
  - 19.2：`@turf/simplify`（simplify-js と同じ）、凸包は `@turf/convex`（`concaveman` の `Infinity`）、凹包は `concaveman` 2.0.0（`@turf/concave` は別の重い方式）、ドロネー・ボロノイは `delaunator` 5.1.0 と `d3-delaunay` 6.0.6（`@turf/voronoi` は古い `d3-voronoi`）、線は `@turf/line-split`・`nearest-point-on-line`（7.x は球面のベクトル計算で、ホストの `Math` が要る）・`line-slice`。`robust-predicates` の `orient2d`、`rbush`、`tinyqueue` は一度だけ移植して共有する。
  - 19.3：`simple-statistics` 8.0.0（ckmeans と jenks は区切りが違うので、名前で分ける）、標準偏差などの分類は `geostats` 2.1.0。
  - 19.4：密度は `d3-contour` 4.0.3 の `contourDensity`（Turf にない）、六角形は `@turf/hex-grid`、`@turf/clusters-dbscan`・`clusters-kmeans`（`skmeans` 0.9.7、最初の k 点で始めるので決まった結果）、`@turf/interpolate`、等高線は `@turf/isolines`・`isobands`（`marchingsquares` は AGPL なので使わない）か `d3-contour`。
  - 19.5：GDAL の `gdal_viewshed`（M2 の GDAL 3.13.3。Web の環境に GDAL はないので、`terrain:golden` と同じく Mac で回す）。
  - 19.6：`geojson-path-finder` 2.1.0（作り手と同じ GeoJSON の線から網を作る）。`ngraph.path` で経路の長さを確かめる。
- **19.1 の結果**：
  - `relate`（純粋な MoonBit、全バックエンド）：JSTS 2.12.1 の `RelateOp` と `Geometry` の述語の移植。GeometryGraph、単調鎖の掃引、DD の向き判定つきの `RobustLineIntersector`、JSTS の赤黒木 `TreeMap`、長方形の近道（`RectangleContains`・`RectangleIntersects`）まで、演算の順を含めて写した。JSTS が例外を投げる不正な形（側の矛盾など）では止まらずに最善の答えを返し、`relate_checked` は None にする。1 組の点は合わせて `MAX_RELATE_POINTS`（100 万）まで。
  - `relate_worker`（relate.wasm 26.5KB、予算 30KB）：箱の重なる組を `@analysis.Index` で探し、述語か DE-9IM のパターンで残す。組は 1000 万まで。離れた組が当てはまるパターンは TS 側で断る（`npm/src/relate-pattern.ts`）。
  - API：`Dataset.relate(other, relation | { pattern })`、`relateMatrix(other, i, j)`。example の「近くの地点」は `pointsWithin` から `relate(zone, "coveredBy")` に替えた。
  - `npm run relate:golden`：手書き 41 組（逆向きも）と格子の上のランダムな 2 万組の行列、ランダムな集合 20 組と GSI の 4 タイル（建物・水域・道路の組）の 9 述語の組がすべて JSTS と同じ。移植のテストは、JSTS で求めた行列 83 件とランダムな 150 組（不正な形を含む）、壊れた入力が止まることを確かめる。

- **19.2 の結果**：
  - 新しい純粋なパッケージ 5 つ（全バックエンドでテスト）。`robust`（robust-predicates 3.0.3 の `orient2d`。厳密な段階まで JS と同じ値）、`simplify`（`@turf/simplify` 7.4.0。`cleanCoords` と、環が 4 点を保つまで許容値を下げる規則を含む）、`hull`（concaveman 2.0.0 と rbush 4.0.1・quickselect・tinyqueue・point-in-polygon。`@turf/convex` は入れ子の concaveman 1.2.1 を使うが、差は書き方だけで結果は同じ）、`delaunay`（delaunator 5.1.0 と d3-delaunay 6.0.6 の `Delaunay`・`Voronoi`。一直線の点の揺らしと V8 の `Math.hypot` を含む）、`lineops`（`@turf/nearest-point-on-line` と `line-slice` 7.4.0。7.x の球面のベクトル計算を `@core.Trig` で）。
  - `shapes_worker`（shapes.wasm 27.9KB、予算 30KB）：ホストの `Math` で動かす。rbush の対数も `Trig` から取り、コアの `@math` を入れない（28.7 → 27.9KB）。
  - API：`Dataset.simplify`、`convexHull`、`concaveHull`、`delaunay`、`voronoi(bbox)`、`nearestPointOnLine(x, y)`、`lineSlice(start, stop)`。線どうしの分割は既存の `split`（Clipper2）を使い、`@turf/line-split` は移植しない（sweepline-intersections などを持ち込む割に、できることが重なる）。
  - JS と違うところ：NaN・無限の点は凸包・凹包・ドロネーから外す（JS は壊れた結果か無限ループ）、点が 3 つに満たないドロネーは三角形なし、Turf が例外を投げる入力（負の許容値、閉じていない環）は元の形のまま返す。上限は `MAX_HULL_POINTS`・`MAX_DELAUNAY_POINTS`（100 万）。
  - `npm run shapes:golden`：ランダムな点・格子の点・一直線の点の三角形とボロノイの領域（61 組）、凸包・凹包（ランダム・格子・GSI の建物と水域、凹度と長さのしきい値を 4 通り）、GSI の道路・建物・等高線・水域の単純化（許容値 3 通り × highQuality）、GSI の線の最近点と切り出し（80）がすべて Turf・concaveman・d3-delaunay と同じ（`Object.is`）。
  - 途中の不具合：解析ワーカーへのメッセージの引数に `op` という名前を使ったため、呼ぶ操作の名前を上書きして無視され、pack test が止まった。引数を `shape` に改めた。

- **19.3 の結果**：
  - `npm/src/classify.ts`（import のない TS、`mbmap/analysis` から出す。Worker も wasm も使わない）：`classBreaks(values, classes, method)`（simple-statistics 8.0.0 の `jenks`・`ckmeansBreaks`・`quantile`・`equalIntervalBreaks`、geostats 2.1.0 の標準偏差の級）、`statistics(values)`（simple-statistics の補正つきの和、平均、中央値、母分散）、`classStep(input, breaks, outputs)`（`mbmap/ui` の凡例が級ごとの項目にする `step` の式）。
  - geostats は平均と標準偏差を `roundlength`（既定で小数 2 桁）に丸めるので、標準偏差の級は geostats の並べ方に丸めない値を使う。ゴールデンでは geostats に同じ値を入れてから比べる。
  - simple-statistics の `jenks` は同じ値ばかりの入力で例外を投げるか、undefined を含む区切りを返す。どちらも null にした。ckmeans の再帰は同じ順の明示的なスタックに直した（深い入力でもスタックがあふれない）。
  - 大きさ：`mbmap/analysis` の入口が 4.3 → 6.3KB になり、予算を 5KB から 7KB に上げた（2026-11-07 ユーザー判断。別の入口に分ける案もあった）。
  - `npm run classify:golden`：ランダムな数（40 組）、同じ値の多い整数（40 組）、1 種類・2 個の値、GSI の 6 タイルの数値の属性について、統計と 5 つの方式（級 1〜10、標準偏差は `matchBounds` の有無）がすべて同じ（`Object.is`）。example への組み込み（凡例つきの階級区分図）は 19.8 でまとめて行う。

- **19.4 の結果**：
  - 新しい純粋なパッケージ 4 つ（全バックエンドでテスト）。`grids`（Turf の point・square（rectangle）・hex・triangle grid と `interpolate`、`bbox`・`centroid`。`mask` なし）、`clusters`（`clustersDbscan` と `clustersKmeans`・skmeans 0.9.7。Turf の rbush は葉 1 つの木なので、同じ近傍を x で並べた範囲から探す）、`isolines`（`isolines`・`isobands`。端点の索引で線をつなぎ、Turf の O(n²) の走査を避ける。結果は同じ）、`density`（d3-contour 4.0.3 の `contours`・`contourDensity` と、入れ子の d3-array 3.2.5 の `ticks`・`blur2`。Float32Array の格子は `Float` に丸めて写す。V8 の `Math.log10` も fdlibm の通りに）。
  - `surface_worker`（surface.wasm 28.1KB、予算 30KB）：ホストの `Math` と、帯のラベルに `String(x)` を使う。入力はテーブル、属性名、f64（区切り）の並び。密度は点を `bbox` の上の画素に写して d3 に渡し、等値線を経緯度に戻す。
  - API：`grid(bbox, cellSide, type)`、`Dataset.interpolate`、`isolines`、`isobands`、`density`、`dbscan`、`kmeans`。六角形の集計は `grid` と既存の `collect` で行う。
  - JS と違うところ：どの格子とも交わらない線・帯は形なしの行（テーブルは空の MultiLineString・MultiPolygon を持てない）、Turf が例外を投げるか止まらない入力（0 以下のセル、無限の範囲、格子でない点、文字列の値）は失敗にする、上限（セル 100 万、点 100 万、区切り 4096 など）。
  - `npm run surface:golden`：4 つの範囲 × 3 つのセル × 4 つの格子（六角形の三角形を含む）、ランダムな点の補間（4 格子 × 重み 3 通り、144 組）、なめらかな値とランダムな値の格子の等値線・等値帯（20）、点の密度（ランダム 12、GSI の建物 4）、DBSCAN と k-means と重心（ランダム 90、GSI 36）がすべて Turf・d3-contour と同じ（`Object.is`）。
  - 大きさ：`mbmap/analysis` の入口が 6,953 バイトになり、19.7 までの API を見込んで予算を 7KB から 9KB に上げた（2026-11-07 ユーザー判断）。

- **19.5 の結果**：
  - `viewshed`（純粋な MoonBit、全バックエンド）：GDAL 3.13.3 の `gdal_viewshed`（`alg/viewshed` の `Viewshed`・`ViewshedExecutor`・`util.cpp`）の移植。GDAL はスレッドで上下の行と左右を並べて計算するが、各行が前の行の結果だけを読むので、同じ順に 1 本で回して同じ値になる。曲がりの補正は CRS の長半径から（`cc / (2a)`）、NORMAL・DEM・GROUND、最小距離・角度・仰角の範囲まで写した。`-sd` と累積（ACCUM）は写していない。
  - `viewshed_worker`（viewshed.wasm 9.0KB とつなぎの `analysis-viewshed.js` で 10.0KB、予算 12KB）：解析ワーカーが格子の標高を渡す。つなぎを解析ワーカーに入れると 30.2 / 30KB を超えたので、最初の可視域で読み込む別ファイルにした。標高タイルの格子は傾斜と同じく中央の緯度での地上のメートル、GeoTIFF の格子はその投影座標系で測る。
  - API：`DemGrid.viewshed(observer, options)`、`DemGrid.lineOfSight(from, to)`（標高を双一次で取り、`npm/src/sight.ts` で gdal_viewshed と同じ曲がりの補正をして決める）。
  - 確かめたこと：移植のテスト 19 件（平面、壁、柱、峰、範囲、曲がり、モード、無効な入力）、`sight.ts` の単体テスト、pack test（富士山の DEM で山頂から 3 km）。
  - **GDAL との突き合わせ（`npm run viewshed:golden`、2026-11-08、M2 の GDAL 3.13.3）**：富士山の DEM（EPSG:3857 の GeoTIFF、北西の角を原点に地上のメートルのセル）で、山頂・斜面・谷・端の 4 か所 × 3 モード × 3 通り（観測点・目標の高さ、距離、曲がり）の 36 件が、出力の大きさ・ジオトランスフォーム・全セルまですべて同じ。初めて回したときに直したもの：
    - スクリプト：メモリが伸びたあとの古い `memory.buffer` を読んでいた。GDAL の AAIGrid の読み手は小数の格子を Float32 で読むので、`-oo DATATYPE=Float64` で開く（これが DEM・GROUND の 0.02 m までのずれと NORMAL の数セルのずれの元だった）。
    - 移植：Homebrew の clang（arm64）は `a*b + c`（と `a*b + c*d` の前の積）を FMA にまとめる。FMA なしでは DEM・GROUND のセルの 3〜5 割が数 ulp ずれた。clang がまとめる式（高さの補間、`adjustHeight`、ジオトランスフォームとその逆、範囲、`verticalIntersect`）だけをソフトウェアの `fma`（`viewshed/fma.mbt`、丸めて奇数にする Boldo・Melquiond の方式）で計算する（2026-11-08 ユーザー判断）。FMA を使わない x86-64 の GDAL とは、この分だけ数 ulp ずれる。viewshed.wasm は 9.0 → 9.2KB。

- **19.6 の結果**：
  - `route`（純粋な MoonBit、全バックエンド）：geojson-path-finder 2.1.0 の移植（前処理、頂点の丸め、縮約、ファントム頂点、tinyqueue 2.0.3 の Dijkstra、@turf/distance の重み）。JS の頂点キー（丸めた座標の文字列）は、-0 と NaN をそろえた double のビットで置き換えても同じにまとまる。近傍の並びは JS のオブジェクトの挿入順（消して入れ直すと最後）まで写したので、同じ長さの経路の選び方も同じ。長い鎖の座標はロープでつなぎ（JS は配列のコピーで二乗）、問い合わせのたびに状態を戻す。MultiLineString は線ごとに分ける（JS は LineString だけ）。
  - `route_worker`（route.wasm 12.9KB、予算 15KB。`snap` を足して 16.2KB、予算 17KB）：網を番号で持ち、同じ網に何度でも問い合わせられる。
  - API：`Dataset.network({ tolerance })` → `Network.route(from, to)` → `{ path, weight }` または null、`dispose()`。
  - `npm run route:golden`：揺らした格子の網 3 つ（600 件）と GSI の 4 タイルの道路（800 件）の経路が、座標も重み（`Object.is`）もすべて geojson-path-finder と同じ。
  - 大きさ：解析ワーカーはつなぎを足して 29.9 / 30KB。19.7 で足りなくなれば、可視域と同じくつなぎを別ファイルに出す。

- **19.7 の結果**：
  - 式の評価：`Map.evaluateExpression(expression, features, { zoom })`（と地図なしで使う `evaluateExpression`）。主スレッドにもともとあるスタイルのコンパイラと `Expr::eval` を使う（`@map.evaluate_expression`、`JsProps` に `$id`・`$type` を足して渡す）ので、評価のための別のモジュールはない。値は style-spec の `evaluate` と同じで、色は `to-string` の文字列、`format` はその文字列、エラーと NaN は null。オブジェクトや配列の属性は null として読む（表示と同じ）。
  - `mbmap/ui` の `createFieldEditor(map, { source, table })`：GeoJSON ソースの列の追加（`addColumn`）、計算（`calculate`。式か行を取る関数、`only: "filtered" | "selected"`）、削除、名前の変更（キーの位置を保つ）。データは `getData` で読んで `setData` で戻す。面積などの形の値は `mbmap/analysis` で求めて関数で渡す。列名の `__proto__` は断る。
  - 属性テーブルに `setColumns` と `passing` を足した。編集を表に入れると表だけで 2.6KB になったので、編集を別の関数に分けた。それでも表が 1,996 → 2,036 バイトで 1 つ 2KB の予算を超え、表だけ 2.2KB にした（2026-11-07 ユーザー判断）。
  - `npm run fields:golden`：expression-cases の値の型の式とフィールド演算の式 240 本を、GSI の 4 タイルの地物（GeoJSON にしたもの）と手書きの 7 件の計 2,539 件 × ズーム 3 通りで評価し、style-spec 26.5.0 の `createExpression(...).evaluate` とすべて同じ（`Object.is`、179 万件）。`within`・`distance` は地物のタイルが要るので除く。
  - 確かめたこと：`ui/table-fields.ts` の単体テスト、`map` の wbtest、pack test（式と関数の列、選んだ行・絞り込んだ行だけの計算、名前の変更と削除でデータが元に戻ること）。example の画面（列の追加などの操作）は 19.8 で足す。

- **19.8 の結果**（範囲は 2026-11-08 ユーザー判断：階級区分図と凡例、属性テーブルの列の編集、道路での経路探索、見通しと可視域の 4 つ）：
  - 3 つの example に「解析」のタブを足した（`examples/shared/analyze.js`、React は `react/src/analysis.jsx`）。
    - 階級区分図：東京の地点のボロノイ領域の面積を、フィールド演算で列にする（関数で m²、式で km²）。自然分類の 5 階級の `step` で塗り、凡例に階級が出る。
    - 経路：描いているタイルの道路から網を作り、クリックした 2 点に近い頂点の間を探す。
    - 可視域：中心から 2 km を `loadDem` と `viewshed` で求め、canvas のソースで塗る。続けてクリックした地点への見通しを線で示す。
    - 足したレイヤーはスタイルが替わると置き直し、地点の下に入れる。
  - 「データ」のタブの地点の一覧に列の欄（列名・式・新しい名前、計算・名前の変更・削除）を足した。見出しは表の `columns` から取る。印を置くときは、列の編集を残すためソースのいまのデータに足す。
  - pack test：解析のタブ（領域 12、区切り 6 つで凡例 5 項目、各領域の m² と km² の列、経路の長さ、可視域の canvas のソースと見える割合、見通し、消すとレイヤーがなくなること）と、表の欄の操作（計算・名前の変更・削除、JSON でない式の知らせ）を 3 つの example で確かめる。経路と見通しのクリックは、パネルに隠れない東側に置く。

## Phase 18 の後の点検（2026-11-07）

Phase 18 で足したもの（`mbmap/services`、`services.wasm` の Esri の読み手、`reprojected` のソース）を AGENTS §7・§8 で見直した。ユーザーの判断（2026-11-07）で、見つけたものは速さの候補を除いてすべて 1 PR で直した。

- **セキュリティ（高）**：
  - GML の `srsDimension` が 0・負・小数だと `positions` が進まず無限ループになった。2〜4 の整数以外は 2 として読む。
  - Esri の多角形（JSON・PBF）は terraformer どおり外周と穴を総当たりで突き合わせるので、細かい輪を大量に並べると二乗で止まらなくなった。シェープファイルの読み手と同じく手数の予算（`MAX_RING_STEPS`）で打ち切り、範囲の箱が離れた組は調べない。PBF の座標は表の点の上限を超えた時点で読むのをやめる（以前は全部読んでから断っていた）。
- **セキュリティ（中）**：
  - 地物の取得のページは 1 つずつは 32MB までだが、合わせての上限がなかった。1 回の取得で 256MB まで（`MAX_GATHERED_BYTES`）。
  - WMS の能力文書のレイヤーの数に上限がなかった。1 万まで（`MAX_WMS_LAYERS`）。
  - `reprojected` のタイルの画像は、頼んだ大きさを超えるものを使わず、1 枚 30 秒で打ち切り、ワーカーに残すのは枚数でなく画素で数える（`MAX_KEPT_PIXELS`、6400 万画素）。`reprojectTile` はデータワーカーの列に並ばず、ほかの読み込みを待たせない。
- **セキュリティ（低）**：テンプレートの `{name}` は自身のキーだけ（`Object.hasOwn`、`{constructor}` を埋めない）、`withQuery` と OGC API のタイル URL の壊れた `%` で URIError を投げない、ArcGIS のソースの表を `Object.create(null)` に。
- **正しさ**：`EPSG:3587`（誤記）を Web メルカトルから外し、`102113` を `reproject.mjs`・`geotiff.mjs` にも足した。`wmsSource` の `crs` が EPSG:3857 なら普通の `raster` に、`tileSize: 512` は `reprojected` にも渡す。ArcGIS のサービスの JSON の `error` を例外にする。ArcGIS の PBF の `Transform` と各フィールドを wire type まで見て読む（型の違うフィールドは飛ばす）、multipatch は形を持たない。
- **整理**：定数（`EARTH_RADIUS`、`MERCATOR_WORLD`、`MERCATOR_LATITUDE`、`OGC_PIXEL_METERS`、`CLICK_PIXELS`、`MAX_IMAGE_SIZE`、`REPROJECTED_TILE_SIZE`、PBF のフィールド番号、`reproject.mjs` の上限）に名前を付け、`followImage` の計算を純粋な `imageView` に、XML の箱の読み取りを `attributeBox`・`corners` に、`serviceBase`・`arcgisError`・`property_limit`・`Shapes::lines`/`multipoint`・ワーカーの `checkTile`・WFS のページ送りの規則 `wfsPagesOn` を一か所にまとめた。
- **見送ったもの**：レビューで出た「PBF の uint64 が符号付きで読まれる」は誤り（`read_varint64` は符号なし）。Esri の輪の補助はシェープファイルのものと意味が違うので共通化しない。`geotiff.mjs` と `reproject.mjs` のタイルの格子の共通化はバイトが減らないので見送り。`reprojected` のタイルの `transformRequest` はテンプレートに 1 回だけ（README に書いた）。
- **依存**：`npm audit` は `npm/`・`bench/`・`examples/react/` とも 0 件。Dependabot の警告はこの環境から読めない（403）ので未確認。
- **大きさ**：`services.wasm` は 18.7KB → 20.0KB（19,966 / 20,000 バイト、輪の予算と箱、点の打ち切り）。次に Esri の読み手に足すものは予算の見直しが要る。
- **確認**：`npm test` 323、`moon test --target all`、`esri:golden` 19/19、`services:golden` 65/65、`reproject:golden` 32/32、`geotiff:tiles` all ok、`npm:pack` 通過。

## Phase 18：GIS の Web サービス（2026-11-06〜）

範囲・段階・予算は 2026-11-06 にユーザーが決めた。サーバーは作らず、すべて読み込みとして扱う。認証は `transformRequest` だけ。

- **段階**（1 段階 1 PR）：
  - 18.1：タイル URL の置き換え。MapLibre の `{bbox-epsg-3857}`・`{bbox}`・`{quadkey}`・`{ratio}`・`{prefix}`。これで Web メルカトルの WMS GetMap、ArcGIS の `export` とタイル、WMTS の GoogleMapsCompatible、OGC API Tiles が普通の `raster` ソースで描ける。
  - 18.2：新しい入口 `mbmap/services`（主スレッドの JS、`DOMParser`）。WMS・WMTS・WFS の GetCapabilities、OGC API と ArcGIS のメタデータを読み、MapLibre のソースを返す。
  - 18.3：ArcGIS VectorTileServer（`root.json`、スプライト、フォント）。
  - 18.4：地物の取得。ArcGIS の `query`（Esri JSON と PBF）、OGC API Features、WFS の GeoJSON。ページ送りと範囲ごとの取得。
  - 18.5：カメラに合わせた 1 枚画像（`export`、GetMap）と GetFeatureInfo・識別。
  - 18.6：Web メルカトル以外のタイルとラスタ（4326・JGD2011 の TileMatrixSet。17.6c の再投影を使う）。
  - 18.7：WFS の GML と example。
- **予算**：`mbmap/services` は 10KB。表示（メイン）は 132.9 / 135KB で余裕がないので、18.1 のほかは遅延読み込みか新しい入口に置く。Esri JSON と PBF の読み手は新しい `services.wasm`（データワーカーは 39.4 / 40KB）。予算は 18.4 で決める。
- **黄金テスト**：公開サービス（ArcGIS Online、OGC のデモサーバーなど）で確かめる。そのためユーザーが環境の許可ホストを広げる。比べる相手は OpenLayers、`@esri/arcgis-rest-*`、`@terraformer/arcgis`、MapLibre 6.16。
- **Phase 19 に足したもの**：フィールド演算（2026-11-06 ユーザー判断）。属性テーブルのコントローラで列を足す・消す・名前を変える。値はスタイルの式で計算し（全件か選んだ地物、取り消しつき）、形から求める値は `mbmap/analysis` で計算する。
- **18.1**：
  - `map/dom.mbt` の `tile_url` は MapLibre の `CanonicalTileID.url` と同じ順で置き換える。`{y}` だけを TMS で反転し、ほかの置き換えは XYZ の行を使う。`{ratio}` は端末の画素比が 1 より大きいとき `@2x` になる。ファサードの `resolveTemplate` は、URL が符号化した置き換えの括弧を戻す（`TILE_PLACEHOLDERS`）。
  - 表示（メイン）は 132.9KB → 133.2KB（+0.3KB、予算 135KB）。
  - `npm run raster:golden` は、置き換えをすべて含むテンプレートで両方のエンジンが要求した URL を比べる。比べる組み合わせは XYZ と TMS、画素比 1 と 2、z14・z15（回転）・z3.4 の 12 場面で、すべて同じだった。タイルはすべて同じ PNG で答える。404 だと MapLibre は親のタイルも要求するため。
- **18.2**：新しい入口 `mbmap/services`（6.5KB / 10KB）。主スレッドの JS で、能力文書はブラウザの `DOMParser` で読む。エンジンには何も足していない（作るソースは 18.1 の置き換えで描ける）。
  - 読むもの：
    - WMS 1.1.1・1.3.0 の能力文書。継承は WMS 1.3.0 の 7.2.4.8 のとおり。
    - WMTS 1.0.0 と WFS 1.0.0・1.1.0・2.0 の能力文書。
    - OGC API のコレクションとタイルセット。
    - ArcGIS REST の `?f=json`。
  - 作るソース：
    - `wmsSource`：EPSG:3857 の GetMap。
    - `wmtsSource`：Web メルカトルの四分木で、TileMatrix の名前がズームのもの。REST を優先し、なければ KVP。
    - `arcgisSource`：Web メルカトルのキャッシュならタイル、それ以外は `export` / `exportImage`。
    - `ogcTiles`：WebMercatorQuad。
  - 文書の中の相対 URL は文書の URL を基準にする。文書は 32MB まで。
  - `npm run services:golden`：公開サービスから取った同じ文書を mbmap と既存の読み手に読ませ、46 件すべて一致した。
    - WMS 4 本と WMTS 3 本は OpenLayers 10.11.0 と比べた。読み取った中身に加えて、`TileWMS`・`WMTS`・`TileArcGISRest` が作る URL も比べ、BBOX は数で比べた。
    - WFS 4 本は @camptocamp/ogc-client 2.0.2 と比べた。
    - 公開サービスは demo.mapserver.org、ArcGIS の sampleserver6、NASA GIBS、services.arcgisonline.com、pygeoapi のデモ。
    - OGC API（pygeoapi の 17 コレクション）も ogc-client と比べた。
    - 作ったソースのタイルは 1 枚ずつ実際に取得し、画像が返ることを確かめた。
  - OpenLayers に合わせて比べたところ：
    - OpenLayers は子レイヤーを、親が受け継いだものを足す前に読む。そのため孫は親自身の CRS やスタイルしか受け継がない。比べる前に、OpenLayers の木を仕様の規則で補った。
    - 最上位のレイヤーの属性（`queryable`、`opaque`）は OpenLayers が読まないので、比べていない。
    - WMTS では、OpenLayers は同じ形式の ResourceURL をタイルごとに使い分ける。mbmap は最初のものだけを使う。
    - WMS の `TRANSPARENT` は、mbmap は仕様どおり `TRUE`、OpenLayers は `true`。大文字と小文字は区別せずに比べた。
    - ArcGIS の `dpi` の既定は、OpenLayers の 90 ではなく ArcGIS と同じ 96。
  - pack テストの `services` ページ：
    - ローカルの WMTS の能力文書から作ったソースは、地理院タイルを直接描いたものと画素まで同じだった。
    - WMS の GetMap は、入口の `map=` を残したまま送られる。
    - 例外報告、壊れた XML、ない層、http(s) でない URL、404 は、何が起きたかを書いたメッセージで失敗する。
    - pack テストに `--only=名前` を足した。
  - 依存の追加（bench の devDependencies、AGENTS §8.1）：
    - `ol` 10.11.0（BSD-2-Clause、OpenLayers の保守者）と `@camptocamp/ogc-client` 2.0.2（BSD-3-Clause、camptocamp）。
    - どちらもインストールのスクリプトはなく、公開から 2 週間以上たった版。`npm audit` は 0 件。
  - 公開サービスへの到達には、環境の許可ホストが要る（docs/CLOUD.md）。この黄金テストは CI では回さない。
- **18.3**：ArcGIS VectorTileServer。
  - `arcgisSource` は VectorTileServer をベクトルのソースにする。ズームはサービスの TileJSON 風の `minzoom`・`maxzoom` を使い、なければ `minLOD`・`maxLOD` を使う。
  - `arcgisVectorStyle` と `arcgisStyle` は、Esri の `root.json` の相対 URL を絶対 URL にし、サービスのソースをタイルの URL とズームを書いたものにする。相対 URL はソースの `../../`、スプライト、グリフ。
  - MapLibre 6.16 は Esri の `root.json` をそのままでは描けない。スプライトとソースの相対 URL を拒み、TileJSON の相対 `tiles` はページのスクリプトの場所で解決する。
  - mbmap のファサードは `root.json` の URL のまま描ける。相対 URL をスタイルや TileJSON の URL で解決するため。pack テストで、書き換えたものと同じ画素になることを確かめた。
  - `npm run services:style`：World_Basemap_v2 を書き換えたスタイルで、mbmap と MapLibre 6.16 を画素で比べた。記号のレイヤーは除き、タイルは公開サービスから取る。4 場面の結果（mean / p99）と残る差：
    - z12：0.073 / 1。差は小数のズームの細い道路と海岸線。
    - z15：0.199 / 4。Esri の z15 のタイルの一部は extent 8192 で、mbmap は `TILE_EXTENT` 4096 に量子化する（VISION §4-2）。そのため縁が最大 1/16 px ずれる。
    - 回転：0.011 / 0。
    - 日本全体：0.1 / 2。差は細い線。
    - 上限は測った値のすぐ上に置き、理由を書いた。
  - mbmap が World_Basemap_v2 のスタイルから省くものは 395 件で、すべて記号のレイヤー：
    - `symbol-avoid-edges`（未描画）180
    - `symbol-spacing` の式 78
    - 線に沿った `text-rotation-alignment` 68 と `text-offset` 67
    - `text-max-width` の式 2
  - `bench/query/page.mjs` の mbmap も出典を出さないようにした（MapLibre と同じ）。出典のあるスタイルの比較で、文字の分だけ差が出ていた。
  - pack テストの直し：
    - `npm` の `style` の確認は、`line-width` を変えて戻す手順で道路のタイルを読み直すことがある。その要求が `idle` の前か後かで数が変わり、ときどき落ちていた。手順のあとで `idle` を待ってから数えるようにした。
    - `element` の右ドラッグは、慣性の 160 ms が過ぎてから離す（#116 で直した）。
  - 未解決：`npm run style:golden` の `heatmap`（mean 0.567 / p99 8、上限 0.5 / 5）と `extrusion-patterns`（0.215 / 1、上限 0.2 / 1）が、この環境では main でも上限を超える。この PR の変更の前後で同じ値なので、別に扱う。`heatmap` は `TILE_EXTENT` 8192 で 0.001 / 0 になった（下の節）。`extrusion-patterns` は残る。
- **18.4 の分け方と予算**（2026-11-07、ユーザー判断）：
  - 18.4a は JS だけでできる地物の取得。18.4b は Esri JSON と PBF の読み手を新しい `services.wasm` に置く（予算 20KB）。
  - `TILE_EXTENT` を 8192 にする件はすぐ試す（別の PR で並行して進める）。
- **18.4a**：地物の取得（`mbmap/services` 7.0KB → 8.4KB）。
  - `ogcFeatures` は OGC API - Features の items を、`next` のリンクをたどって取る。
  - `wfsFeatures` は WFS の GetFeature を GeoJSON の出力形式で取る。WFS 2.0 で `count` を渡すと STARTINDEX でページを送る。bbox は WFS 1.1 と 2.0 には EPSG:4326 の緯度・経度の順で、1.0 には経度・緯度の順で送る。
  - `arcgisFeatures` は ArcGIS のレイヤーの `query` を `f=geojson` で取る。レイヤーが `supportsPagination` なら、`exceededTransferLimit` の間 `resultOffset` で続けて取る。
  - 3 つともページを `gather` でまとめる。上限は `MAX_FEATURES`（100 万件）と `MAX_PAGES`（1 万ページ）。同じページの URL が繰り返されたら止め、`exceeded` を立てる。
  - `followView` は表示している範囲の地物で GeoJSON ソースを埋める。`moveend` で取り直し、前の要求は中止する。
  - XML の例外報告で答えたサービスは、その内容をエラーのメッセージにする。
  - `services:golden` に地物の取得を足し、49 件すべて一致した：
    - OGC API（pygeoapi の lakes、1 ページ 5 件）は、サーバーの `numberMatched` と同じ 25 件を、重複なく取った。サーバーは 1 ページを 10 件までに切るので、1 回で全部を取る要求は比べる相手にならない。ogc-client の `getCollectionItems` もページを送らない。
    - WFS（MapServer の ms:cities）は、1 ページ 3000 件で 12686 件を取り、ページを送らずに取った結果と同じだった。GetFeature の URL は ogc-client の `generateGetFeatureUrl` と同じ要求になった。bbox で取った 76 件は、すべて範囲の中にある。
    - ArcGIS（SampleWorldCities の Cities）は、1 ページ 300 件で 2232 件を取った。bbox で取った 19 件と合わせて、サーバーの `returnIdsOnly` の id と同じだった。
  - pack テストの `services` では、ローカルの 2 ページの items を `followView` でソースに入れて描いた。動かすと取り直し、止めたあとは取り直さない。
- **18.4b**：ArcGIS の `f=json` と `f=pbf` を `services.wasm`（新しいモジュールとワーカー、`services-worker.js` と合わせて 18.7KB / 20KB）で読む。`mbmap/services` は 8.4KB → 9.1KB。
  - `@formats.read_esri_json` は @terraformer/arcgis 2.2.2 の `arcgisToGeoJSON` の移植。外側の輪（時計回り）を反時計回りにし、穴は含む外側の輪へ（なければ交わる輪へ、それもなければ外側の輪に）。id は `objectIdFieldName`、`OBJECTID`、`FID` の順。envelope、輪、線、マルチポイント、点の順に見る。
  - `@formats.read_esri_pbf` は FeatureCollection.proto の `FeatureResult` を読む。座標は部分ごとに最初が絶対値で残りが差分、変換（scale、translate、左上原点なら y を反転）で戻す（arcgis-pbf-parser 0.0.4 と同じ）。Z と M は捨てる。`geometryType` を書かない結果は点（proto3 の既定値 0）。
  - 空の幾何（`"rings": []`）は、ほかの読み手と同じく null にする。terraformer は座標が空の MultiPolygon を返す。
  - `arcgisFeatures` に `format`（`"geojson"`・`"json"`・`"pbf"`）を足した。既定はレイヤーの `supportedQueryFormats` で PBF、なければ GeoJSON、なければ JSON。PBF を頼んで JSON のエラーが返ったときは JSON として読み、エラーの内容を出す。
  - `npm run esri:golden`（新設）は公開レイヤー 11 枚で 19 件すべて一致：
    - `f=json` は terraformer と完全に同じ（SampleWorldCities、USA の高速道路・州・郡、FeatureServer の点・線・面、services.arcgis.com の World Countries と USA Major Cities）。
    - `f=pbf` は 7 枚。属性と id は arcgis-pbf-parser と同じで、幾何は同じ問い合わせの `f=json` の terraformer の結果と 1e-7° 以内（量子化の分）。World Countries は 1.9MB で `f=json` の 8.7MB の 22%。
    - 壊れた入力 5 つはどれも理由を付けて断る。
  - pack テストの `services` に静的な FeatureServer を置いた。PBF を挙げるレイヤーは `f=pbf` で、JSON だけのレイヤーは `f=json` で読み、どちらも `services.wasm` で読む。
  - 依存：bench の devDependencies に @terraformer/arcgis 2.2.2（MIT）と arcgis-pbf-parser 0.0.4（Apache-2.0）を足した。どちらもインストールスクリプトなし、`npm audit` は 0 件。移植の出典は NOTICE。
- **18.5**：カメラに合わせた 1 枚画像と識別（`mbmap/services` 9.1KB → 10.1KB）。
  - 予算は 2026-11-07 のユーザー判断で 10KB → 12KB（18.5 で 101 バイト超え、18.7 の GML の分も見込む）。
  - `followImage` は表示している範囲を 1 枚の画像のソースで見せる（OpenLayers の `ImageWMS`・`ImageArcGISRest` と同じ考え方）。`moveend` ごとに、表示の EPSG:3857 の範囲をそのズームの解像度（512 画素のタイル、`pixelRatio`）で頼み直し、`updateImage` で差し替える。1 辺は 4096 画素まで。画像は `wmsImage`（GetMap）か `arcgisImage`（`export`・`exportImage`、dpi は `pixelRatio` 倍）で作る。
  - `wmsFeatureInfo` と `arcgisIdentify` はクリックした点のまわり 101 × 101 画素を問い合わせる（OpenLayers の `getFeatureInfoUrl` と同じ窓）。GetFeatureInfo の形式は既定でサービスが挙げる JSON。`identify` は EPSG:4326 で問い合わせ、結果の幾何は `services.wasm` で GeoJSON にする。
  - `wmsSource` と `arcgisSource` は GetMap・`export` の組み立てを 1 枚画像と共有するように分けた（タイルの URL は前と同じ）。
  - `services:golden` は 53 件すべて一致：1 枚画像の URL は OpenLayers の `getImageSrc`（WMS 3 つ）と arcgisRest の `getRequestUrl`（ArcGIS 3 つ）と同じ要求で、どれも画像が返った。GetFeatureInfo の URL は `getFeatureInfoUrl` と同じ要求で、サーバーは 200 を返した。SampleWorldCities の `identify` は東京で Tokyo を見つけた（ArcGIS の WMS は EPSG:3857 を挙げないので、GeoJSON の GetFeatureInfo を実際に読む確認は pack テストで行う）。
  - pack テストの `services` は、静的な GetMap の PNG を `followImage` で 600 × 400 の 1 枚画像として描き、静的な GetFeatureInfo（GeoJSON）と `identify` の答えを読む。
- **18.7b**：example（3 つの書き方とも）に「Web サービス」を足した（「データ」のタブ）。
  - URL から WMS・WMTS（`getCapabilities`）か ArcGIS（`arcgisService`）を読み、レイヤーを選んで重ねる。WMS・WMTS・ArcGIS のタイルや `export` はラスタのソース（3857 以外は `reprojected`）、FeatureServer・MapServer のレイヤーは `arcgisFeatures` の地物（データの重ねと同じ層）。VectorTileServer はスタイルごと読むものなので断る。
  - 同梱のサンプル：地理院の淡色地図の WMTS の GetCapabilities（`examples/shared/services/gsi-wmts.xml`、z5〜18）。`?local=1` ではタイルをフィクスチャーの標準地図にする。
  - 重ねたラスタは地点などのベクトルの重ねの下に入り（`firstVectorOverlay`）、背景地図や 2D・3D を切り替えても残る（`serviceLayers`）。
  - pack テストの `showcase-*`（3 つとも）：サンプルを読み、淡色地図を重ね、ソースのタイルの URL と `minzoom`、地点の下にあること、背景地図の切り替えで残ること、消せることを確かめる。HTML と Element の例の import map に `mbmap/services` を足した。
- **18.7a**：WFS の GML。18.7 は GML（18.7a）と example（18.7b）の 2 つの PR に分けた。
  - 大きさ：GML の読み手は `services-gml.js`（1,993 バイト、新しい行の予算 2.5KB）に分け、最初に GML を読むときだけ読み込む。入れたままでは `mbmap/services` が 12.2KB で予算 12KB を超えた。`mbmap/services` は 10.8KB → 11.0KB。
  - `wfsFeatures` は GeoJSON の出力形式がなければ、いちばん新しい GML（`gmlFormat`：2、3.1、3.2）を EPSG:4326 で頼み、`readGml`（`services/gml.ts`、ホストの `DOMParser`）で読む。
  - 幾何：Point、LineString、LinearRing、Curve（segments）、Polygon、Surface（patches）、Multi* とその member・members、GeometryCollection。座標は `coordinates`（cs・ts・decimal）、`pos`、`posList`（srsDimension）、`coord`。
  - 軸の順：URN と OGC の URL は座標系の順、GML 2 の `…epsg.xml#` は東が先、単なる `EPSG:4326` は頼んだ順（MapServer は WFS 1.1・2.0 で URN を頼まれると、`EPSG:4326` と書いて緯度を先に書く）。OpenLayers は単なる `EPSG:4326` をいつも緯度が先として読むので、GML 2 の経緯度を逆に読む。
  - 属性は OpenLayers の GMLBase と同じ（葉は文字列、入れ子はオブジェクト、同じ名前は配列、`fid`・`gml:id` が id）。違うのは、`boundedBy` を属性にしないこと、属性つきの要素を `{_content_}` にせず値だけにすること、`xsi:nil` を null にすること。
  - `services:golden` は 65 件すべて一致（+11）：手書きの GML 4 件（GML 2 の穴あき多角形と区切り文字、GML 3 の Surface・Curve・3 次元、CRS84、別の座標系を断る）。MapServer の WFS 2.0・1.1・1.0 の GML 6 形式（3.2 ×2、3.1.1 ×2、2.1.2、GML2）で 586 件の位置が同じ問い合わせの GeoJSON と 1e-5° で一致し、属性と id が OpenLayers 10.11.0 の WFS の読み手と一致。ArcGIS の WFS（GML 3.2）の 19 件が範囲の中。
  - pack テストの `services` は、GML だけを挙げる静的な WFS 1.1 から地物を読み、要求の SRSNAME と OUTPUTFORMAT を確かめる。
- **18.6**：Web メルカトル以外のタイルとラスタ。作りと範囲は 2026-11-07 のユーザー判断（独自のソース型で再投影、`proj.wasm` が知る座標系すべて）。
  - mbmap 独自のソース型 `reprojected`（エンジンでは `geotiff` と同じ `tiles` のない raster）。`wmtsSource` は Web メルカトルのセットがなければ EPSG の座標系のセットから、`wmsSource` は EPSG:3857 を持たないレイヤーなら `crs`（既定は EPSG:4326）の GetMap から作る。
  - タイルは `mbmap/data` のワーカーが作る（`reprojectTile`、`data-reproject.js` 1.8KB / 2KB）。3857 のタイルの画素ごとの中心を `proj.wasm` でその座標系にし、WMTS はタイルの画素より細かいうちでいちばん粗い行列の重なるタイル（64 枚まで）、WMS は範囲の画像（1 辺 2048 画素まで、2.5 画素の余白）を取り、最近傍で引く。画像は 128 枚までワーカーに残す。
  - 軸の順：WMTS の TopLeftCorner と WMS 1.3.0 の BBOX は、EPSG の地理座標系と日本の平面直角座標系（2443〜2461、6669〜6687）で北が先（`northFirst`）。CRS84 と UTM は東が先。
  - `transformRequest` はテンプレートで 1 回だけ呼び、その headers と credentials を付ける（URL の書き換えは使わない）。
  - `npm run reproject:golden`（新設、Chromium）は 32 件すべて一致。合成の WMTS（EPSG:4326 の世界、EPSG:6677 の 50〜800 m）と WMS（1.3.0 の 4326・6677・32654、1.1.1 の 4326）の画素に自分の番号を書き、z9〜z15 のタイルの全画素が proj4js 2.22.0 で求めた元の画素と一致した（画素の境目から 1e-6 画素以内は除く）。
  - `services:golden` は 54 件すべて一致（+1）。NASA GIBS の EPSG:4326 の WMTS から `reprojected` のソースができ、最初の行列が世界の左上にあり、タイルが画像で返る。
  - pack テストの `services` は、EPSG:4326 の静的な WMTS（西半分が青、東が緑）を地図に描き、両側の色を確かめる。
  - 大きさ：`mbmap/services` 10.1KB → 10.8KB、データワーカー 39.3KB → 39.8KB / 40KB（画像の取得と PNG にする部分）、表示（メイン）133.2KB → 133.3KB。
  - 残したもの：ArcGIS のキャッシュで 3857 以外のタイル方式（`arcgisSource` は `export` で 3857 にしてもらうので描ける）。`followImage` は 3857 のレイヤーだけ。双線形の補間はしない。速さは M2 で測っていない。
- **`TILE_EXTENT` を 8192 に**（2026-11-07 ユーザー判断、18.3 と並行の別 PR）：MapLibre の `EXTENT` と同じにした。位置は Int16 のまま。
  - 4096 の MVT は 2 倍するだけなので、GSI のタイルの出力は同じ。fixtures 35 枚の packed tile は前後とも計 77,448,536 バイトで、1 枚も変わらない（`bench/maplibre/style.json`）。
  - 座標は ±32767 で切る。8192 の単位で ±4 タイル分で、MapLibre の `loadGeometry`（15 ビット、±2 タイル分）より広い。
  - 破線の距離は 8192 の単位で、MapLibre の `linesofar` と同じく偶数にそろえる（半分にして切り捨て、2 倍）。`MAX_LINE_DISTANCE` は 16384（MapLibre の `MAX_LINE_DISTANCE / 2`）。4096 のタイルでは前と同じ値。
  - 2 倍や半分の換算をなくした：ラベルの y 順、`map_placed_labels`、線に沿うラベルの `TO_EXTENT`、押し出しの壁の距離と `u_height_factor`、画像ソースの角。`worker/js/mirror.test.mjs` が `symbols.mjs` と `media.ts` の `TILE_EXTENT` を確かめる。
  - GeoJSON のタイルも MapLibre と同じ 8192 で切るようになった（バッファ、許容誤差、クラスタの半径）。`npm run geojson:golden` の `maplibre` と `lineMetrics` の組を 8192 にした（0 differ。この環境では Node の既定のヒープでは main でも足りず、`--max-old-space-size` が要る）。
  - 結果（mean / p99、前 → 後）：
    - `npm run services:style` の tokyo15：0.199 / 4 → 0.006 / 0。ほかの 3 場面は同じ。
    - `npm run style:golden`：`heatmap` 0.567 / 8 → 0.001 / 0、`heatmap-state` 0.345 / 4 → 0.001 / 0、`clusters` 0.061 / 1 → 0 / 0、`cluster-properties` 0.047 / 1 → 0 / 0、`gradients` 0.053 / 1 → 0.003 / 0、`icons-lines` 0.017 / 0 → 0.001 / 0、`icons-lines-tilted` 0.033 / 1 → 0.005 / 0。ほかは同じで、`extrusion-patterns`（0.215 / 1）だけが上限を超えたまま。
    - `query`、`labels`、`raster`、`track`、`pmtiles`、`tess`、`mvt`、`cluster` の黄金テストは前後で同じ。`export` は分けて描いた画像の差の画素が 1366 → 1365。
  - 速さ（`worker:browser`、`render`）は M2 で測る必要がある。出力のバイト数は同じなので、変わらない見込み。

## Phase 17 の後の点検（2026-11-06〜）

全体をリファクタリング（AGENTS §7）とセキュリティ（§8）の目で見た。`npm audit` は 3 か所とも 0 件、Dependabot の未対応なし。

- **example の再設計（#107）**：12 節のパネルをタブ 5 つに分け、最初は地図だけを見せる（2026-11-06 ユーザー判断。1 アプリのまま、明るい色だけ）。データのタブで `mbmap/data` を example に入れた。
- **JS のセキュリティ**：高 0、中 4、低 6。すべて可用性か管理の問題で、コード実行、DOM への注入、資格情報の漏れ、プロトタイプ汚染はなかった。
  - FlatGeobuf の `index_node_size = 1` の無限ループ、`.prj` の幅の広いノードのメモリ、GeoTIFF の展開量の上限（1 回の読み込みで `8 * max`）、PMTiles のディレクトリの上限（1 アーカイブ 200 万項目）。
  - データの取得は全体で 5 分の時間切れ（アイドルの時間切れではない。256MB には約 7Mbps が要る）。
  - 残したもの：`createImageBitmap` は大きさを確かめる前に復号する。`keepBlock` は同じキーの古い長さを引かない（速さだけの問題）。
- **MoonBit のセキュリティ**：高 0、中 8、低 5。線形メモリの範囲外アクセスはなかった。
  - FlatGeobuf のオフセットの使い回しによる指数の仕事（1 ファイルの訪問はファイルのバイト数まで）、XML の `end_tag` の二次の走査、`TableBuilder` の欄の数の上限（TopoJSON と FlatGeobuf にも 3200 万）、GPX の拡張の列、KML と GPX の点の上限を読みながら確かめる、TIFF のビット数とブロックの大きさの折り返し（1 ブロック 256MB、1 ファイルのタグの値 6400 万）、Shapefile の輪の二次の処理。
  - 大きなファイルで変わること：行 × 列が 3200 万を超える FlatGeobuf と TopoJSON は断る。256MB を超える非圧縮のブロックは開くときに断る。
  - BitsPerSample のないファイルは、使わない IFD で全体を断らないよう読み、使うときに「unsupported data format」で失敗する。
- **`idle` の競合**（#109 の CI で分かった）：TileJSON や PMTiles の文書が、エンジンが落ち着いたあとに届くと、ソースが入る前に `idle` が出ていた。文書の取得とスタイルの適用を同じ待ちに入れた。`tile-sources` の確認は文書を 400 ms 遅らせ、修正なしでは失敗する。
- **3D の抜け**：2D で陰影のために読んだ標高タイルは標高のテクスチャを持たず、そのまま地形に使われて描かれなかった（`gl_draw_terrain` が飛ばす）。`set_style` で地形のソースが変わるとき、持っている `dem.heights` から上げる（`Map::raise_dem_tiles`、取り直さない）。確認はフィクスチャのある環境だけで走り、CI では飛ばす。
  - 残したもの：`request_tile` が Stale の項目を置き換えるとき `kept` が `(-1, -1)` になり、再読み込みのたびに古いタイルのバイト列をワーカーが手放さない（コードを読んだだけで未計測）。
- **MoonBit のリファクタリング**：AGENTS §7 の順に。`String::view` の 5 箇所（`clamped_view` と 1 字ずつの書き出し。`exact_view` は孤立したサロゲートで止まるので使わない）、TIFF のタグと LZW の名前、`@geom.MAX_TABLE_POINTS` / `MAX_TABLE_CELLS`、`KIND_*` を `core/kinds.mbt` に、10 の累乗と `radians` を `core` に、使われていない公開項目の削除、`tiff/window.mbt` などファイルの分割、エラーの経路のテスト。
  - `write_units` は 1 字ずつ書くので長い文字列でわずかに遅い（未計測）。
- **TS・JS と文書のリファクタリング**：`mirror.test.mjs` が Phase 17 の定数も確かめる。`crs`、`worker-client`、範囲リクエストの単体テスト、`writeInput`、`rangeReader`、`npm/scripts/build.mjs` の表、bench の共通化（`lib/args.mjs`、`data/common.mjs`）、`data_worker/js/geotiff-read.mjs` への分割、文書の更新。速さの候補はまだ試していない（M2 で測ってから）。
- **moonc 0.10.20**（2026-11-06 ユーザー判断。作業中に Mac が 0.10.19 から 0.10.20 に変わり、原因は不明）：`derive(...)` は `#derive(...)` に（59 箇所、`moon fmt` が移した）。js バックエンドの `Array[T]` は JS の配列でなくなったので、JS に配列を返す `map_warnings` は `FixedArray` に。
  - 大きさ：表示（メイン）は 128.6KB → 132.9KB（+4.2KB、予算 135KB）。js の出力が増えた。wasm は減った（表示ワーカー -0.3KB、`xml.wasm` -0.1KB ほか）。
  - 0.10.20 で黄金テスト 26 種を回した。`track:golden` だけ 1 回 exit 1 になり、続く 7 回は通った。最初の回のログはなく、原因は分からない。
- **計測**（M2、Chromium、0.10.20 の `render`、`worker:browser`、`tess:browser`、`bench/results`）：
  - 同じコード（#112）を moonc 0.10.18 と 0.10.20 でビルドし、`render` を 3 回ずつ交互に測った。`rafCpuP50`（ms、中央値）は pan 1.0 → 1.0（+5.1%）、pan-back +0.5%、zoom-in +1.6%、zoom-out +1.7%、`idle` は 147.3 → 148.3 ms（+0.7%）。差はばらつきと同じくらいで、0.10.20 の低下は見えない。
  - `worker process_tile` は 11-03 の記録と ±2.5% 以内。
  - `rafCpuP50` は 11-03 の記録（pan 0.56 ms、zoom-in 0.39 ms）より 0.10.18 でも増えている（pan 約 1.0 ms、zoom-in 0.61 ms）。moonc ではなく、その後のコードか計測環境の差で、切り分けていない。
  - `uncapped` の `rafCpuP50` は 0.12〜2.2 ms の二山に分かれ、回ごとに変わるので比べられない。
- **大きさ**：`createAttributeTable` だけで 1996 / 2000 バイト、`xml.wasm` 26.0KB、GeoTIFF 19.9KB、データワーカー 39.4KB。`xml.wasm` の予算は 26KB → 27KB に引き上げた（2026-11-06 ユーザー判断。上限の確かめで約 350 バイト増え、CI の moonc 0.10.18 で 26,031 バイト。ローカルの 0.10.19 は 48 バイト小さい）。ほかの予算は変えていない。GeoTIFF には次の機能の余地がない。

## Phase 17：データ形式（2026-11-04〜）

範囲・段階・予算は 2026-11-04 にユーザーが決めた。完了条件は、形式ごとに既存の JS 実装との黄金テストが通り、形式ごとの予算に収まること。

- **構成**：
  - 入口は新しい `mbmap/data`（`data.js`、6KB）。分析ワーカー（28.1 / 30KB）と GeoJSON ワーカー（29.3 / 30KB）には読み手の入る余裕がないので、ワーカーも新しく作る。
  - wasm は 3 つ：`data.wasm`（CSV、WKT/WKB、TopoJSON、Shapefile、FlatGeobuf、書き出し）、`xml.wasm`（KML/GPX と KML の書き出し、初めて使うときに読む）、`geotiff.wasm` 20KB（同じく遅れて読む）。
  - 予算：データワーカーは 30KB → 38KB → 40KB、`xml.wasm` は 20KB → 26KB に引き上げた（2026-11-05 ユーザー判断。40KB は 17.5 で GeoJSON の読み込みを足したとき）。17.2 でデータワーカーが 28,976 / 30,000 バイトになり、17.3（FlatGeobuf、約 4〜5KB）と 17.5（書き出し、約 2KB）が入らなかったため。`xml.wasm` は xmldom と同じ振る舞いの XML の読み手（約 10.4KB）、KML（4.5KB）、GPX（2.2KB）で 22.2KB になり、17.5 の KML の書き出し（約 3KB）も入る。分けると wasm ごとに core の約 6KB を持つので、データワーカーは 1 つのままにした。
  - 読んだデータは `@geom.Table` にし、地図の GeoJSON ソースにも `mbmap/analysis` の Dataset にもする。
- **段階**：
  - 17.1：土台と CSV（緯度経度の列、WKT の列）、WKT/WKB。比べる相手は papaparse 5.7.0、betterknown 1.2.0、wkx 0.5.0。
  - 17.2：Shapefile（zip、DBF、`.prj`）と TopoJSON。shpjs 6.2.0、topojson-client 3.1.0。4326 以外の SRID（EWKT、EWKB、CSV）も、`.prj` と同じ座標変換で 4326 にする（2026-11-05 ユーザー判断）。
  - 17.3：FlatGeobuf（HTTP の範囲リクエストと R-tree）。flatgeobuf 4.6.1。
  - 17.4：KML/KMZ と GPX。@tmcw/togeojson 7.1.3 と @xmldom/xmldom 0.9.12。
  - 17.5：書き出し（GeoJSON、CSV、KML）。`JSON.stringify`、papaparse の `unparse`、@placemarkio/tokml 0.4.0。
  - 17.6：GeoTIFF/COG。比べる相手は geotiff 3.0.5。
    - a：読み込みと解析の Grid。
    - b：3857 と 4326 の表示。
    - c：proj.wasm での投影し直しによる、どの座標系でも描く表示（ユーザー判断）。
  - 17.7：`mbmap/ui` の属性テーブルのコントローラ（並べ替え、絞り込み、ページ送り、選択を feature state に）。ほかと独立なので最初から並行して進める。
- **決めたこと**（2026-11-04）：
  - Shapefile は正しく読み、shpjs との違いは黄金テストで正規化して記録する。違いは 4 つ：外周は反時計回り、穴は内外判定で割り当てる、削除済みの行は飛ばす、日付は文字列。
  - GeoTIFF の表示はどの座標系でも描く。
  - そのほかは下調べの推奨どおり：
    - 入れ子のプロパティは JSON の文字列。
    - `.prj` の WKT は wkt-parser の TS ポートを遅れて読む。
    - 書き出しは読み込みと同じモジュール。
    - GeoTIFF の LERC と ZSTD はあとに回し、JPEG と WebP はブラウザで復号して許容範囲で比べる。
- **下調べで分かったこと**：
  - ワーカーには `DOMParser` がないので、KML と GPX には MoonBit の XML の字句解析が要る。比べる相手は togeojson と同じく xmldom にする。
  - `DecompressionStream`（deflate、deflate-raw、gzip）は非同期なので、zip の中身や TIFF のタイルは JS で展開してから wasm に渡す。
  - DBF の Shift_JIS は host の `TextDecoder` で読む。
  - 書き出す数値は host の `String(x)` で表す。
  - d3-dsv 3.0.2 は公開されたばかりなので使わない。

### 17.6c：どの座標系の GeoTIFF でも描く（#105）

- **作り**：EPSG:3857 と 4326 以外の EPSG のコードを持つファイルは、タイルの画素ごとの中心（経緯度）を 1 回の `transform_coords` でファイルの座標系にしてから引く（`data_worker/js/crs.mjs` の `transformPairs`、`proj.wasm` は初めてのときに読む）。
  - 画素ごとに変換するので、近似の格子（GDAL の既定の 0.125 画素）による誤差はない。256 画素のタイルで 65,536 点。
  - 概観図は、タイルの中心の 1 画素の幅をファイルの単位で測って選ぶ。窓は、変換した全画素の範囲。
  - `rasterInfo` の `bounds` は、ファイルの 4 辺を 32 等分した点を経緯度にしたものの範囲。`maxzoom` は中心の 1 画素を Web メルカトルのメートルで測ったもの。
  - `proj.wasm` が知らない座標系は、その EPSG のコードを添えて失敗する。EPSG のコードのないファイルは描かない（17.6b のまま）。
- **黄金テスト**（`npm run geotiff:tiles`）：58 件すべて OK（+6）。
  - 平面直角座標系 IX 系（EPSG:6677、50 m の画素、100 m の概観図つき）のファイルの z10〜z14 のタイルが、proj4js 2.22.0 で独立に引いた最近傍の画素と一致した（z10 は概観図から）。画素の境目から 1e-6 画素以内の点は、proj4js と proj.wasm の 1 mm 以内の差で隣の画素になりうるので比べない。
  - `bounds` は proj4js で変換した四隅と 1e-4 度以内、`maxzoom` は 12。
- **大きさ**（gzip -9）：GeoTIFF 19.2KB / 20KB（+0.6KB）。ほかは変わらない。
- **残したもの**：17.6b の残りのまま。投影し直す分の速さは M2 で測っていない。

### 17.6b：GeoTIFF/COG の表示（EPSG:3857 と 4326、#104）

- **書き方**（2026-11-05 ユーザー判断）：mbmap 独自のソース型 `{ type: "geotiff", url, dem?, bands?, range?, colors?, resampling?, tileSize? }`。1 帯は `range` で灰色に、`colors`（`[値, 色]`）で色の帯に。
- **作り**：
  - エンジン（`style/source.mbt`）：`geotiff` は `tiles` のない raster ソース。`dem: true` なら Terrarium の raster-dem になり、hillshade・color-relief・terrain に使える。
  - タイルは GeoJSON と同じプロバイダの経路で受け取り（`map/tiles.mbt`）、表示ワーカーがラスタか DEM のバイト列として読む。
  - ファサードは TileJSON と同じ仕組みで、ファイルのヘッダーから `bounds` と `maxzoom` を決める（`GEOTIFF` の鍵、`geotiff-source.js`、0.2KB）。
  - タイルは `mbmap/data` のワーカーが作る（`rasterTile` → `renderTile`）。
    - 画素ごとに中心を EPSG:3857 か 4326 の座標にする。
    - タイルより細かいうちでいちばん粗い画像の、必要なブロックだけを読む。
    - 最近傍か双線形で引き、色を付ける（no data は透明）。標高は Terrarium にし、PNG にする。
  - ヘッダー（8 ファイル）とブロック（32MB）は URL ごとにワーカーに残し、隣のタイルで使い回す。
- **公開した API**：`mbmap/data` の `rasterInfo` と `rasterTile`。
- **黄金テスト**（`npm run geotiff:tiles`、Chromium）：52 件すべて OK。
  - GSI の標準地図の z14 のタイル 35 枚を、概観図つきの EPSG:3857 の COG にした。z14 のタイルは元の PNG と画素単位で一致し、地図に描いても PNG のタイルの地図と画素単位で一致した（差 0）。
  - 富士山の DEM（EPSG:3857、float32）は Terrarium で 1/256 m 以内。
  - EPSG:4326 の面は、z11〜z14 のタイルが独立に書いた最近傍の参照と一致した（灰色と色の帯）。
- **pack test**：データページの地図に `geotiff` のソースを 2 つ足す（灰色の raster と、`dem: true` の hillshade）。中心の色を確かめ、`geotiff-source.js` は 1 回だけ読み込まれる。
- **大きさ**（gzip -9）：表示（メイン）128.4KB / 135KB（+0.4KB）、GeoTIFF 18.6KB / 20KB（+2.0KB）、データワーカー 38.6KB / 40KB。
- **残したもの**：
  - 1 帯の色は直線の補間だけ（MapLibre の `raster-color` にあたるものはない）。
  - 標高は Terrarium の 1/256 m 刻み。
  - DEM の範囲の外は 0 m として描く。
  - PNG に包んでから表示ワーカーで開くので、タイルごとに符号化と復号が 1 回ずつ余分にかかる。

### 17.6a：GeoTIFF/COG の読み込みと解析の Grid（#103）

- **API**（2026-11-05 ユーザー判断）：`mbmap/data` の `readRaster(input, options)` と、`mbmap/analysis` の `loadGrid(raster, { band, scale })`。
- **読み手**：geotiff 3.0.5 の `readRasters` と同じ値を返す。
  - `tiff`（純粋な MoonBit、全ターゲットでテスト）：IFD（TIFF と BigTIFF、両方のバイト順、IFD の輪は拒む）と、ブロックの復号（非圧縮、LZW、PackBits、予測子 2・3、1 バイトより狭いビット、float16）、窓への写し。
  - `geotiff_worker`（geotiff.wasm、12.8KB）はデータワーカーが初めて `readRaster` を呼ぶときに読む。
  - `data_worker/js/geotiff.mjs`（`data-geotiff.js`、3.8KB）：画像の選び方（解像度で概観図）、bbox から窓、窓に重なるブロック、Deflate は `DecompressionStream`、JPEG・WebP はブラウザ（JPEGTables をつなぐ）、リサンプリング（最近傍、双線形）。
  - URL は範囲リクエスト。最初に 64KB、IFD がその先なら足りるまで読み足す。ブロックは 64KB より近いものをまとめ、同時に 6 つまで。Blob は必要なところだけ切り出す。
  - 返す値：帯ごとの型付き配列、`bbox`・`resolution`（ジオタグがなければ null）、GeoKeys の EPSG コード、GDAL_NODATA、PixelIsPoint。
- **loadGrid**：帯を `@analysis.Grid`（`load_grid`）にし、`noData` を値なしに。`scale` は gdaldem の `-s`。`sample` は経緯度を proj.wasm で GeoTIFF の座標系にして画素から引く（`grid_sample_pixels`）。PixelIsPoint は GDAL と同じく半画素ずらす。
- **黄金テスト**（`npm run geotiff:golden`）：304 件、すべての値が一致（差 0）。
  - データは富士山の DEM（標高タイル 4 枚、512×512）と地理院地図の標準地図のタイル（RGB）。テスト用の書き手 `bench/data/tiff-write.mjs` で 28 通りのファイルにした。
    - ストリップとタイル、planar 2、LZW・Deflate・PackBits と予測子 2・3。
    - float16/32/64、int8/16/32、uint1/4/8/12/16/32、BigTIFF とビッグエンディアン。
    - 空のブロック（no data あり・なし）、ModelTransformation、EPSG:6677 と PixelIsPoint、概観図つきの COG。
  - それぞれを窓、画像の外にはみ出す窓、空の窓、帯の選択、`fillValue`、bbox、大きさの指定（最近傍と双線形）、解像度での概観図の選択で読む。
  - バイト列から 280 件（2,250 万値）、HTTP の範囲リクエストで 17 件（IFD が後ろにあるファイル、範囲に答えないサーバーも）、両方で拒むもの 7 件。
  - 範囲リクエストの数は geotiff の 1/2〜1/5（ブロックをまとめるため）。
  - 違いは 31 件で、記録どおり：
    - geotiff のバグ（ビッグエンディアンで予測子のあるファイルをリトルエンディアンとして戻す）。ビッグエンディアンのファイルは、geotiff が読むリトルエンディアンの対のファイルと比べた。
    - `width` だけを渡すと geotiff は空の帯を返す。こちらは窓の高さのまま。
    - 途中で切れたファイルは拒む。
  - テスト用の LZW の書き手は、最初は符号の幅を 1 つ早く上げていた。geotiff の復号器で往復を確かめて直した。
- **terrain:golden**（GDAL が要るので M2 で）：GDAL が書いた COG（Deflate、浮動小数点の予測子）を `readRaster` と `load_grid` で読み、gdaldem（傾斜、陰影）と gdallocationinfo（EPSG:3857 の座標で双線形）と比べる段を足した。クラウドでは走らせていない。
- **pack test**：COG を URL で全体、bbox、概観図で読む。ブラウザで作った JPEG と WebP のタイルを含む TIFF を読む（差は JPEG が最大 3、WebP は 0）。`loadGrid` の `sample` と `slope`、拒む入力も確かめる。geotiff.wasm は 1 回だけ読み込まれる。
- **大きさ**（gzip -9）：GeoTIFF 16.6KB / 20KB（geotiff.wasm と data-geotiff.js）、データワーカー 38.5KB / 40KB、`mbmap/data` 4.2KB / 6KB、`mbmap/analysis` 3.8KB / 5KB、解析ワーカー 28.6KB / 30KB。
- **bench の devDependencies**（版は固定、`npm audit` は 0 件）：geotiff 3.0.5（MIT、EOX）。依存の lerc 3.0.0、pako 2.2.0、zstddec 0.2.0、quick-lru 6.1.2、xml-utils 1.10.2、web-worker 1.5.0、parse-headers 2.0.6、@petamoriken/float16 3.9.3 も install スクリプトはない。NOTICE に書いた。
- **残したもの**：
  - LERC と ZSTD は拒む（17 の決まりどおり、あとで）。
  - YCbCr の色の変換は、ブラウザの JPEG の復号に任せる。
  - 回転のある ModelTransformation は、`loadGrid` では北が上として扱う。
  - 24 ビットの整数は読まない（geotiff も正しく読めない）。

### 17.5：書き出し（#102）

- **API**：`write(input, { format })`。`input` は `DataTable` か GeoJSON のオブジェクト、`format` は `"geojson"`・`"csv"`・`"kml"`。文字列を返す。
  - GeoJSON：`JSON.stringify(table.toGeoJSON())`。wasm のコードはない。
  - CSV（data.wasm の `@formats.write_csv`）：papaparse 5.7.0 の `unparse` と同じ。ジオメトリは点なら経度・緯度の列、ほかは WKT の列（betterknown 1.2.0 の `geoJSONToWkt` と同じ）、なければ書かない（`geometryFormat` で選べる）。同じ名前の属性の列があればその場所に書く（JS の `{...props, wkt}` と同じ）。
  - KML（xml.wasm の `@kml.write_kml`）：@placemarkio/tokml 0.4.0 の `toKML` と同じ。エスケープは tokml がまとめている xast-util-to-xml 4.0.0 のもの（`&`、`<`、属性の `"` を `&#x26;` などに、C0 の制御文字は落とす）。
  - どちらも Table のバイト列から書き、数は host の `String(x)`。
- **GeoJSON の読み込み**：GeoJSON のオブジェクトを CSV や KML にするために、data.wasm に `read_geojson`（GeoJSON ソースと同じ読み手）を足した。`read` でも `format: "geojson"`・`.geojson` が読める。
- **見つけた不具合**：`worker/js/values.mjs` の `TextDecoder` が、先頭が U+FEFF の文字列からそれを落としていた（`toGeoJSON`、表示ワーカーの属性、問い合わせ）。`ignoreBOM: true` にした。`data:golden`、`xml:golden`、`fgb:golden` は差 0 のまま。
- **黄金テスト**（`npm run write:golden`）：83 件、バイト単位で差 0。
  - GSI の 6 層と点、MultiPolygon・MultiPoint を CSV（区切り、ヘッダーなし、列の名前、WKT、ジオメトリなしの 5 通り）で 34 件 27.4MB、KML で 8 件 16.9MB。
  - 手で書いたもの：引用の要る値（引用符、区切り、CR・LF、BOM、前後の空白）、`-0`・`1e21`・`1e-7`、真偽値、null、値のない行、ジオメトリのない行、ジオメトリと同じ名前の列、行のない表（papaparse は空の行を 1 つ書く）、KML の `name`・`description`・`visibility` の真偽の扱い（`0`、`""`、`false`、null）、id（文字列、数、`0`）、`&` `<` `"` と制御文字、サロゲートペア、すべての図形、FlatGeobuf から NaN・無限大・float。
  - 点でない行を `lonlat` で書くことと、知らない `geometryFormat` は両方で拒む。
- **予算**：データワーカーは 38,106 / 40,000 バイト（+5.5KB：CSV と WKT の書き手 約 2.8KB、GeoJSON の読み込み 約 2.7KB）。38KB をわずかに超えたので 40KB に引き上げた（2026-11-05 ユーザー判断）。
  - 削ったもの：入口の列の名前の読み取りを `split` から手書きのループにして約 1.6KB、`replace_all` をやめて約 0.3KB。
  - 試してやめたもの：ジオメトリの形式を JS で決める代わりに wasm で決める（変わらず）、配列の作り方を変える（gzip の揺れの範囲）。
- **大きさ**（gzip -9）：`xml.wasm` 25,660 / 26,000（+3.0KB）、`mbmap/data` 3,842 / 6,000。
- **bench の devDependencies**（版は固定、`npm audit` は 0 件）：@placemarkio/tokml 0.4.0（MIT、tmcw、依存なし、install スクリプトなし）。NOTICE に tokml と、それがまとめている xast-util-to-xml・stringify-entities を書いた。
- **pack test**：観測点の CSV を GeoJSON・CSV に書いて読み直す、作図した GeoJSON を KML と CSV（WKT）に書いて読み直す、id、拒む入力。
- **残したもの**：書き出しは文字列で返す（ストリームはない）。KML の `description` は tokml と同じく文字列のまま書く（togeojson が読んだ HTML の説明は JSON の文字列なので、CDATA には戻らない）。CSV に id の列は書かない（papaparse の参照にない）。

### 17.3：FlatGeobuf（#101）

- **読み手**：`@formats.read_flatgeobuf`（data.wasm）。flatgeobuf 4.6.1 の `deserialize` と同じ地物にする。
  - FlatBuffers は自前で読む。どのオフセットも範囲を確かめ、誤りは残す形（`Wkb` と同じ）。地物ごとにその地物のバイトの中だけを読む。
  - 図形：すべての型、ヘッダーの型が Unknown なら地物ごと、GeometryCollection は要素ごとの行（入れ子 32 段まで）、Z・M は落とす。曲線の型は拒む。ジオメトリのない地物は行にする（flatgeobuf は例外になる）。
  - 属性：15 の型すべて。Long と ULong は flatgeobuf の `Number(BigInt)` と同じ丸め。Json は文字列のまま（入れ子は JSON の文字列という 17 の決まりどおり）、Binary は base64。文字列の先頭の BOM は `TextDecoder` と同じく落とす。
  - id は地物の番号。ヘッダーの `crs`（EPSG か org なしの code、なければ wkt を `.prj` と同じく読む）は `crs` オプションがなければ使う。
- **索引と範囲リクエスト**：`data_worker/js/fgb.mjs`（`data-fgb.js`、2.3KB / 2.5KB、FlatGeobuf を初めて読むときに読む）。
  - flatgeobuf の `streamSearch`（段ごとの範囲をまとめる）と HttpReader の読み方を写した：最初に 12,944 バイト、索引の段、256KB より近い地物は 1 回で、同時に 6 つまで。
  - 見つけた地物をヘッダーの後ろに並べ、番号と一緒に `read_flatgeobuf(ids)` に渡す。範囲リクエストに答えないサーバー（200）ならファイル全体から探す。
  - 上限：ヘッダー 10MB（flatgeobuf と同じ）、読むバイトは合わせて `MAX_INPUT_BYTES`。上の段を指す索引や同じ節を何度も指す索引は、調べる節の数の上限で拒む。
- **黄金テスト**（`npm run fgb:golden`）：648 件で差 0。
  - 内訳：GSI の 6 層（節の大きさ 16、2、索引なし、ヘッダーの型つき、flatgeobuf 自身の `serialize`）23 件 115,072 行、15 の型、すべての図形の型と Z・M、座標系 5 件（EPSG:6677 を code、org なし、WKT で。proj4 と 1e-8° 以内）、`bbox` をバイト列から 511 件、HTTP の範囲リクエストで 92 件（地物が数個の小さなファイルも）、悪意のある入力。
  - 範囲リクエストの数は flatgeobuf と同じ（ファイルごとに 15 回の `bbox` で合わせて 18〜29 回）。最初の版は最後の地物の長さを取り違え、小さなファイルで足りない範囲を読んでいた（pack test で見つけ、黄金テストに小さなファイルを足した）。
  - 違いは 12 つで、記録どおり：ジオメトリのない地物を読む、曲線を拒む、ヘッダーの大きさの誤り・ヘッダーや索引や地物の途中で切れたファイル・地物の数が大きすぎる索引・ループする索引・列のない属性を拒む（flatgeobuf はバッファの外を読むか、何も読まずに終わる）。
  - テスト用の書き手 `bench/data/fgb-write.mjs`（すべての型、索引、CRS）は flatgeobuf の builder を使う。flatgeobuf 4.6.1 の書き手は索引を書かず、欠けた属性を壊れた値で書くので（`JSON.stringify(undefined)`、NaN）、比べる相手のファイルは主にこれで作った。
- **bench の devDependencies**（版は固定、`npm audit` は 0 件）：flatgeobuf 4.6.1（BSD、bjornharrtell、install スクリプトなし。依存の flatbuffers 25.9.23、slice-source 0.4.1、@bokuweb/zstd-wasm 0.0.27、@repeaterjs/repeater 3.1.0 もなし）、flatbuffers 25.9.23（Apache-2.0、テスト用の書き手が使う）。NOTICE に書いた（flatgeobuf の LICENSE は 2 条項の BSD で、package.json は BSD-3-Clause と書く）。
- **大きさ**（gzip -9）：データワーカー 32.6KB / 38KB（+3.1KB）。`mbmap/data` 3.4KB / 6KB。
- **残したもの**：`bbox` はファイルの座標系で渡す（経緯度から変換しない）。索引のないファイルに `bbox` を渡すと拒む（flatgeobuf と同じ）。地物を順に届ける（ストリームで返す）形はない。

### 17.4：KML/KMZ と GPX（#100）

- **パッケージ**：
  - `xml`：xmldom 0.9.12 の sax の読み手と同じ振る舞いの、純粋な XML の読み手。xmldom がする立ち直り（本文の `<`、引用符のない属性、`;` のない参照）と、xmldom が止まる誤りをそのまま写した。
    - 改行をそろえ、BOM を落とす。名前空間は範囲で解決し、接頭辞は名前に残す。
    - 宣言された実体は展開しない。billion laughs のような入力も書かれたまま。
    - 上限：深さ 256、要素ごとの属性 1024、ノード 400 万。
  - `kml`：togeojson 7.1.3 の `kml()` と `gpx()` を `@geom.Table` に写した。
    - KML：Placemark（MultiGeometry は要素ごとの行、gx:Track / MultiTrack は時刻つき）、GroundOverlay（LatLonBox の回転、gx:LatLonQuad）、Style / StyleMap を simplestyle の値に（aabbggrr の色）、ExtendedData（Schema で型を付ける）、TimeStamp / TimeSpan。
    - GPX：trk（区間が複数なら MultiLineString）、rte、wpt、`_gpxType`、拡張（心拍などは `coordinateProperties`）。
    - 高さは落とす。入れ子の値は JSON の文字列。`kmlWithFolders` と TCX は範囲の外にした。
  - `xml_worker`：`xml.wasm`。データワーカーが KML/GPX を初めて読むときに読み込む。
- **KMZ**：17.2 の共通の zip の読み手で開き、`doc.kml`、なければ最初の `.kml` を読む。17.4 が先に作っていた別の zip の読み手は消し、1 つにまとめた。
- **id**：Placemark の id は `ids_out` から `toGeoJSON` の地物の `id` に入る。TopoJSON と同じ道を通る。
- **座標系**：KML と GPX は EPSG:4326 なので、座標変換の段を通らない。`crs` を渡すと拒む（無視するより誤りに気づきやすい）。
- **黄金テスト**（`npm run xml:golden`）：83 件で差 0。
  - 内訳：kml 38、gpx 8、悪意のある入力 20、GSI の地物を KML にしたもの 7（29,291 行）、GPX にしたもの 3（9,050 行）、KMZ 7。地理院地図の作図の書き方をまねた KML も入れた。
  - 違いは 6 つで、記録どおり：深さ 256 を超えるものと属性 1024 を超えるものは拒む、内部サブセットは確かめない、XML 宣言の中身は確かめない、NetworkLink は読まない。
  - `data:golden` は 860 件で差 0 のまま。
- **bench の devDependencies**（版は固定、`npm audit` は 0 件）：@tmcw/togeojson 7.1.3（BSD-2、tmcw、依存なし）、@xmldom/xmldom 0.9.12（MIT、依存なし）。どちらも install スクリプトはなく、NOTICE に書いた。
- **大きさ**（gzip -9）：
  - `xml.wasm`：22,661 / 26,000。id で約 0.5KB 増えた。最初の版は約 29KB で、削って収めた。
  - データワーカー：29,536 / 38,000。`mbmap/data`：3,281 / 6,000。
  - 試したもの：`wasm-opt -Oz` を xml.wasm にかけると 18.7KB になり、黄金テストも差 0 のままだった。AGENTS の決まりと速さの問題があるので使っていない。
- **確認**：
  - MoonBit のテストは全ターゲットで通る（470 / 474 / 501 / 470）。npm のテストは 210 件。
  - pack test は全部通った。KML を URL・File・KMZ で、GPX も読み、KML を描く。id と `crs` を拒むことも確かめる。xml.wasm は KML/GPX を初めて読むときだけ、1 回読み込まれる。
- **残したもの**：
  - Node の bench では KML を `dataReader` に通していない（通すのは pack test だけ）。
  - 複数の区間がある GPX の track の `time` という名前の拡張は落とす。
  - SimpleData のキー名が Object.prototype の名前のときなど、悪意のある入力の隅のいくつかは togeojson と合わせていない。

### 17.2：Shapefile、TopoJSON、座標変換（#99）

- **入力**：
  - `read` は URL（`.shp` なら隣の `.dbf`・`.prj`・`.cpg` も取る。404 はないものとする）、zip、File の配列（拡張子で見分ける）、`{ shp, dbf?, prj?, cpg? }` を受け取る。
  - オプション：`layer`（zip の中の Shapefile、TopoJSON のオブジェクト。既定は最初）、`encoding`、`crs`（mbmap/analysis と同じ形。`.prj` より先に効く）。
  - `DataTable` に `layer` と `layers` を足した。
- **Shapefile**：
  - 点・マルチ点・線・面と、その Z/M（Z/M は落とす）。null の図形は図形のない行、MultiPatch は拒む。
  - 時計回りの輪が外周。穴は、それを含むいちばん小さい外周に、内外判定で割り当てる。書き出しは外周を反時計回り、穴を時計回りにする。
  - DBF：C、N/F、L（`TtYy` / `FfNn`）、D（`YYYY-MM-DD` の文字列）。削除済みの行は飛ばす。
  - 文字コードの順：オプション、`.cpg`（UTF-8・SJIS・CP932・ANSI 932・Shift_JIS など）、言語ドライバの値、UTF-8。host の `TextDecoder` で読む。
  - `.shx` は使わない。
- **zip**（`npm/src/zip.ts` → `data-zip.js`。17.4 の KMZ も使う）：
  - central directory を読む。無圧縮と deflate（`DecompressionStream`）に対応する。
  - ZIP64・分割・暗号化・ほかの圧縮方式は拒む。
  - 上限：項目 10,000、展開後の合計 256MB。宣言より大きく展開されたものも拒む。
  - 名前は UTF-8 の印があるか正しい UTF-8 ならそのまま、それ以外は Shift_JIS として読む。
- **TopoJSON**：
  - topojson-client の `feature()` と同じ。量子化の delta 復号、`~i` の逆向きの弧、弧のつなぎ方（つなぐ弧の最初の点を落とす）。
  - Point と MultiPoint は delta なしで変換する。`id` と `properties` も持つ。
- **座標変換**：
  - proj.wasm を、4326 以外のデータを初めて読むときだけ読み込む。data.wasm には入れない。
  - 行を座標系ごとにまとめ、f64 の組で 1 回ずつ変換する。
  - 1 つの入力の中で SRID が混ざっていても、行ごとに正しく変換する。1 つの図形の中で SRID が違うものは拒む。
  - 優先する順：明示した SRID、`crs`、`.prj`、4326。proj が知らない SRID は拒む。
  - `.prj` は `npm/src/prjwkt.ts`（wkt-parser 1.6.0 の WKT1 と、proj4js の Proj と parseCode のポート）で読み、EPSG コードか CRS の定義にする。`Mercator_Auxiliary_Sphere` は 3857。WKT2 は拒み、軸の順は読まない。
- **黄金テスト**（`npm run data:golden`）：860 件で差 0。
  - 内訳：Shapefile 40 件（文字コード、`.prj`、zip を含む）、TopoJSON 19 件、SRID 6 件（6677・3857・32654 の混在。proj4 と 1e-8° で比べる）。
  - 違いは 25 あり、すべて記録どおり。ユーザーが決めた 4 つ（輪の向き、内外判定での穴の割り当て、削除済みの行、日付の文字列）は、比べる前に正規化した。
- **bench の devDependencies**（版は固定、`npm audit` は 0 件）：shpjs 6.2.0（MIT。依存の but-unzip は Apache-2.0、parsedbf は MIT）、topojson-client 3.1.0（ISC）、topojson-server 3.0.1（ISC、試験用の TopoJSON を作るだけ）。どれも install スクリプトはない。
- **大きさ**（gzip -9、前 → 後 / 予算）：
  - データワーカー：17,170 → 28,976 / 30,000（data.wasm 25.4KB、Shapefile と DBF で約 3.8KB、TopoJSON で約 4.7KB）。
  - `mbmap/data`：2,435 → 3,191 / 6,000。
  - 新しい行：`.prj` WKT 3,679 / 4,000、zip 1,214 / 2,000、座標変換 1,020 / 1,500。`.prj` は proj4 の投影名と測地系の表で 4KB 近くになった。
  - geojson.wasm・analysis.wasm・geojson-properties.wasm は 2 バイトずつ大きくなった。逆アセンブルでは、`formats` の閉包の 1 つでフィールドの並びが変わっただけで、新しい読み手は入っていない。
  - **データワーカーには約 1KB しか余裕がなかった**。予算を 38KB に引き上げた（上の「構成」）。
- **確認**：pack test は 12 ページすべて通った。`data` の確認でやったこと：
  - 平面直角 IX 系・Shift_JIS の DBF・Esri の `.prj` の `wards.zip` を URL・File・隣のファイル・`{shp, dbf}` と `crs` で読み、穴を保ったまま 1e-7° で一致させる。
  - SRID 6677 の EWKT を読む。
  - TopoJSON を描く。
  - 拒むもの（暗号化された zip、256MB の上限、知らない layer、SRID 9999）を拒む。
  - 必要なときだけ proj.wasm・prjwkt・data-zip・data-crs を読み込む。
- **残したもの**：`.shx` を使わない、印のない zip の名前は Shift_JIS とみなす、`.prj` の軸の順を読まない、WKT2 の `.prj` を拒む、遅れて読み込むものが失敗したらワーカーを作り直すまで再び試さない。

### 17.1：土台、CSV、WKT/WKB（#98）

- **入口とワーカー**：
  - `mbmap/data` の `read(input, options)` は URL・File/Blob・バイトを読み、`parse(text, { format })` は CSV・WKT・hex WKB の文字列を読む。どちらも `DataTable` を返す。
  - `DataTable` は `format`、`length`、`columns`、`toGeoJSON()`（GeoJSON ソースの `data` にできる）、`tableBytes()`。
  - `mbmap/analysis` の `load` は `tableBytes()` を持つものを受け取る。形を見るだけで、`mbmap/data` は読み込まない。座標系の指定（`crs`）も効く。
  - `data_worker`（wasm-gc）は Table のバイトを返す。Table のバイトを GeoJSON にする `tableToGeoJSON` は `wasmio/js/table.mjs` に移した。
- **CSV**（papaparse 5.7.0 のソースから決まりを写した。NOTICE に MIT の項）：
  - 区切りは推測する（`, \t | ; RS US`、最初の 10 行）。同じ見出しは `a_1` のように名前を変える。
  - `dynamicTyping` は papaparse と同じ（`true`/`false`、`""` は null、±2^53 までの数。`NaN`、`+1`、`0x10`、`1e400` は文字列のまま）。
  - 点は緯度経度の列（lat/latitude/y/緯度、lon/lng/long/longitude/x/経度）から作る。WKT か hex WKB の列（wkt/geometry/the_geom/geom）があれば、そちらを先に使う。
  - 上限：`MAX_POINTS`、`MAX_CSV_COLUMNS`、`MAX_CSV_FIELD_BYTES`、`MAX_CSV_CELLS`。
- **WKT/WKB**：EWKT、EWKB、hex、両方のバイト順、ISO と EWKB の Z/M、EMPTY、入れ子の集まり（地物ごとの行に平らにする）。
- **SRID**：4326 以外は 17.1 では拒む（0 は「指定なし」として読む）。データワーカーには proj がないので、座標変換はあとの段にする。
- **黄金テスト**（`npm run data:golden`）：796 件で差 0。
  - 手で書いた場合と、GSI の地物を CSV・WKT・WKB にした分（約 23 万行）を比べる。
  - 違いは 8 つで、比べる前に正規化して記録した。主なもの：WKT のあとの文字、`1a` のような数、WKB の後ろの余りのバイトは拒む。`POINT (1 2 3)` は読む。
- **bench の devDependencies**（版は固定）：papaparse 5.7.0（MIT、依存なし）、betterknown 1.2.0（MIT、tmcw）、wkx 0.5.0（MIT、2020 年から更新なし）。どれも install スクリプトはなく、`npm audit` は 0 件。
- **大きさ**（gzip -9）：
  - `mbmap/data` 2.4KB / 6KB、データワーカー 17.2KB / 30KB（wasm は約 15.7KB）。
  - geojson.wasm と analysis.wasm は変わらない。`mbmap/analysis` 3,425 → 3,481、分析ワーカー 28,067 → 28,102 バイト。
- **確認**：
  - MoonBit のテストは全ターゲットで通る（434 / 438 / 465 / 434）。npm のテストは 197 件。
  - `analysis:golden` はすべて一致、`geojson:golden` は差 0。
  - pack test の `data` の確認：緯度・経度の列の CSV を URL で読んで地図に描き、WKT の範囲を解析に渡して `pointsWithin`。File・バイト・hex も読む。拒むもの（http(s) でない URL、知らない形式、壊れた CSV、SRID、404）は拒む。`mbmap` が `data*` を読み込まないことも確かめる。
- **残したもの**：見出しだけでデータ行のない CSV では `columns` が空になる。

### 17.7：属性テーブルのコントローラ（#97）

- **API**：`createAttributeTable(map, { source, sourceLayer?, columns?, searchColumns?, filter?, pageSize? = 50, locale?, highlight? = "selected" | false, fitBoundsOptions? })`。
  - 状態：`columns`、`rows`（いまのページ）、`total`、`filtered`、`page`、`pages`、`pageSize`、`sort`、`query`、`selected`、`loading`、`error`。
  - 操作：`setSort`、`setQuery`、`setFilter`、`setPageSize`、`goTo` / `next` / `previous`（範囲に収める）、`select(id, { add })`、`clear`、`zoomTo`（地物の範囲に `fitBounds`）、`refresh`。
- **行**：
  - GeoJSON ソースは `getData()` の全部、vector ソースは描いているタイルの `querySourceFeatures`。どちらも id（`promoteId` か地物の id）ごとに 1 行で、タイルに分かれた地物は GeometryCollection にまとめる。
  - 並べ替えは `Intl.Collator`（`numeric: true`）。数、文字列、値なしの順で、同じ値は元の順を保つ。
  - 絞り込みは mbmap/search と同じ畳み方（NFKC、大文字と小文字、カタカナとひらがな）。
- **窓口に足したもの**（メインに +172 バイト）：
  - `sourcedata` イベント（MapLibre と違い、タイルが読み込まれても出ない）。
  - `getSource` の `promoteId`。
  - GeoJSON ソースの `getData()`。`getStyle()` で全部をコピーせずにデータを読める。
- **大きさ**（gzip -9）：
  - `createAttributeTable` だけで 1,991 / 2,000 バイト。最初の版は 2,246 バイトだったので、行ごとの外接矩形をやめ（`zoomTo` で求める）、選択を文字列で持ち、ページ送りを簡単にした。
  - `mbmap/ui` 全部で 6,876 → 8,282。メイン 127,832 → 128,004。
  - `Store` や `normalize` が大きくなると 2KB を超える。
- **例**：3 つのアプリに「地点の一覧」（名前と種別、6 行ずつ）。見出しで並べ替え、入力で絞り込み、行をクリックで選んで移動、Shift で追加。地点に `kind`（駅・名所・山）を足した。
- **確認**：
  - npm のテストは 192 件。
  - pack test の `tableChecks` を 3 つのアプリで通した：並べ替え（`Intl.Collator("ja")` と比べる）、「名所」での絞り込み、半角「ﾀﾜｰ」で東京タワー、ページの範囲、選択と feature state、`setData` で行が増えること。
  - `ui:golden` は変わらない。
- **残したもの**：
  - vector ソースは描いているタイルの分だけ。
  - id のない地物はまとめられず、選べない。
  - 例では、識別と表が同じ `selected` のキーを使う。

## 全体のレビュー（2026-11-04）

8 つの範囲（style、表示ワーカー、map と描画、core〜tess、GeoJSON と分析、幾何・座標系・測地線、npm の窓口、道具と文書）を、読むだけのサブエージェントが §7・§8 の観点で全部読んだ。指摘を 4 本の PR に分けて直す。

### R4：文書（#96）

- `Emitter` の使い回しをやめた（下の R3 の計測）。tess の線は 1 本ごとに `Emitter` を作る形に戻した。`line_emit.mbt` への分割はそのまま。
- AGENTS.md：
  - §1 に `npm test` で拡張子つきで読めるモジュールと `mirror.test.mjs`。
  - §4 の食い違いを直した：format の区切りの `text-font` / `text-color` は描いている。地形のタイルの描画は中身が変わったときだけ（`texture_signature`）。`@wasmio.input_number`。`<mb-map>` は約 1.6KB。
  - §4 に新しく足したもの：`ENTRY_*` と `EXPR_*`、`compiled_writer.mbt` と `compiled_reader.mbt`、窓口の純粋なモジュール、`.d.ts` の後処理、exports、テスト用の export。

### R3：重複・定数・分割・テスト（#95）

4 つの範囲を、それぞれ自分の worktree のサブエージェントが並行して直し、ひとつのブランチにまとめた（AGENTS §2 "Parallel work"。クラウドの `isolation: "worktree"` でも動いた）。

- **使われない公開を外した**：
  - エンジンの export `map_gpu_bytes`、`map_handler_enabled`、`map_has_image`、`map_image_names`（と `Map::gpu_bytes` などの裏側）。`map_frame_count` と `map_placed_labels` はテスト用として `engine.d.ts` に書いた。
  - `Transform::mercator_to_screen`、`ring_area`（earcut の `signed_area` を使う）、`clipper.Rect64`。
  - 非公開にしたもの：`normalize_bearing` などの core の 5 つ、`Earcut`、`DEFAULT_EXTENT`、`state_defaults`、`MAX_HILLSHADE_LIGHTS`、`LineAtlas`、`PatternAtlas`、`abbreviated_count`、`MAX_GRID_SIDE`。
  - 消したもの：`MAX_GEOJSON_BYTES`（`@wasmio.MAX_INPUT_BYTES` と同じ値）と、`symbols.mjs` の使われない export。
- **定数**：
  - 詰めたタイルの項目の語の位置は `ENTRY_*`（worker/packed.mbt）。worker.mjs は同じ順の名前で読む。
  - コンパイル済みスタイルの式のタグは `EXPR_*`（値は変えていない）。
  - 柱状タイルの形の番号は `@core.GEOM_*`、tiler のズームの上限は `MAX_ZOOM`。
  - 描画の `4096` は `create_gl` に渡す `TILE_EXTENT` に、tess の `4096` / `512` は `TILE_EXTENT` / `TILE_SIZE` に。
  - 窓口のズームとピッチの上限は camera.ts、`pmtiles://` は urls.ts、式の深さは style.ts、クリックの 3 px は events.ts。
  - アンカーの表は一つに、i16 の切り詰めは `@core.clamp_i16` に。
- **重複**：
  - 画面の光線（core の 3 か所）は `screen_ray`。終わり方の違いは残した。
  - `ease_to` と `fly_to` の前置き、破線の描画 2 つ、gl の行列と描画の前置き（`place` / `draw`）。
  - overlay の合体 3 つは `region_of` に。`host_number` と `slow_number` は `@wasmio.input_number` に。
  - 分析ワーカーの `readValue` は values.mjs から読む。f64 の書き手と、http(s) の確認もまとめた。
- **ファイルの分割**（中身はそのまま移した）：
  - earcut（穴の扱い、z-order）、tess の線（`Emitter`）、`compiled.mbt`（書き手と読み手）。
  - worker（fills、circles、query_geometry、テスト）、map のラベル（箱、`placed_labels`）、map の描画（ラスタ）。
  - `ClusterIndex`（問い合わせ）、flatqueue、geodesic の級数。
  - `index.ts` のテストできる部分（engine-style.ts、feature-state.ts、query.ts）。
- **テスト**：
  - JS と MoonBit で写した定数（`KIND_*`、`LAYER_ENTRY_WORDS`、`ENTRY_*`、ラベルの列）を突き合わせる `worker/js/mirror.test.mjs`。
  - `events.ts`、`geojson_tiles`（wasm-gc）、map の純粋な計算、ワーカーの上限（`MAX_GROUPS`、`MAX_FONTS`、`MAX_FEATURE_DASHES`）、`ByteReader::remaining`、Int32 の端の座標。
  - npm のテストは 164 → 184。
- **小さな直し**：
  - `zoom_box` がコンパイラのタプルの JS の形に頼っていた件。
  - 浮動小数のターゲットも RGBA8 も描けないときの heatmap。
  - `geojson_props_worker` の `properties` を load ごとに消す。
  - 部分のない地物の `length`。
  - パッケージの exports に `geojson-properties.wasm` と `worker-*.js` を足した。
  - `dist/*.d.ts` の相対 import を `.js` にした（`moduleResolution: nodenext` で解決できる）。
- **M2 での計測**（2026-11-04、ユーザーが測った。結果の JSON はユーザーの手元にある）：
  - `worker:browser`：Chromium −8.4%、Firefox −5.5%、WebKit ±0。
  - `tess:browser`（mbt-wasm-gc、中央値）：
    - decode + lines：Chromium 3.75–3.77 → 3.88–4.04 ms（+3〜7%）、WebKit 4.16–4.36 → 4.38–4.46 ms（+1〜5%）。
    - decode + fills + lines：Chromium 5.09 → 5.19–5.21 ms（+2〜3%）、WebKit 5.52 → 5.70 ms（+3%）。
    - Firefox は 1〜4% 速い。fills と decode だけの行は ±2% 以内。
  - `tess:node`（Node 22）：fills −6.9%、lines +4.3%、fills + lines +3.4%。合計ではほぼ同じ（+0.3〜0.5%）。
  - 線だけが遅くなったのは、`Emitter` の使い回しで V8 の最適化が効きにくくなったためとみている（推測）。AGENTS §7.5 に従い、R4 で 1 本ごとに作る形に戻した。戻したあとの `tess:browser` は、まだ測っていない。
- **ホットパスの変更**：
  - 円の点ごと、押し出しの壁ごとの配列リテラルをやめた。
  - 線の `Emitter` を使い回す（R4 で戻した）。
  - ワーカーの `put_i16` は `@core.clamp_i16` を呼ぶ（wasm-gc でインライン化されるか）。
- **試して戻したもの**：
  - 線の `Emitter` を `LineTessellator` に持たせて使い回す：M2 の `tess:browser` で線が Chromium・WebKit で 2〜7% 遅くなった（上の計測）。1 本ごとに作る形に戻した。
  - map の `VertexPaint::position` に host の `pow` を渡す：メインが 17 バイト増えた（`js_trig` は `Trig::moonbit()` で、`@math.pow` はもともと入っている）。
  - worker.mjs の `ENTRY` オブジェクト：+179 バイト。名前つきの局所変数にした。
  - 定数を埋め込んだテンプレート文字列は esbuild が畳まず、文字列のままのほうが小さかった。
- **残したもの**：
  - `join_lines` の O(n²)：出力が走査の順で決まるため。
  - `css_number`：CSS と JSON で数の書き方が違うため。
  - `media.ts` の http(s) の確認：pack test がその文を見ているため。
  - `glyph_key` と `ramp_clips` のテスト：`Map` 全体が要るため。
- **大きさ**（gzip -9、R3 の前 → 後）：
  - 減ったもの：表示（メイン）127,997 → 127,832（−165）、ラベル 9,580 → 9,544、幾何 41,877 → 41,815、測地線ワーカー 12,026 → 12,018。
  - 増えたもの：表示ワーカー 80,947 → 80,954、GeoJSON ワーカー 29,435 → 29,502、式を持つ GeoJSON ワーカー 49,198 → 49,221、分析ワーカー 28,059 → 28,067。
- **既知の問題**：`npm:pack` の `style` の確認（タイルの要求数、31 と 35）は、クラウドでは main でも 3 回に 1〜2 回落ちる。2 回続けた `setPaintProperty` の間に描画のフレームがはさまるかどうかで変わる。

### R2：正しさ（#94）

- キーつきのスプライト URL（`https://…/sprite?key=K`）は `?key=K@2x.json` になって読めなかった。MapLibre の `normalizeSpriteURL` と同じく、path に足す（`spriteUrl`、`npm/src/images.ts`）。
- `*-sort-key` と `symbol-z-order` は描いているのに「まだ描かない」と警告が出ていた。`ignored_properties` には `symbol-avoid-edges` だけが残る。
- 複数のホストを持つソースは要求の番号でホストを選んでいたため、同じタイルでも読み直すたびに別のホストになり、HTTP のキャッシュが効かなかった。MapLibre の `CanonicalTileID.url` と同じく `(x + y) % n` で選ぶ。
- PMTiles のヘッダーやディレクトリの取得に一度失敗すると、そのアーカイブはそのセッションの間使えなかった。失敗したものは覚えない。取り消されたタイルは、タイルのデータの取得も止める（ヘッダーとディレクトリはほかのタイルと共有するので止めない）。
- `ClusterIndex::children` は呼ぶたびに木全体の大きさの配列を確保していた。leaves は入れ子のクラスタごとに呼ぶので、大きなクラスタではワーカーが固まった。配列は使い回す。
- GeoJSON の `data` の URL も `transformRequest`（`"Source"`、MapLibre と同じ）を通す。ヘッダーと `credentials` はワーカーがタイルと同じ形で確かめる。

### R1：セキュリティ（#93）

- **式のコンパイル**（高）：`coalesce` の型を求め直していたため、入れ子が 1 段深くなるたびにコンパイル時間が倍になっていた（20 段 90 ms、22 段 360 ms。`MAX_EXPR_DEPTH` の 31 段では数分）。`var` の共有では 3 倍ずつ。子の型は一度だけ求め、ノード数をコンパイルしながら数えて（`var` は束縛先の大きさで）`MAX_EXPR_NODES` を超えたらすぐ止める。
- **表示ワーカーの出力の大きさ**（高）：テッセレーションの出力に上限がなく、詰めるとき（`MAX_PACKED_BYTES`）まで分からなかった。レイヤーごとの残り（`TileProcessor.budget`）を、地物の前は点の数の下限で、後は実際の頂点と index で減らす。線は丸い角で 1 点から多くの頂点を作るので、`LineBuffers::limit` で途中で止める。
- **頂点ごとの paint の大きさ**（高）：`vertices * words` が Int32 で負に回り込むと `reserve` を通り、予約の外に書けた（線形メモリの中）。掛ける前に比べる。
- **幾何の入口**（高）：バッファの距離と `arcTolerance` に上限がなく（1 回で数十億点）、無限大や巨大な座標で分割のループが 2^31 回になり、Clipper の整数を超えうる。`@overlay.refusal`（有限、±1e9 以内。測地線のバッファは経緯度で、辺の分割が 1,000 万点まで）と `buffer_refusal`（測地線 2e7 m、平面 1e9、許容誤差は距離の 1e-6 以上）を幾何ワーカーの入口で。
- **GeoJSON**：点 2,000 万（`MAX_GEOJSON_POINTS`）とプロパティの枠 3,200 万（地物 × キー、`MAX_GEOJSON_CELLS`）まで。クラスタ id が 2^26 点で回り込む件も、これで届かない。ソースの `buffer`（0〜512）、`tolerance`（0 以上）、`maxzoom`（0〜24）を窓口（`loadOptions`）とワーカー（`geojson_tiles`）の両方で。
- **スタイル**：ソースの `minzoom` / `maxzoom` は 0 以上（24 を超えれば 24、min が max を超えれば Invalid）。空の `tiles` は Invalid（`% 0` で描画ループが止まっていた）。コンパイル済みの形の読み手は stops の空の補間を拒み、配列の確保を 64 までに抑える。
- **タイルと DEM**：MVT の `extent` が 0 以下なら 4096 として読む。DEM は 2 × 2 以上（MoonBit と JS の両方）。tess の座標の差は Double で（2^31 離れると輪の向きが反転していた）。
- **`Table::from_bytes`**：空の部分と空の輪を拒み、数の上限を厳しく（地物 5 バイト、キー 4 バイト）。
- **窓口の JS**：`__proto__`、`constructor`、`toString` などのキー（ソース名、プロパティ名、旧式のフィルタ）を自分のキーとして扱う（`Object.hasOwn`、`Object.fromEntries`、`setOwn`）。それまではスタイル全体が TypeError で落ちたり、値が黙って消えたりした（全体のプロトタイプの汚染は起きない）。
- **小さなもの**：`json_string_text` の末尾の `\`（panic）、PROJ の定義の `towgs84` の数が整数か、長半径が有限か、測地線の経路の NaN のエラー文。
- **道具**：`worker:browser` が使う `bench/worker/compile_entry` を `build:moon` で作る（新しい複製では動かず、古い環境では古いコンパイラのまま動いていた）。`fetch-tiles` はハッシュの合うバイトだけを置く（合わなければ消す）。
- **大きさ**（gzip -9）：表示（メイン）127,695 → 127,989 バイト（+294）、表示ワーカー 80,559 → 80,952（+393）、GeoJSON ワーカー 29,119 → 29,313、式を持つ GeoJSON ワーカー 48,878 → 49,055、分析ワーカー 27,915 → 28,059、幾何 41,267 → 41,877、TileJSON の取り込み 411 → 462。
  - `read_geojson` に省略できる引数（点の上限）を足すと、既定の `slow_number`（core の strconv）がモジュールに入り、GeoJSON ワーカーと分析ワーカーがそれぞれ約 24KB 増えた。上限は内部の `read_points` の引数にした。エラー文に Double を埋め込んでも浮動小数の表示が入る（幾何ワーカーで約 4KB）ので、文は定数にした。
- **依存**：`npm audit` は bench、npm、examples/react とも 0 件。版はすべて exact、CI は `npm ci`、actions は SHA で固定、`setup.sh` は sha256 を照合する。Dependabot と GitHub Advisory はクラウドのセッションから読めない（**ユーザーに確認をお願いする**）。

### 残りの指摘

- **R3 で手を付けなかったもの**：pmtiles の上限（`fetchRange` の大きさ、ディレクトリの深さ）の単体テスト。
- **R4（文書）**：
  - docs/FORMATS.md：Compiled style（translate の Expr、`Accumulated` のタグ、text の 3 つの式）、Display worker messages（`paint`、`outline`、`dashPatterns` など）、Packed tile（`KIND_SYMBOL`、語の表）、CRS の節に紛れた段落。
  - AGENTS §4 の食い違い：format の `text-font` / `text-color`、地形のキャッシュ、`slow_number` の持ち主、`<mb-map>` の大きさ。
  - 各 README（npm：対応するスタイル、遅れて読むファイル、`worker-*.js` の置き場所。bench：コマンドの一覧。ルート：パッケージの表。examples）。
  - NOTICE：MapLibre から写したアトラス、color ramp、heatmap、シェーダ、`media.ts`、`custom.ts`、アイコン。
  - R3 で変わったもの：
    - FORMATS「Packed tile」の語は `ENTRY_*`、「Compiled style」のタグは `EXPR_*`（書き手と読み手は `compiled_writer.mbt` と `compiled_reader.mbt`）、「Columnar tile」の形の番号は `@core.GEOM_*`。
    - AGENTS §1：npm test のモジュールは camera.ts、urls.ts、style.ts を拡張子つきで読める。
    - AGENTS §4：
      - 新しいファイル（engine-style.ts、feature-state.ts、fills.mbt、circles.mbt、query_geometry.mbt）。
      - `@wasmio.input_number`、`geojson_tiles.load` が `trig` と `slow_number` を受け取ること。
      - mirror.test.mjs、`.d.ts` の後処理、消した export。
- **M2 で測ってから**（性能の候補。クラウドでは測れない）：
  - 描画ごとに約 20 個のオブジェクトを作り、毎回 `useProgram` を呼んでいる（`npm run render`）。
  - 起動時に約 32 のシェーダを同期でコンパイルしている（初回描画）。
  - `setData` のたびにスタイル全体をコンパイルし直す。凡例やレイヤー一覧があると、ポインタが動くたびに `getStyle()` で深くコピーする（`draw:setdata`）。
  - ワーカーがグリフをすべて覚えたうえでコピーしている（約 15MB）。
  - tess の点ごとの配列リテラル（`worker:browser`）。
  - style の評価の `Match` と `Step`。
  - overlay の merge と split が O(n²)。
  - R1 の上限の確認（地物ごとに 1〜2 回の比較）が `worker:browser` に出ないことも確かめる。

## Phase 16.8：公開スタイルの突き合わせ（Protomaps）（2026-11-04）

状態：**完了**。

- **依存**：`@protomaps/basemaps` 5.7.2（bench の devDependency、exact。配布物には入らない）。BSD-3-Clause、The Protomaps Authors（protomaps/basemaps）。依存なし、install スクリプトなし、`npm audit` 0 件。スタイルを `layers("protomaps", namedFlavor(f), { lang: "ja" })` で作る（公式の作り方。JSON を写すより版がはっきりする）。NOTICE に書いた。
- **フィクスチャ**（`bench/fixtures/protomaps`、35 タイル、約 4MB）：Protomaps の日ごとのビルド `20261103.pmtiles` から、`pmtiles`（bench に既にある 4.5.0）の範囲リクエストで GSI と同じ z14 の 7×5 を取り、manifest の sha256 で固定。日ごとのビルドはしばらくで消えるので、取れない組があってもほかの組は続けて取る（`fetch-tiles.mjs`）。クラウドのネットワークに `build.protomaps.com` を足した（docs/CLOUD.md、AGENTS §9）。
- **`npm run style:public`** に 5 つの flavor（light、dark、white、grayscale、black）× 2 カメラ（z15、z14.6・25°）を足した。記号レイヤーは外す（OpenMapTiles 系と同じ）。結果（クラウドの SwiftShader、平均 / p99）：

  | flavor | z15 | z14.6・25° |
  |---|---|---|
  | light | 0.012 / 1 | 0.006 / 0 |
  | dark | 0.022 / 1 | 0.011 / 0 |
  | white | 0.007 / 0 | 0.004 / 0 |
  | grayscale | 0.01 / 0 | 0.005 / 0 |
  | black | 0.051 / 1 | 0.025 / 1 |

  black の z15 だけ限度を 0.06 にした（暗い地に細い道の縁の差が目立つ）。
- **見つけて直したもの**（`style:compat` で Protomaps のスタイルは拒まれていた）：
  - `text-variable-anchor` の式（`places_locality` の `["step", ["zoom"], ["literal", [...]], 8, ["literal", ["center"]]]`）が「not an anchor」で不正扱いになり、スタイルごと拒まれていた。ズームの `step` で `literal` の組を返すものは読む（`TextLayout.variable_stops`、`variable_at`）。ほかの式は `Unsupported`。
  - ズームで変わる `text-padding` と `icon-padding`（一つの数）：式として持ち、ワーカーがタイルのズームで評価する（MapLibre もレイアウトはタイルのズームで評価する）。地物で変わる式は `Unsupported`。
  - `labels:golden` に場面 `zoom-layout`（3 つともズームで変わる。z14.6 で、z14 と z15 で値が違うよう段を置いた）を足し、MapLibre と一致（101 ラベル、箱の差 0）。全 56 場面一致。
- `style:compat`：Protomaps light の警告は 1（`roads_shields` の線に沿った `text-rotation-alignment: viewport`。段階案の外）。
- **MapLibre との違い**：ソースの maxzoom を超えて拡大したタイル（z15 以上で z14 のタイル）では、MapLibre はタイルを読み直してそのズームでレイアウトを評価するが、mbmap は z14 で評価する（`text-size` などほかのレイアウトと同じ）。
- **大きさ**（gzip -9）：表示（メイン）127,003 → 127,695 バイト（+692：アンカーの段と余白の式の読み取りと書き出し）、表示ワーカー 80,114 → 80,559 バイト（+445：余白の評価、段の読み取り）。
- **本線で測ってほしいもの**：`style:public`（Protomaps を含めて）と `labels:golden` を M2 の GPU とフォントで。

## Phase 16.6 の残り（2026-11-04）

状態：**完了**（下の「MapLibre との違い」「残したもの」を除く）。

- **`within`**（style-spec 26.5.0 の `within.ts` と `geometry_util.ts` を写した）：引数は GeoJSON の Polygon・MultiPolygon、それを持つ Feature、FeatureCollection（Polygon と MultiPolygon だけを集める）。点と線の地物だけが対象で、多角形の地物は false（MapLibre と同じ）。経緯度を正準タイルの座標（`getTileCoordinates`、`Math.round`）にし、点と線を世界一周分ずらして箱を合わせる（`updatePoint`）ところまで同じ。
- **`distance`**（`distance.ts`、`cheap_ruler.ts`、`classify_rings.ts`、tinyqueue 3.0.0）：Point・LineString・Polygon と Multi・Feature・FeatureCollection。分割統治のキュー（大きい距離が先に出る `compareDistPair`）、範囲の分け方、点 100・線 50 未満での総当たり、多角形どうしの箱の判定まで写した。MapLibre が例外を投げるところ（点のない地物など）は評価エラー（`Failed`）。
- **地物の形の通り道**：`FeatureContext` に `within` と `distance`（既定は false と NaN。MapLibre で正準タイルがないときと同じ）。表示ワーカーの `FeatureRef` が地物を MapLibre の `loadGeometry` と同じく 8192 単位（`@style.GEOMETRY_EXTENT`、四捨五入、15 ビットに丸め）で読み、タイルの x・y と一緒に渡す。タイルのメッセージに `x` と `y` を足し（`process_tile` / `query_tile` / `source_features` の引数も）、フィルタ、レイアウト、頂点ごとの paint、ソート、クエリで効く。計算は host の `Math`（表示ワーカー）。
  - 主スレッドで組ごとに評価する paint（記号の paint、押し出しの色、feature-state を読むレイヤー）では形がないので、`within` / `distance` を含むプロパティは `Unsupported`（警告を出して除く）。MapLibre も feature-state を更新した地物では正準タイルなしで評価する（false / NaN）ので、そこを合わせるより拒むことにした。
  - 式の主スレッドの束（`main`）にはコンパイルと読み書きだけが入り、`within` / `distance` の計算はワーカーにだけ入る（`FeatureContext` の既定の実装が呼ばないため）。
- **地物ごとの `line-dasharray`**：MapLibre の `addLineDashDependencies` と同じく、地物ごとにタイルのズーム −1・0・+1 で模様を評価する。ワーカーは項目ごとに模様の表と頂点ごとの u16 × 4（docs/FORMATS.md「Packed tile」、項目の 22・23 語目。`LAYER_ENTRY_WORDS` 21 → 23）を書き、主スレッドが模様を線のアトラスに入れて頂点ごとの `a_dash`（行 × 64 ＋ 高さ、幅、拡大中・縮小中の縁の長さ）を作る（`lineDashFeature`）。幅は MapLibre の `a_dasharray_*` が Uint16 なので切り捨てる（`[1, 1.5]` は長さ 2 として描かれる。合わせないと破線の周期が 1.25 倍違った）。地物ごとの破線のレイヤーはバッファを共有しない。feature-state を読む破線と、組ごとに描くレイヤーの地物ごとの破線は `Unsupported`。
- **`accumulated` と `clusterProperties`**：MapLibre の `getSuperclusterOptions` と同じく、演算子の名前は `[op, ["accumulated"], ["get", key]]`、map はズーム 0 で点のプロパティを、reduce はもう一方の値をプロパティとして読む。結果の NaN・エラー・色・配列は null（MapLibre の `StyleExpression.evaluate` の既定値。色と配列は MapLibre ではそのまま残る）。
  - 主スレッドがコンパイルして（エンジンの `compile_cluster_properties`）二進形式で GeoJSON ワーカーに送る（docs/FORMATS.md「Compiled style」）。`tiler` の `ClusterIndex` は geojson-vt と同じく 5 語ごとのデータとクラスタのプロパティの表を持ち、`@tiler.ClusterProperties`（map / reduce の関数）で集計する。式の評価は新しいパッケージ `cluster_props`。
  - **式を持つ GeoJSON の wasm を別に**した：式の評価（`Expr::eval`、読み手、色や文字列の演算、host の `Number` / `String` / `Intl`、`wasmio/text.mbt`）を GeoJSON ワーカーに入れると 25.6KB → 44.5KB（gzip -9）で予算 30KB を超えるため。`clusterProperties` のあるソースだけ `geojson-properties.wasm`（`geojson_props_worker`）で読み、ほかは今までの `geojson.wasm`（`geojson_worker`）。どちらも処理は移した `geojson_tiles` を包む。Worker の JS は同じで、ソースごとにどちらのモジュールかを覚える。大きさの表に行を足した（予算は仮に 50KB。**ユーザーの判断がほしい**）。
- **heatmap の feature-state**：`heatmap-weight` と `heatmap-radius` が feature-state を読むと、円と同じく組ごと（ワーカーが読む値で組を分け、地物の範囲を記録）に詰め、主スレッドが状態の範囲ごとに重みと半径を変えて核を足す。
- **大きさ**（gzip -9、main 91a4719 からの差）：表示（メイン）123,940 → 126,809 バイト（+2,869：式 3 つのコンパイルと書き出し、地物ごとの破線の描画、`compile_cluster_properties`）、表示ワーカー 71,714 → 79,967 バイト（+8,253：`distance` 約 4.4KB、`within` 約 1.9KB、地物ごとの破線、x・y）、GeoJSON ワーカー 27,606 → 29,119 バイト（+1,513：`ClusterIndex` のプロパティの扱い。予算 30KB まで 881 バイト）、式を持つ GeoJSON ワーカー 48,888 バイト（新しい行）。`distance` は組の配列（タプル）で書いたので、平らな配列にすれば縮む見込み（未着手）。
- #90（16.8）と合わせて（gzip -9）：表示（メイン）127,003 バイト、表示ワーカー 80,114 バイト、GeoJSON ワーカー 29,119 バイト、式を持つ GeoJSON ワーカー 48,888 バイト（予算 50KB は 2026-11-04 ユーザー判断）。
- **確認**（クラウドの SwiftShader）：
  - `npm run expression:golden`：式 262（新しく 19：`within` 7、`distance` 12。地物に `loadGeometry` と同じ形と正準タイルを持たせ、MapLibre の評価に canonical を渡す。host の `Math` で計算）で **差 0**、問題 0。`within` は 209〜1119 / 1879 地物が true、`distance` は 0 の地物も正の地物もある（空の比較でないことを確かめた）。
  - `npm run cluster:golden`：`clusterProperties` の組（合計、最大、数、`any`、文字列の連結、元のキーを上書きするもの。MapLibre の `getSuperclusterOptions` を geojson-vt に渡したものと比べる）を足し、6663 タイル、18161 クラスタ、94855 問い合わせで **差 0**（`clusterProperties` は js ビルドだけ。wasm-gc はハッシュ比較から外した）。
  - `npm run style:golden`：新しい場面 4 つ：`within-distance`（`within` のフィルタ、`distance` と `within` の頂点ごとの paint）平均 0.037 / p99 1、`dashes-by-feature`（道路の種別ごとの模様、丸い端、拡大中の縁）0.001 / 0、`cluster-properties`（集計した値で色と大きさ）0.047 / 1、`heatmap-state`（両方の地図に同じ feature-state を設定してから撮る。場面に `states` を足した）0.345 / 4（heatmap の場面の限度 0.5 / 5）。既存の場面は `heatmap`（0.567 / 8）と `extrusion-patterns`（0.215 / 1）が限度を少し超えるほかは通る（この 2 つは main でも同じ SwiftShader の差。破線・線・円・クラスタの場面は変わらない）。結果の JSON は戻した。
  - その他：`labels:golden` 全 55 場面一致（結果の JSON は戻した）、`query:golden` 447 / 447 一致、`geojson:golden` 8148 タイルで差 0、`npm:pack` は `style` の確認（タイルの要求数。この環境では main でも落ちる）のほかは通る。pack test と `checks/` の「未対応の式」の例を `["accumulated"]` から `["properties"]` に替えた。
  - MoonBit のテスト（全ターゲット）：`style/geometry_test.mbt`（`within` / `distance` の値、引数の誤り、組ごとの paint の拒否）、`style/cluster_test.mbt`、`style/dasharray_test.mbt`、`style/heatmap_test.mbt`、コンパイル済みの形の往復と拒否（新しいタグ 24〜26）、`cluster_props`、worker（タイルの x・y で `within` / `distance` が変わること、地物ごとの破線の詰め方、heatmap の組と範囲）。`npm test`（`sameOptions` が `clusterProperties` を比べる）。
- **MapLibre との違い**：GeoJSON ソースのタイルは 4096 単位なので、`within` / `distance` は 8192 単位の MapLibre と境目で 1 単位ずれうる（MVT は 4096 → 8192 が 2 倍なので同じ）。地物ごとの破線はタイルのズームで評価するので、ソースの maxzoom を超えて拡大したタイルでは、ズームにもよる模様の式が MapLibre（表示ズームで読み直す）と違いうる。`clusterProperties` のキーは JSON の順（MapLibre の `Object.keys` は整数のようなキーを先にする）。`distance` の座標は ±10^6 度まで（cheap-ruler の折り返しの繰り返しを有限にするため。MapLibre は上限なし）。
- **残したもの**：組ごとに描く paint（記号、押し出しの色、feature-state を読むレイヤー）の `within` / `distance`、feature-state を読む破線、組ごとに描くレイヤーの地物ごとの破線、`format` の画像の区切り（16.6 から）。
- **本線で測ってほしいもの**：`labels:golden` と `style:golden` の結果（Mac のフォントと GPU で。結果の JSON は戻した）、`worker:browser`（`within` / `distance` のないスタイルの手順は変わらない。項目の語が 2 つ増えた）、`render`。

## Phase 16.8：公開スタイルの突き合わせ（OpenMapTiles 系）（2026-11-04）

状態：**OpenMapTiles 系の 7 本は完了**。Protomaps は上の節。

- **`npm run style:public`**（`bench/style/public.mjs`）：OpenMapTiles スキーマの公開スタイル 7 本（osm-bright、positron、dark-matter、maptiler-basic、ofm-liberty、ofm-bright、ofm-positron）を、OpenFreeMap のタイル（ビルド `20261101_080013_pt`、GSI と同じ東京駅周辺の z14 7×5、約 20MB）と各スタイルのスプライトで、mbmap と MapLibre 6.16 に描かせて画素で比べる。ラベルは `labels:golden` の担当なので記号レイヤーは外し、低ズームの陰影のラスタ（`ne2_shaded`）も外す。カメラは z15（回転なし）と z14.6（25° 回転）。フィクスチャは manifest の sha256 で固定（`ofm-planet`、`sprites`。`npm run fixtures` が取る）。比べる部分は `bench/style/compare.mjs` に切り出し、`style:golden` と共通にした。
- **見つけて直したもの**：
  - ズームで変わる `*-translate`（osm-bright と ofm-bright の `building-top` が `{"stops": [[14, [0, 0]], [16, [-2, -2]]]}`）：平行移動を `[x, y]` の式（定数かズームの曲線）にした（`@style.translate_at`、主スレッドはカメラのズーム、ワーカーのクエリはクエリのズームで評価）。地物ごとの式は MapLibre と同じく拒む。osm-bright は平均 1.036 → 0.072。
  - `line-join: bevel`：MapLibre は miter の長さが `line-miter-limit`（既定 2）未満なら miter で描く（`line_bucket.ts`）。mbmap はほぼまっすぐのときだけ miter にしていた。
- **結果**（クラウドの SwiftShader、平均 / p99。限度は測った値のすぐ上）：

  | スタイル | z15 | z14.6・25° |
  |---|---|---|
  | osm-bright | 0.072 / 1 | 0.037 / 1 |
  | positron | 0.007 / 0 | 0.006 / 0 |
  | dark-matter | 0.04 / 1 | 0.036 / 1 |
  | maptiler-basic | 0.114 / 4 | 0.064 / 2 |
  | ofm-liberty | 0.102 / 2 | 0.108 / 2 |
  | ofm-bright | 0.04 / 1 | 0.01 / 0 |
  | ofm-positron | 0.007 / 0 | 0.006 / 0 |

  - 残る差は細い破線の道（`line-dasharray`、幅 1 px 前後）。source の maxzoom より深く見るとき、MapLibre はタイルを組み直し（overscale）、鋭い角を分ける距離（`sharpCornerOffset`）や破線の距離がそのズームで変わる。mbmap は z14 の形のまま。破線をなくすと maptiler-basic の道は 0.153（bevel の修正後）。
- `style:compat` の警告は 30 → 27（`fill-translate` の式が読めるようになった）。
- 大きさ（gzip -9）：表示（メイン）123,940 → 124,099 バイト（+159）、表示ワーカー 71,714 → 71,855 バイト（+141）。
- クラウドでは Node の `fetch` がプロキシを通らないので `NODE_USE_ENV_PROXY=1` が要る（`scripts/setup.sh`、docs/CLOUD.md、AGENTS.md §9。ネットワークに `tiles.openfreemap.org` と `raw.githubusercontent.com` を足した）。
- **本線で測ってほしいもの**：`style:public` を M2 の GPU で（限度を Mac の値に合わせる）。

## 点のラベルの字の位置（16.5 の残り、2026-11-04）

状態：**完了**（ズームで変わる `*-translate` と縦書きの `text-rotate` は残した。下）。

- **原因**：字の縦の位置。MapLibre の `getGlyphQuads` は、その場で描いたグリフ（`GlyphManager._createGlyph`：`top = glyphTop / 2 - 27.5`）の四角形を字形の上端から `GLYPH_PBF_BORDER + 1 = 4` 単位上に置くので、基線は整形の y から 27/24 em 下になる。`worker/js/text.mjs` は「em の 0.88 が基線より上」として 1.0883 em 下に置いていて、0.0367 em（13 px で 0.48 px）上にあった。横は合っていた（`leftAdjustment` 0.5 と四角形の余白がちょうど打ち消し合う）。`BASELINE` を MapLibre の数え方の 27/24 em にした（縦書きの列は変えていない）。
- ほかに見つけて直したもの：
  - 字の四隅を 1/4 px から 1/16 px で持つ（`OFFSET_UNITS`。MapLibre は 1/32 グリフ単位で、13 px なら 1/59 px）。範囲はアンカーから ±2048 px。
  - グリフのアトラスに MapLibre の `GlyphAtlas` と同じく 1 px の余白を周りに置き、四角形はその余白まで覆う（`label.Atlas` の `GLYPH_PADDING`）。ぼかした縁取りが SDF の端で切れなくなる。
  - `format` の `font-scale` を SDF の鋭さ（ガンマと縁取りの幅）に掛けない。MapLibre の symbol_sdf はラベルの大きさだけを使う（16.6 で掛けたのを戻した）。
- **確認**（クラウドの SwiftShader）：`npm run style:golden` の点のラベル（mean / p99）：`text` 3.253 / 74 → 0.174 / 6、`text-thin-halo` 1.085 / 39 → 0.073 / 3、`text-format` 1.828 / 58 → 0.163 / 6、`text-2x` 2.948 / 106 → 0.175 / 6、`text-lines` 0.024 / 0 → 0.002 / 0。画像全体のずれは 1/32 px 刻みで 0 になった。残りは字ごとに ±0.05 px ほどのずれと濃さの差で、原因は分かっていない。限度を測った値のすぐ上（0.2 / 7 など）にし、`gap` を外した。`npm run labels:golden` は全場面一致（箱の差 0）。結果の JSON は Linux のフォントなので戻した。
- **大きさ**（gzip -9）：表示（メイン）123,940 → 123,945 バイト、`worker-labels.js` 9,561 → 9,582 バイト（予算 10KB まで 418 バイト）、表示ワーカーは変わらない。
- **残したもの**：
  - （16.8 で対応した）ズームで変わる `*-translate`：値は `StyleLayer` の定数の組で、コンパイル済みの形でワーカーにも渡り（クエリの余白と当たり判定）、変えると style/・worker/ に触る。式（16.8）の作業と重なるので後に回した。
  - `text-writing-mode` 縦と `text-variable-anchor`：`text-rotate` がなくても、縦書きに可変アンカーを組み合わせると MapLibre と箱が最大 48 px 違う（MapLibre は 2 列に折るのに mbmap は 1 列のままのラベルがある）。`labels:golden` の `same` は箱の差を見ないので、そういう場面を足すと一致のまま `boxDiff` が出る。+90° の扱いはこの後で（mbmap は列の形で箱を回すので、列の箱が MapLibre の縦の形を 90° 回したものと同じなら回し方は同じになる）。
- **本線で測ってほしいもの**：`style:golden` の文字の場面（Mac の GPU で）。性能は変わらない見込み。

## Phase 16.5：文字（2026-11-04）

状態：**完了**（下の「残したもの」を除く）。

- **`text-font`**（地物ごとの式も）：MapLibre 6.16 がグリフをブラウザのフォントでその場で描くとき（`GlyphManager._createTinySDF`）と同じフォントにした。名前をそのまま CSS のファミリーに並べ（単語の文字がない名前だけ `CSS.escape` と同じに引用）、最後に地図の `fontFamily`（MapLibre の `sans-serif` の位置）を足す。太さと斜体は最初の名前から MapLibre と同じ規則で決める（`Thin` 100 〜 `Ultra Black` 950、最後に見つかったもの。`italic` / `oblique`）。`text-font` がないときはこれまでどおり `fontFamily` だけで描く（MapLibre の既定のスタック `Open Sans Regular,Arial Unicode MS Regular` とかなの `localIdeographFontFamily` には合わせない）。式は style-spec と同じく、文字列だけの配列は名前の並び、`get` などで始まれば式。
  - 表示ワーカー（wasm）がスタックを `@style.font_face` で CSS の書体（スタイル・太さ・ファミリー）にし、項目ごとに最大 32 の書体の表を書く（docs/FORMATS.md「Labels」）。JS はワーカーごとに書体ごとの TinySDF を持ち（最大 32、超えたら地図のフォント）、グリフの鍵は「書体の番号 × 2^21 ＋ 符号位置」。ワーカーごとに番号が違うので、タイルのメッセージに `fonts` を添え、主スレッドが書体の名前に自分の番号を振り直してアトラスの鍵にする（最大 1023）。
  - `format` の区切りの `text-font` も同じ表の番号で（255 はラベルのもの）。
- **`text-letter-spacing`**（地物ごとの式も）：MapLibre の `shapeLines` と同じく、字の送りに `間隔 × 文字の大きさ` を足し、行の長さは最後の字の送りまで（`x - spacing`）。改行の判定（`determineLineBreaks`）も間隔込みの幅で、間隔が負なら 1 行に収まっても改行を調べる。続け書きの文字（アラビア文字など）を含む文は間隔 0（MapLibre の `allowsLetterSpacing`。判定は BMP の範囲だけ）。縦書きの列と線に沿ったラベルにも効く。
- **`text-transform`**（地物ごとの式も）：MapLibre の `transformText` と同じく区切りごとに `toLocaleUpperCase` / `toLocaleLowerCase`（JS）。アラビア文字の字形の整形はしない（以前から）。
- **`text-rotate`**（地物ごとの式も）：MapLibre の `getGlyphQuads` と同じく字の四隅をアンカーの周りに回し（線に沿ったラベルは字の中心の周り）、衝突判定の箱は余白をつけた箱を回した外接矩形（`CollisionFeature`）。主スレッドが余白を足すので、ワーカーは外接矩形から余白を引いて渡す。可変アンカーのずらしは回した箱の幅と高さで決まる（MapLibre と同じ）。
- **`text-opacity`**：以前から色と縁取りに掛けていた。MapLibre と同じく 0.1 未満では描かない（`icon-opacity` も）。
- **`text-halo-blur`**（地物ごとの式も）と文字の描き方：文字の断片シェーダーを MapLibre の symbol_sdf と同じ式にした（アイコンの SDF と共通の `sdf`。縁は 0.75、ガンマ `0.105 / dpr / fontScale`、縁取りのぼかし `halo_blur × 1.19 / 8`）。以前は 1 px 幅の直線のぼかしで、ぼかしがなかった。縁取りは MapLibre と同じく、幅 1 px を超えるとき（地物ごとの幅も）と字間が負のときだけ別のパスで先に描き、ほかは文字と同じパスで重ねる。線に沿った文字は `u_gamma_scale`（cos(pitch) × 中心の距離）と頂点の w で MapLibre と同じに滑らかにする。
- **`text-translate` / `icon-translate`**（と `-anchor`）：MapLibre の `placement.ts` と同じく、配置のときに文字とアイコンをそれぞれの平行移動の分ずらした行列で投影して衝突判定し（`Pending.at` / `icon_at`、`Map::icon_translated`）、描くときも同じ行列を使う。クエリはその箱で当たる。値は定数の `[x, y]` だけ（ほかの `*-translate` と同じ）。
- **`text-overlap` / `icon-overlap`**：MapLibre の `getOverlapMode` と同じく `*-overlap` があれば `*-allow-overlap` より優先（`always` は従来の allow-overlap）。`cooperative` は、`never` の記号の箱や円にだけ当たる（`label.Grid` が箱と円ごとに `never` かを持つ。MapLibre の `overlapAllowed`）。可変アンカーの 2 回目の試しは `cooperative` で（MapLibre の `placementPasses`）。
- **`format` の区切りの `text-color`**：記号の頂点に色を持たせた（区切りに色があるときだけ、項目に 8 バイト／頂点の `colors`：RGBA と 1。頂点属性 `a_fill` と `a_section`）。色は `text-opacity` を掛け、縁取りには使わない（MapLibre と同じ）。区切りの色と書体の警告はなくなった。
- **`ignored_properties`** から `text-translate(-anchor)`、`icon-translate(-anchor)`、`text-font`、`text-letter-spacing`、`text-transform`、`text-rotate`、`text-halo-blur`、`text-overlap`、`icon-overlap` を外した（残りは 16.3 の 5 つ）。
- **大きさ**（gzip -9。main b71d928 からの差）：表示（メイン）120,984 → 122,623 バイト（+1,639：シェーダー、平行移動と cooperative の配置、書体の番号）、表示ワーカー 68,398 → 70,820 バイト（+2,422：`font_face`、新しいレイアウトの式と書き出し）、`worker-labels.js` 8,959 → 9,561 バイト（+602。予算 10KB まで 439 バイト）。
- **確認**（クラウドの SwiftShader）：
  - `npm run labels:golden`：新しい場面 13（`font-bold`、`font-by-feature`、`format-fonts`、`transform-spacing`、`spacing-negative`、`rotate`、`rotate-variable`、`translate`、`translate-viewport`、`overlap`、`icon-overlap`、`contours-spacing`、`contours-rotate`）を含めて全場面一致（箱の差 0）。書体の場面はラテン文字を混ぜた（IPAGothic に太字がないので漢字では太さが箱に出ない。太さを渡さないと `boxDiff` 0.375 になることを確かめた）。結果の JSON はフォントが Mac と違うので戻した。
  - `npm run style:golden`：新しい場面 5 つ。線に沿った文字（`text-lines`：斜体、字間、幅 2 px・ぼかし 1.5 の縁取り、傾き 45°）は mean 0.024 / p99 0（限度 0.05 / 1）で、MapLibre の symbol_sdf と画素で合う。点のラベル（`text`、`text-thin-halo`、`text-format`、`text-2x`）は mean 1.1〜3.3 / p99 39〜106：字が MapLibre より約 0.5 px 上と左にある（`worker/js/text.mjs` の字の置き方の定数。箱は一致しているので 16.5 の前からの差）。限度は測った値のすぐ上にして `gap` に書いた。
  - `npm run style:compat`（外への要求をすべて断って）：警告 321 → 30。残りは `symbol-placement` / `text-anchor` / `fill-antialias` / `fill-translate` の式と、線に沿った `text-pitch-alignment` / `text-rotation-alignment`。
- **MapLibre との違い**：既定のフォントスタックとかなの `localIdeographFontFamily`（上）、`font-faces`（スタイルのフォントファイル）は読まない、続け書きの判定は BMP だけ、点のラベルの字の 0.5 px のずれ（上）。
- **残したもの**：点のラベルの字の位置を MapLibre の `getGlyphQuads` の数え方に合わせる（labels:golden の箱は変えずに）、ズームで変わる `*-translate`、`text-variable-anchor` と `text-writing-mode` での `text-rotate` の縦書きの扱い（MapLibre は縦の形に 90° 足す）。
- **本線で測ってほしいもの**：`worker:browser`（ラベルの項目の語が増え、書体ごとの TinySDF）、`render --labels`（文字の 1 パス化で描画が減る）。

- 16.3（#87）と合わせて（gzip -9）：表示（メイン）123,940 バイト、表示ワーカー 71,714 バイト、`worker-labels.js` 9,561 バイト。

## Phase 16.3：並び順（2026-11-04）

状態：**完了**。

- **`fill-sort-key`、`line-sort-key`、`circle-sort-key`**（地物ごとの式も）：MapLibre の bucket と同じく、タイルの地物をキー（タイルのズームで評価）の小さい順に、同じキーはタイルの順のまま並べてから三角形にする（`TileProcessor::feature_order`、`@core.stable_order`）。キーのあるレイヤーは、ほかのレイヤーとバッファを共有しない。
- **円はタイルをまたいで**：MapLibre の draw_circle はキーの同じ続き（segment）をすべてのタイルから集めてキーの順に描く。ワーカーが円のレイヤーの続きを（キー、最初の index、index の数）としてパックし（項目の 19・20 語目、`LAYER_ENTRY_WORDS` は 21 に）、主スレッドが集めて並べ、範囲ごとに描く（`Map::draw_circles_by_key`）。feature-state を読む円はタイルごとのまま。
- **`symbol-z-order`**：`viewport-y` はキーを使わず（MapLibre の `sortFeaturesByKey` が偽）、タイルごとにラベルを回した画面の下から置く（`getSortedSymbolIndexes`：8192 単位のアンカーを `-bearing` で回した y を `Math.round`、同じなら地物の index の大きい方が先）。重なってよいラベル（`*-allow-overlap` か `*-ignore-placement`）は、`viewport-y` か「`auto` でキーなし」のとき、その順に上から描く（`sortFeaturesByY`、向きが変わるたびに並べ直す）。`source` はキーがあればキー順。線に沿ったラベルは描く順を並べ替えない（MapLibre は並べる）。
- **`symbol-avoid-edges`**：MapLibre 6.16 は読むだけで使わない（`symbol_style_layer_properties` にあるだけ）ので、同じく型だけ確かめて何もしない。
- **確認**（クラウドの SwiftShader）：`style:golden` に `sort-keys`（建物・道路・タイルの境をまたぐ大きな円）を足し、平均 0.101 / p99 1（限度 0.12 / 1。8 を超える画素の差は 0）。`labels:golden` に `z-order-viewport-y`（30° 回してキーあり）と `z-order-source`（負のキー、`symbol-avoid-edges`）を足し、全場面一致。`query:golden` 447 / 447。
- **大きさ**（gzip -9）：表示（メイン）120,984 → 122,401 バイト（+1,417）、表示ワーカー 68,398 → 69,418 バイト（+1,020）。並べ替えは core の汎用の sort の代わりに小さな安定なマージソート（`@core.stable_order`）にした（ワーカーで約 −0.3KB）。キーの比較で `Expr` の等価を使うと派生した比較がワーカーに入り +1.6KB だったので、キーのあるレイヤーは共有しないことにした。
- **本線で測ってほしいもの**：なし（キーのないレイヤーの手順は変わらない。項目の語が 2 つ増えた）。

## Phase 16.6：式（2026-11-04）

状態：**一部完了**（優先度の高いものから。残りは下の「未対応のまま」）。

- **足した式**（MapLibre 6.16 / style-spec 26.5.0 の定義を写した）：
  - `format`：区切りごとに `font-scale`、`text-font`、`text-color`、`vertical-align`。値は `Value::Formatted`（MapLibre の `Formatted` と同じ区切り）。MapLibre と同じく偽の値（`0`、`""`、`null`）の設定は無いものとし、区切りの後でない `{}` や `vertical-align` の不正な値は `Invalid`。`["image", ...]` の区切りは未対応（`Unsupported`）。
  - `is-supported-script`：常に true。MapLibre 6.16 はどこからも `isSupportedScript` を渡さないため（`compound_expression.ts` は引数を評価せずに true を返す）。引数の型は調べる。
  - `number-format`：`locale`、`currency`、`unit`、`min-fraction-digits`、`max-fraction-digits`。ホストの `Intl.NumberFormat` で書く（`Intl` が投げたら評価エラー）。`currency` と `unit` の両方は `Invalid`。
  - `collator` と、比較（`==` `!=` `<` `<=` `>` `>=`）の 3 つ目の引数、`resolved-locale`：ホストの `Intl.Collator`（`usage: "search"`、sensitivity は MapLibre と同じ組み合わせ）。等しさは両方が文字列のときだけ照合し、ほかは厳密な比較。順序は文字列どうしか数どうし（数は文字列にして照合）。`collator` は比較・`resolved-locale`・`let` の束縛・式の一番上にだけ置ける（ほかは MapLibre と同じく `Invalid`）。
  - `split` / `join`：style-spec 26.5.0 にある文字列の操作はこの 2 つ（JavaScript の `split` / `join`。空の区切りは UTF-16 の単位ごと）。
  - `global-state`：スタイルの `state` の既定値を読む。コンパイル時に値を埋め込む（`Assert(AnyType, [Lit(v)])`）。ファサードに MapLibre と同じ `setGlobalStateProperty(name, value)`（`null` で既定値に戻す）、`getGlobalState()`、`MapOptions.globalState` を足した。ファサードは値をスタイルの `state` の既定値にしてエンジンに渡す（`npm/src/style.ts` の `withState`、`loadedState` は MapLibre の `setGlobalState` と同じ）ので、変わったキーを読むレイヤーは `same_tiles` が違って描き直し・読み直しになる。`getStyle()` の `state` は元のまま。
- **`Intl` の通り道**：`FeatureContext` に `number_format`、`collate`、`resolved_locale`。既定は js バックエンドでは `Intl` を直接呼び（`style/intl_js.mbt`。主スレッドと bench/expr）、ほかのバックエンドでは近似（`style/intl_nonjs.mbt`。テスト用）。表示ワーカーは `@style.Intl` を `TileProcessor` に渡し、`host.intl`（`wasmio/js/host.mjs`）で文字列を 1 単位ずつ渡して呼ぶ（地物の値に NUL があっても長さで切る）。wasm に数の書式や照合の表は入らない。
- **ラベル**：ワーカーは `format` の区切りを文字列・`font-scale`・`vertical-align` で詰め（docs/FORMATS.md「Labels」のタグ 6）、`worker/js/text.mjs` が MapLibre の `shapeLines` と同じに組む：字の送りと大きさは区切りの倍率、行の高さは行の最大の倍率、`vertical-align` は行の中での位置、どれかの行の高さが `text-line-height` と違うと MapLibre と同じく揃え方（`align` の `shiftY`）が変わる。グリフの SDF の鋭さ用の大きさも倍率をかける（頂点の u16 に収めるため倍率は 0〜15）。縦書きの列では倍率を使わない。
- **MapLibre との違い**：区切りの `text-font` と `text-color` は読むが描かない（`report_ignored` が `layers[i].layout.text-field: text-font of format sections not drawn yet` などを警告する）。`text-font` はレイヤーのものも未対応（16.5）。区切りの色は記号の頂点に色を持たせる必要があり、16.2 の `text-translate` と同じシェーダーに触るので後に回した。`collator` を型の合わない場所に置いた一部（`let` で束縛して `typeof` に渡すなど）は MapLibre は拒み mbmap は評価エラー。
- **大きさ**（gzip -9）：表示（メイン）116,251 → 119,749 バイト（+3,498：7 つの式のコンパイルと評価）、表示ワーカー 63,773 → 66,869 バイト（+3,096：評価、`host.intl`、区切りの書き出し）、`worker-labels.js` 8,570 → 8,959 バイト（+389、予算 10KB まで約 1KB）。
- **確認**（クラウドの SwiftShader）：
  - `npm run expression:golden`：式 243（新しく 57：`format` 9、`is-supported-script` 3、`number-format` 10、`split` / `join` 13、`global-state` 8、`collator` と `resolved-locale` 14。`createExpression` に `globalState` を渡す）で **差 0**、問題 0。
  - `npm run labels:golden`：新しい場面 7 つ（`format`：2 行・倍率・`vertical-align`、可変アンカーと、線に沿った `contours-format`、全体を縮めた `format-scaled`、`split` / `join` / `is-supported-script` と照合のフィルタの `string-ops`、`global-state` のフィルタ、`number-format` の等高線）を含めて全場面一致（表示されるラベル、アンカー、箱、線に沿ったグリフ）。結果の JSON はフォントが Mac と違うので戻した（Mac で走らせて更新してほしい）。
  - `npm run style:golden`：新しい場面 `expressions-strings`（`global-state` の既定値の色、照合のフィルタ、`split` / `join` / `is-supported-script` の paint）は mean 0.001 / p99 0（限度 0.05 / 1）。ほかは `heatmap` と `extrusion-patterns` が限度を少し超えるが main でも同じ（SwiftShader の差）。
  - MoonBit のテスト（`style/format_test.mbt` ほか、全ターゲット）、コンパイル済みの形の往復（新しい `Op` と `Collate`）と、引数の数が合わない `Call` を読み手が拒むこと（この PR で読み手に `arity_fits` を足した。前は引数の足りない `Call(At, [])` などで範囲外の読みになりえた）。`npm test`（`hostText` の `intl`、`text.mjs` の区切り、`loadedState` / `withState`）。pack test にグローバルな状態（設定、`getGlobalState`、`null` で既定値、色が変わる）を足した。
  - 見つけたもの（この PR とは別）：線に沿ったラベルで文字列に空白があると、空白の後のグリフが MapLibre と 6px ずれる（`["concat", ["get", "alti"], " m"]` で再現。`number-format` の有無と関係しない）。黄金テストのグリフの並べ方（空白のグリフを数えるか）の違いか本当のずれかは未確認。
- **未対応のまま**（`Unsupported` で、警告を出して除く）：`within`、`distance`（地物の形とタイルの位置が評価に要る。filter はワーカー、paint の一部は主スレッドで評価するので、形を渡す仕組みから）、`accumulated` と GeoJSON の `clusterProperties`（クラスタの集計の式を GeoJSON ワーカーで評価する必要がある）、地物ごとの `line-dasharray`（線のアトラスを地物ごとに。16.2 と同じ線の描画に触る）、heatmap の paint の feature-state、`format` の画像の区切り。
- **本線で測ってほしいもの**：`labels:golden` の結果（Mac のフォントで）。性能は変わらない見込み（ラベルの組み方に区切りがないときの手順は同じ）。
- 16.2・16.4（#85）と合わせて（gzip -9）：表示（メイン）120,984 バイト、表示ワーカー 68,398 バイト、`worker-labels.js` 8,959 バイト。

## Phase 16.2・16.4：線と平行移動、円（2026-11-04）

状態：**完了**（`text-translate` と `icon-translate` を除く）。

- **`line-offset`**（地物ごとの式も）：MapLibre 6.16 の `a_offset_normal` と同じく、頂点ごとに offset が動かす向きを持たせた（`LineBuffers.offsets`、2 つの i8、`EXTRUDE_SCALE` 倍）。線の端と結合のない頂点は線分の法線、結合では miter ベクトルを長さ 2 まで（`MAX_OFFSET_MITER_LENGTH`）、miter の長さ 3〜8 で頂点の法線へ戻す（`offsetFallback`）。offset が 0 でないレイヤーだけが持ち（パックの項目の 17・18 語目、`LAYER_ENTRY_WORDS` は 19 に）、そのバッファは offset のあるレイヤーとだけ共有する（`StyleLayer::line_offsets`、`same_line_layout`）。
- **`line-gap-width`**（地物ごとの式も）と **`line-blur`**：MapLibre の線のシェーダーの outset・inset とぼかしの式に合わせた。ギャップと offset は円の stroke の不透明度と幅の枠（`SLOT_GAP_WIDTH` 4、`SLOT_OFFSET` 5）を使うので、頂点ごとの paint と定数がそのまま通る。`line-blur` と `circle-blur` は空いた枠がないので一様変数で、ズームの式まで（地物ごとの式は `Unsupported`）。
- **`*-translate` / `*-translate-anchor`**（fill、line、circle、fill-extrusion）：レイヤーのタイル行列を CSS px 分ずらす（`Map::translated`、MapLibre の `translatePosition`。`viewport` ならカメラの向きで回す）。地形のテクスチャに描くときも同じ。値は定数の `[x, y]` だけ（ズームの式は `Unsupported`）。
- **円**：`circle-blur`、`circle-pitch-scale`、`circle-pitch-alignment` を MapLibre の circle シェーダーと同じに（地図に寝かせるか画面に向けるか、距離で縮めるか画面の大きさを保つか）。
- **クエリ**：MapLibre の `queryIntersectsFeature` と同じく、クエリの形を平行移動の分ずらし（`Query::translated`。要求にカメラの向きを足した）、線は `getLineWidth`（ギャップ）と `offsetLine`、円は `circleIntersection` の 4 通りで当てる。タイルのクエリの余白（`queryPadding`）にも offset と平行移動を入れた。
- **黄金テスト**（クラウドの SwiftShader）：
  - `style:golden` に 4 場面を足した：`line-offset`（miter・bevel・round、地物ごとの offset）平均 0.029 / p99 0、`line-gap`（ギャップ、ぼかし、回転）0.018 / 0、`translate`（4 種類、map と viewport、回転）0.002 / 0、`circle-pitch`（傾き 55°、4 通りとぼかし）0 / 0。限度はどれも 0.05 / 1。
  - 既存の場面は変わらないか良くなった（`lines` 0.001 / 0）。傾けた線は以前からの差のまま（`turned` 0.558 / 18）。
  - `query:golden` に平行移動・offset・ギャップ・円の向きを入れたスタイルの 2 つの見え方（回転、傾き 50°）を足し、447 / 447 一致。
- **大きさ**（gzip -9）：表示（メイン）116,251 → 117,487 バイト（+1,236）、表示ワーカー 63,773 → 65,323 バイト（+1,550：offset の法線、クエリの offsetLine と平行移動、レイヤーの新しい欄の読み込み）。
- **残したもの**：`text-translate` と `icon-translate`（ラベルの衝突判定に入れる必要があり 16.5 で）、ズームで変わる平行移動、地物ごとの `line-blur` / `circle-blur`。
- **本線で測ってほしいもの**：`worker:browser`（offset のないレイヤーの手順は変わらない。項目の語が 2 つ増えた）と `render`。

## 大きさの対策：スタイルのコンパイルを主スレッドだけに（2026-11-04）

状態：**完了**（「方針の更新：大きさ（Phase 16）」の 1）。

- スタイルを読んで式をコンパイルするのは主スレッドだけになった。表示ワーカーには `Style::to_compiled` の二進形式（docs/FORMATS.md「Compiled style」）を `init` と `style` のメッセージで送り、ワーカーは `Style::from_compiled` で読む。クエリのフィルタ（`queryRenderedFeatures` と `querySourceFeatures`）も主スレッドでコンパイルして `write_expr` の形で送る。
- 送るのはタイルを作るのに要るものだけ：ソースの URL・`bounds`・`scheme`、hillshade・color relief・raster の paint、`terrain`・`sky`・`light`、アイコンの `layout` の JSON（`same_tiles` で使う）は送らない。
- 読み手は壊れた入力を拒む：知らないタグ、足りないバイト、残りのバイトより多い個数、後ろに余るバイト。式 1 つあたり `MAX_EXPR_NODES` 個、深さ 4 × `MAX_EXPR_DEPTH` まで（コンパイル時の上限と同じ）。
- ワーカーから JSON の読み込み（`@core.parse_json`）と `host.number` の取り込みがなくなった。
- テスト：worker のテスト（`TileProcessor::from_utf8`）はすべて JSON → `Style` → 二進 → `Style` を通るようにした。style には書いて読んだものが元と等しいこと（全レイヤー種類、全式・値の種類）、拒む場合のテストを足した。`worker:browser` などのベンチは `bench/worker/compile_entry`（ベンチ専用の wasm-gc）でスタイルをコンパイルしてから渡す。
- 大きさ（gzip -9）：表示ワーカー 96,333 → 73,381 バイト（−22,952）、表示（メイン）114,636 → 116,228 バイト（+1,592：書き出し）。見込み（ワーカー約 −22KB、主 +3〜4KB）どおり。
- 黄金テスト（クラウドの SwiftShader）：`query:golden` 320/320 一致、`labels:golden` 全場面一致、`raster:golden`・`pmtiles:golden` 一致。`style:golden` は `heatmap` と `extrusion-patterns` が限度を少し超えるが、main でも同じ数字（SwiftShader の差）。`npm:pack` はこの環境では main でも `style` の確認（タイルの要求数）で落ちる。CI で確かめる。
- **本線で測ってほしいもの**：`render`（初回描画。ワーカーがスタイルを読まなくなった分の変化）。`process_tile` の手順は変わらない。

## 方針の更新：大きさ（Phase 16）（2026-11-04、ユーザー判断）

16.1・CSS の色・16.7 の後で、表示（メイン）114.6KB / 120KB、表示ワーカー 96.3KB / 100KB。Phase 16 の残り（式、文字）で両方が予算を超える見込みだったので、内訳を測って決めた。

- **内訳**（gzip、限界寄与。d8439c1、#81 の前）：
  - 表示ワーカー 95.1KB（wasm 81.1 ＋ worker.js 14.0）。wasm のうち style の読み込みとコンパイル 20.8KB、moonbit core 9.0KB、style の評価 7.0KB、worker 7.2KB、earcut 4.9KB、クエリ 4.6KB、JSON 3.5KB、線 3.1KB、mvt/pbf 2.3KB。`Style::from_json` とフィルタの `compile` を外すと wasm は 81.1 → 53.3KB。worker.js のうちラベル（symbols・text・line-labels・tiny-sdf）7.9KB、pmtiles 1.3KB、query 0.7KB。
  - 表示（メイン）110.1KB。map 25.9KB、style 24.9KB（読み込みとコンパイル約 17、評価約 7）、ソースマップに載らない部分 20.5KB（JS バックエンドのコンストラクタなど約 14、シェーダーと GL 約 6）、TS 11.3KB、moonbit core 10.1KB、core 7.1KB、render_webgl2 5.1KB。
  - MapLibre 6.16 は主 294.3KB ＋ ワーカー 147.3KB。
- **決めたこと**：
  1. スタイルのコンパイルは主スレッドだけで行い、ワーカーにはコンパイル済みの二進形式を送る。見込みはワーカー約 −22KB、主 +3〜4KB。`compile → 書き出し → 読み込み` が元と等しいことを全バックエンドのテストで守る。ワーカーのクエリのフィルタも主スレッドでコンパイルして送る。
  2. ワーカーの JS のラベル・PMTiles・クエリを、使うときだけ動的 import する（size.mjs に行を足す）。
  3. 表示（メイン）の予算を 120KB から 135KB に。
- **やらないこと**：ワーカーの wasm を機能ごとに分けること（MoonBit は複数モジュールをリンクできず、mvt・評価・core の重複がほうが大きい）。小さな削減（js-string-builtins で −1.9KB、hashmap の統一など）は性能ベンチで確かめられるときに。

## 大きさの対策：表示ワーカーの JS を分ける（2026-11-04）

状態：**完了**（「方針の更新：大きさ（Phase 16）」の 2）。

- 表示ワーカーの JS（`worker/js/worker.mjs`）は、ラベル（`symbols.mjs` と、それが使う `text.mjs`・`line-labels.mjs`・`tiny-sdf.mjs`）、PMTiles のタイル（`pmtiles.mjs`）、クエリの結果（`query.mjs`）を動的 `import()` で使うときだけ読み込む。npm のビルドはそれぞれを `worker.js` の隣の `worker-labels.js`、`worker-pmtiles.js`、`worker-query.js` にする（esbuild のプラグインで外部の import に置き換え）。ソースのまま読む bench のページはそのまま `./symbols.mjs` などを読み、bench/render のように 1 つに束ねると中に入る。
  - ラベル：記号レイヤーのあるスタイル（`init` と `style` のメッセージの `symbols`。主スレッドの `has_labels`）なら先に読み始め、タイルは自分の出力に記号の項目があれば読み込みを待つ。待つ間はほかのタイルが wasm を使うので、出力と feature ranges を先に写しておく。
  - PMTiles：最初の `pmtiles://` のタイルで読み、待つ。読み込みの失敗はほかと同じ `tile-error`。
  - クエリ：最初の `query` で読み、その後のメッセージ（`drop`、新しいスタイル）も `ready` につないで読み込みを待たせる（順序は元のまま）。失敗は `error` と空の結果。毎タイル使う feature ranges の読み取りは `ranges.mjs` に分けて `worker.js` に残した。
  - 失敗した読み込みは覚えず、次のタイルやクエリで読み直す。
- **大きさ**（gzip -9、`npm run size`）：

  | ファイル | 前 | 後 | 予算 |
  |---|---|---|---|
  | 表示ワーカー（`worker.js` ＋ `mbmap.wasm`） | 96.3KB（`worker.js` 14.0KB） | 86.8KB（`worker.js` 4.4KB） | 100KB |
  | `worker-labels.js` | — | 8.6KB | 10KB |
  | `worker-pmtiles.js` | — | 2.0KB | 3KB |
  | `worker-query.js` | — | 0.9KB | 1.5KB |

  分けた 3 つは `values.mjs`（PMTiles は `body.mjs`）をそれぞれに持つので、合わせると元より 0.4KB ほど大きい。
- スタイルのコンパイルを主スレッドだけにしたもの（#83）と合わせて、表示ワーカーは 96,333 → 63,773 バイト、表示（メイン）は 114,636 → 116,251 バイト（ラベルを先に読むかを `init` / `style` のメッセージの `symbols` で渡す分を含む）。
- pack test が、ラベルのあるスタイルでは始めに `worker-labels.js` だけ、クエリの後で `worker-query.js`、PMTiles のソースの後で `worker-pmtiles.js` が読まれることを確かめる。`npm run labels:golden`（33 場面すべて同じ）、`pmtiles:golden`、`query:golden`（320 / 320）は変わらない。

## Phase 16.7：地形の表現（2026-11-04）

状態：**完了**。

- **hillshade の方式**（`hillshade-method`）：MapLibre 6.16 の `standard`、`basic`、`combined`、`igor`、`multidirectional` をすべて描く。シェーダーは MapLibre の hillshade.fragment.glsl をそのまま写した（方式は `u_method`、光の数は `u_count`、上限 `MAX_HILLSHADE_LIGHTS` = 8）。
  - `hillshade-illumination-direction` / `-altitude`（`numberArray`）と `hillshade-highlight-color` / `-shadow-color`（`colorArray`）は、値 1 つ（式も可）か値の並び。並びか式かは MapLibre と同じく見分ける（数だけ、または色で始まる文字列だけなら並び）。光の数は `hillshade-highlight-color` の数（MapLibre の `NUM_ILLUMINATION_SOURCES`）で、短い並びは最後の値を繰り返す（`getIlluminationProperties`）。並びを返す式は未対応。
  - `hillshade-illumination-altitude` を読むようにした（`standard` と `igor` は使わない）。`hillshade-exaggeration` が 0 なら描かない（MapLibre は勾配を作らない）。
  - 勾配のテクスチャに MapLibre と同じ 1 画素の縁を付けた（`@raster.hillshade_slopes` は `(size + 2)²`）。縁は隣のタイルの端の勾配で、隣が来るまでは自分の端を繰り返した標高から。これまでの縁なしでは、タイルの境目の半画素が MapLibre と違っていた（`basic` で平均 0.02、境目で最大 48）。
  - 陰影も、ラスタと同じく止まっているときは画素の格子に合わせて描く（`raster_matrix`、MapLibre の `aligned`）。
- **`color-relief` レイヤー**：`color-relief-color`（`["elevation"]` の `interpolate`）と `color-relief-opacity`。MapLibre の color_relief シェーダーをそのまま使う。
  - 色の段は `interpolate` の入力の値で、そこでの色（ストレートの RGBA、アップロードで premultiply）の間を線形にテクスチャで補間する（`_createColorRamp`。`interpolate` でなければ透明、段が 1 つなら 1m 上に複製）。補間の種類や色空間は段の色にだけ効く（MapLibre と同じ）。
  - 標高は DEM の符号化で RGB に詰め直したテクスチャから読む（MapLibre の `packDEMData` と `getUnpackVector`。国土地理院の `gsi` は Terrarium で詰める）。MapLibre の DEM と同じく 2 画素の縁を持ち、読み込み済みの隣（斜めも）から埋める（`backfillBorder`）。段の標高も同じ符号化で丸める。
  - `["elevation"]` は `color-relief-color` の中だけ（`heatmap-density` と同じ扱い）。`color-relief-color` は zoom もデータも読めない。
- **`resampling`**：hillshade と color relief の `resampling`、raster の `resampling`（`raster-resampling` とどちらかが `nearest` なら最近傍。MapLibre と同じ）。
- **`npm run style:golden`**：富士山の DEM（Terrarium にしたもの、ズーム 11.8 で z12 のタイルをそのまま）に 8 場面を足した。

  | 場面 | 平均 | p99 |
  |---|---|---|
  | `hillshade-standard`（影・アクセントの色） | 0 | 0 |
  | `hillshade-basic`（高さ 35°、半透明の光） | 0.001 | 0 |
  | `hillshade-combined` | 0 | 0 |
  | `hillshade-igor`（`map` に固定） | 0 | 0 |
  | `hillshade-multidirectional`（光 4 つ、高さの並びは 3 つ） | 0 | 0 |
  | `hillshade-turned`（40° 回す、`resampling: nearest`） | 0.001 | 0 |
  | `color-relief`（6 段、上端が半透明、上に `igor`） | 0 | 0 |
  | `color-relief-nearest`（不透明度 0.7、`nearest`、-20° 回す） | 0 | 0 |

  - 残る差は、斜めの隣のタイルを待たない勾配の角の 1 画素。ほかの場面は変わらない。
- **`npm run raster:golden`**：`resampling: nearest` の段を足し、10 段すべて一致。
- 大きさ：メイン 107.1 → 111.7KB（+4.6KB：シェーダー約 1.2KB、hillshade と color relief の描画と DEM の詰め直し・縁、スタイルの読み込み）、表示ワーカー 93.1 → 94.3KB（+1.2KB：スタイルの読み込み）。
- 例（`examples/`）には足していない。東京駅のあたりは平らで、段彩が見せ場にならないため。
- MapLibre との違い：並び（`numberArray` / `colorArray`）を返す式（ズームで並びを補間するもの）は未対応。光が 9 つ以上も未対応。勾配の角の画素は、斜めの隣のタイルで埋めない（以前から）。
- **本線で測ってほしいもの**：なし（タイルの処理と描画の手順は、hillshade の縁が 1 画素増えたことと、color relief のあるときだけの詰め直し以外は変わらない）。

- **16.1 と合わせて**：`hillshade-illumination-altitude` を警告の一覧（`ignored_properties`）から外した。`text-opacity` も一覧から外した（`"\{prefix}-opacity"` で読んでおり、16.1 で誤って載せていた）。

## Phase 16：CSS の色（2026-11-04）

状態：**完了**。公開スタイルの色（OSM Bright の `hsla(30, 19%, 90%, 0.4)` など）が読めずにスタイルごと拒まれていたので、`style/color.mbt` の `parse_color` を MapLibre 6.16（style-spec 26.5.0）の `parseCssColor` の移植に置き換えた。

- **読めるもの**：名前付きの色 148 個と `transparent`、16 進の 4 形式、`rgb()` / `rgba()`（数か百分率。混ぜると拒む）、`hsl()` / `hsla()`（色相に `deg` を付けてもよい）。区切りはカンマ（続く不透明度も `, a`）か空白（`/ a`）。不透明度は数か百分率。範囲の外は拒まずに切り詰め、0..255 の整数に丸めない。大文字と前後の空白は JavaScript の `toLowerCase().trim()` と同じ（Kelvin 記号 U+212A は `k`、空白は `\s` の全種）。
- **数**：MapLibre は `[\de.+-]+` の並びを `+x` で数にする（`1e2`、`+5`、`.5`、`5.` は読め、`1.2.3` は NaN で拒む）。`strconv` を入れずに同じ値を出す小さな読み手 `css_number` を書いた。有効数字 15 桁・10 の ±22 乗までは Clinger の速い道でビットまで一致。その外は最後の数ビットが違うことがある（`1e-23` など。色では実際には出ない）。`1e400` は Infinity で、色相に入れると MapLibre と同じく NaN の色になる。
- **名前の表**：「名前 空白 16 進 6 桁」を 1 行ずつ並べた 1 本の文字列（2.3KB、gzip 約 1.1KB）。名前の検索は `#`・`rgb`・`hsl` で始まらないときだけ。
- **大きさ**（gzip -9）：表示（メイン）107,124 → 108,557 バイト（+1,433）、表示ワーカー 93,108 → 94,175 バイト（+1,067。予算 100KB まで残り約 5.8KB）。増えた分のほとんどは名前の表。
- **確認**：
  - **`npm run color:golden`**（新規。`bench/style/colors.mjs`、bench/expr の js ビルドの `color_parse` と style-spec の `parseCssColor` をチャンネルごとに比べる）：7351 入力（色になるもの 6831）で **差 0**。名前（大文字、前後の空白、1 文字欠け・余り）、16 進の各長さ、区切りと単位の組み合わせ、数の書き方 50 種（`1e400`、`-0`、`0e999`、20 桁など）× 10 の位置、空白 8 種の組み合わせ、乱数の hsl / rgb 6000。速い道の外の 25 入力は 1e-15 以内（うち 4 つがビットまでは一致しない）として別に数える。
  - `npm run expression:golden`：色の式 3 件（`to-color` の既定に hsla、`match` に名前と空白区切りの rgb、`interpolate` に hsl と名前）を足して差 0 のまま。
  - MoonBit のテスト（`style/color_test.mbt`）：構文ごとと、拒む場合（区切りの混在、単位の混在、壊れた数、余計な文字）。全ターゲット。
  - style:golden は全場面が限度内、npm:pack は通過。
- **`style:compat`**（16.1 の後の main と合わせて）：8 本すべてが拒まれずに描ける（色のほか、`["linear", 1]` のような余分な引数を持つ補間の型を MapLibre と同じく受け付けるようにした。OpenFreeMap の 3 本がこれで拒まれていた）。警告は osm-bright 58、positron 49、dark-matter 44、maptiler-basic 21、ofm-liberty 51、ofm-bright 51、ofm-positron 41、demotiles 6。多いのは `text-font` 128、`text-halo-blur` 83、`text-transform` 38、`text-letter-spacing` 22。新しく見えたもの：`symbol-placement`（12）、`text-anchor`（7）、`fill-antialias`（2）の式と、線に沿った `text-pitch-alignment` / `text-rotation-alignment`（6）。

## 方針の更新：Phase 16（2026-11-04、ユーザー承認）

スタイル互換の仕上げ（2D）。未対応の扱いを方針 D（VISION §6「スタイルの互換」）にし、未対応の式とプロパティを MapLibre と同じに描く。

| 段階 | 内容 |
|---|---|
| 16.1 | 方針 D の土台：未対応のプロパティは既定値に戻し、描けないレイヤーとソースは外し、コンソールと `warning` イベントで知らせる。`strict: true` で従来どおり拒む。黙って無視していたプロパティも警告する。公開スタイルを読んで未対応の一覧を出す `npm run style:compat` |
| 16.2 | 線と平行移動：`line-offset`、`line-gap-width`、`line-blur`、全種類の `*-translate(-anchor)` |
| 16.3 | 並び順：`fill` / `line` / `circle` の `sort-key`、`symbol-z-order`、`symbol-avoid-edges` |
| 16.4 | 円：`circle-blur`、`circle-pitch-scale`、`circle-pitch-alignment` |
| 16.5 | 文字：`text-translate`・`icon-translate`（16.2 から）、`text-font`（ブラウザのフォントへ）、`text-letter-spacing`、`text-transform`、`text-rotate`、`text-opacity`、`text-halo-blur`、`text-overlap`、`icon-overlap` |
| 16.6 | 式：`format`、`number-format`、`collator`、`split` / `join`、`global-state`、`within`、`distance`、`is-supported-script`、`resolved-locale`、`accumulated` と `clusterProperties`、地物ごとの破線、heatmap の feature-state |
| 16.7 | 地形の表現：hillshade の方式（`basic`、`combined`、`igor`、`multidirectional`）、`illumination-altitude`、`resampling`、`color-relief` レイヤー |
| 16.8 | 公開スタイルの突き合わせ：同じスキーマのタイルで MapLibre と画素で比べる |

- 完了条件：公開スタイル（OpenMapTiles 系と Protomaps）を読み、警告なしで描ける。足したものはそれぞれ `style:golden` か `labels:golden` で MapLibre と比べる。
- 並行：16.1 の間に、調べもの（公開スタイルとタイルの入手先）と 16.7、CSS の色（`hsl()` など。公開スタイルの 7 本が読めない原因）を別の worktree で。16.1 の後に 16.2・16.4 と 16.6 を並行。
- 調べもの（2026-11-04）：
  - 候補のスタイル：OpenMapTiles の OSM Bright・Positron・Dark Matter・MapTiler Basic（デザインは CC-BY 4.0、コードは BSD-3-Clause）、OpenFreeMap の liberty・bright・positron、Protomaps basemaps 5.7.2（BSD-3-Clause、`layers()` 関数で生成）、Versatiles colorful（Shortbread スキーマ）、MapLibre demotiles。
  - タイル：OpenMapTiles スキーマは OpenFreeMap の日付付きタイル（東京駅の周辺を manifest で固定）、Protomaps はデイリービルドを `pmtiles extract` で切り出す。どちらも ODbL（© OpenStreetMap contributors）。
  - 使われ方：どのスタイルも `text-font` を使う。多いのは `text-halo-blur`、`text-transform`、`text-letter-spacing`、`line-gap-width`、legacy の関数（OSM Bright で約 240）、Protomaps の `format`（91）と `is-supported-script`。`circle-*`、`symbol-z-order`、`text-rotate`、`*-overlap`、`number-format`、`collator`、`within`、`distance` はどれにも出てこない。

## Phase 16.1：未対応の扱い（方針 D）（2026-11-04）

状態：**完了**。

- **読み方**：`Style::from_json(json, strict?)`。strict でなければ、`Unsupported` の出たプロパティ（`paint` / `layout` のキー、ソースのキー）を外して読み直し（`leniently`、1 つのレイヤーかソースにつき 64 回まで）、外せないもの（`filter`、`type`、レイヤーやソースそのもの）はレイヤーかソースごと外す。外したソースを使うレイヤーも外す。どれも `Style.warnings` に入る。不正な値（`Invalid`）はこれまでどおり拒む。知らないレイヤーの種類も、黙って外さず警告にした。
- **黙って無視していたプロパティ**：`ignored_properties`（30 個）。主スレッドだけが `Style::report_ignored` で警告に足す（表示ワーカーは同じ文字列を同じように読むので、レイヤーとソースのそろい方は変わらない）。各段階で対応したものから一覧を消す。
- **ファサード**：`MapOptions.strict`（既定 false）。スタイルを描いたあと、除いた内容が前と変わったときだけ、`console.warn` と `warning` イベント（`warnings`：`{path, layer, message}`。オブジェクトのスタイルはコンストラクタの中で描くので、イベントは次のマイクロタスクで出す）。legacy の変換を待つスタイルが拒まれたときに `error` にならず未処理の Promise になっていたのを直した。
- **`npm run style:compat`**：`bench/style/public-styles.mjs` の 8 本（コミットと sha256 で固定し、`bench/fixtures/styles/` に置く）を Chromium で、すべての外部への要求を断って読み、警告を種類ごとに数える（`bench/results/style-compat.json`）。
  - いまは demotiles 以外の 7 本が、`hsl()` / `hsla()` の色を読めずに拒まれる（並行の PR で MapLibre の CSS の色の読み方を移植している）。demotiles は警告 6（`text-font`、`text-halo-blur` 各 2、`line-blur`、`text-transform`）。
- **大きさ**（gzip）：表示（メイン）107.1 → 108.7KB、表示ワーカー 93.0 → 94.0KB（読み直しの処理。`ignored_properties` をワーカーから外して 0.7KB 減らした）。

## 計測：Phase 15 の後のリファクタリングの後（2026-11-04、main 45a5f3a ＋ 壁の模様の修正）

- **`worker:browser`**（`process_tile` の中央値）：Chromium 7.41ms、Firefox 10.16ms、WebKit 7.96ms。リファクタリングの前（7.65 / 10.38 / 8.12ms）とぶれの範囲で同じ。
- **`render --labels`**（vsync あり、1 フレームの CPU 時間。中央値 / 95 パーセンタイル）：
  - パン：mbmap 0.60 / 1.48ms、MapLibre 1.76 / 2.66ms。
  - ズーム：mbmap 0.49 / 0.93ms、MapLibre 1.40 / 2.88ms。
- **`render --labels --line-labels`**：パン mbmap 0.99 / 2.23ms、MapLibre 2.18 / 3.19ms。ズーム mbmap 0.65 / 1.45ms、MapLibre 2.16 / 3.58ms。
- この回はマシンが前回の計測（#75）より遅く、MapLibre も 1.59 → 1.76〜2.2ms（パン）。そこでリファクタリングの前（aa3e667）と後を交互に `render --labels` で測った：パンの mbmap は前 0.78 / 0.89ms、後 0.60 / 0.63ms。ラベルの配置の確保を減らした分（`Grid::reset`、クロージャの削除）、後の方が速い。
- **`extrusion-patterns`**：壁沿いの距離を MapLibre と同じく 8192 単位で丸める（`@tess` の `wall_distance`、シェーダで半分に）。差は 0.696 / 20 → 0.183 / 0、限度を 0.2 / 1 に。ほかの style:golden の場面は変わらない。

## リファクタリング：Phase 15 の後（TS・bench 側）（2026-11-04）

状態：**完了**。Phase 15 で足した TS・JS・bench を AGENTS.md §7 で見直した（MoonBit 側は前の節、PR #76）。

- **重複**：画像を並べ替えずに読む `createImageBitmap(..., {premultiplyAlpha: "none", colorSpaceConversion: "none"})` を worker/js/imagesize.mjs の `decodeImage` 1 つに（スプライト、`loadImage`、DEM タイル、解析の DEM の 4 か所）。`err instanceof Error ? err : new Error(String(err))` の 14 か所は `Map` の `#fail` が `unknown` を受けて 1 か所で変換する形に（media.ts も同じ `fail` を受ける）。symbols.mjs のアンカー名と揃えは text.mjs の `anchorShares` に。GeoJSON ワーカーの呼び出しは `WorkerClient` にまとめなかった（タイル・クラスタ・エラーの 3 種の返事を持つ別のプロトコルで、まとめるにはワーカー側も変える）。
- **使われない export**：legacy.ts の `isFunction`、draw/shapes.ts の `PRECISION`、dem-zoom.ts の `MAX_GRID_SIDE` を非公開に。
- **index.ts の分割**（1529 → 1359 行）：イベント（`on` / `off` / `once`、レイヤーのマウスイベントと hover）を `events.ts` の `Events` に、スタイルの画像（スプライト、`addImage` など、`loadImage`）を `style-images.ts` の `StyleImages` に、どちらも `Map` が持つ形で。`idle` を待たせる処理（TileJSON とスプライト）は `#waitFor` 1 つに。分割の分だけ gzip で +185 バイト（イベント +100、画像 +85）。
- **遅延読み込み**：`toBlob` の結合と符号化を `export.js`（368 バイト）、TileJSON の取り込み（`withTileJSON`）を `tilejson-merge.js`（411 バイト）に分け、それぞれ最初の `toBlob`、最初の文書を取りに行くときに読む。文書の来ていない `url` のソースは本体の `withoutSources` で外す。size.mjs にそれぞれの行（予算 1KB）。
- **大きさ**（gzip）：表示（メイン）107,263 → 107,122 バイト（-141。遅延読み込みと重複の整理で -326、分割で +185）。`sprite.js` +13、`media.js` -15、`pmtiles.js` +17。
- **JS と MoonBit の定数**：symbols.mjs の `SIZE_PACK` / `OFFSET_PACK`（render_webgl2/gl.mbt のシェーダ）、`ICON_COLUMN`、`ANCHOR_BYTES`、`QUAD_INDICES`（新設、`* 6` を置き換え）、line-labels.mjs の `EXTENT`（MapLibre の 8192）、worker.mjs の `MAX_RASTER_SIZE`（JS だけの値）に相手の場所を書いた。
- **テスト**（npm test 134 → 151）：`geojson-options.ts`（`loadOptions`、`sameOptions`、`clusterArgs` を import のないファイルへ。既定値と int32 の境界）、pmtiles の `headerDocument`（純粋な関数に分けた。v3、短すぎ、tileType）、`loadSprites`（sprite.ts を `./images.ts` のように拡張子つきで import して Node で読めるように。fetch を差し込んで 404、@2x、名前つきスプライト、大きすぎるシート）、geojson_worker/js/features.mjs（`__proto__` のキー）、wasmio/js/host.mjs。`npm test` に geojson_worker/js と wasmio/js のテストを足した。tsconfig に `allowImportingTsExtensions`。
- **コメント**：types.ts（`Source`、`MapOptions`）、draw/controller.ts、ui/profile.ts、examples/shared/search.js の 4 行以上の塊を 3 行以内に（`MapOptions` の詳しい説明は README に既にある）。checks/geo-tools.mjs と query/golden.mjs の Phase 番号を消した。
- **bench**：pack-test.mjs（1020 → 519 行）の query、state、tile sources、track と export、style、camera、controls、search を `bench/npm/checks/*.mjs` へ。画面の画素を読む `pixel` と `near`、`atCentre` は `checks/pixels.mjs` 1 つに（media と custom の写しもこれに。読み方は decodePng に揃えた）。
- **style:golden**：
  - `extrusion-patterns` は本来のカメラ（zoom 16、bearing 30、pitch 50）に。mean 0.696、p99 20 だった。差は壁の模様の横のずれで、壁沿いの距離を mbmap は 4096 単位で切り捨て、MapLibre は 8192 単位で丸めていた。続く PR で MapLibre に合わせ（tess/extrusion.mbt の `wall_distance`、シェーダで半分に）、0.183 / 0、限度 0.2 / 1 に。
  - スプライトの模様にも本当の透明度を入れた（dots と stripes が半透明）。`patterns` 0.074 / 2、`patterns-2x` 0.077 / 2 で限度を 0.08 / 2 に（`gap` つき）。差の大部分（約 3 万画素）は半透明の画素の 1〜2 段の丸め。残り約 700 画素の大きな差は輪郭（`fill-antialias` の模様の輪郭）のところで、輪郭を切ると 33 画素に減る。半透明の模様の塗りと輪郭が重なる辺の画素の混ぜ方が MapLibre と違う（原因は未特定）。`line-patterns` は半透明にして 0.233 → 0.143 / 1 になったので限度を 0.2 / 1 に下げた。
- **確認**：moon check / test（全ターゲット）、npm build / test / size、bench test、npm:pack を 2 回、style / labels / query / track / export / pmtiles / raster の黄金テスト。track:golden の `flank` が 1 回目だけ 319px ずれた（2 回目は 8e-10px。DEM の読み込みとの競合と思われ、このコードの変更とは関係しない）。

## リファクタリング：Phase 15 の後（MoonBit 側）（2026-11-04）

状態：**完了**。Phase 15 で足した MoonBit のコード（ラベル、アイコン、線に沿ったラベル、heatmap、render_webgl2 の GL）を AGENTS.md §7 で見直した。TS・JS・bench 側は並行する別の PR。

- **分割**（コードは変えていない）：`render_webgl2/gl.mbt`（1128 行）からシンボルの GL を `gl_symbol.mbt`、陰影・ラスタ・画像の GL を `gl_raster.mbt` へ（`gl.mbt` は 689 行。残りのほとんどは `create_gl` のシェーダ）。`map/labels.mbt` からアイコンの配置（`IconSet`、`icon_set`、`icon_of`、`joint`、`show_icon`）を `map/icons.mbt` へ、`map/render.mbt` からタイルの被覆と置き場所（`draws`、`placement`、`cover`、`pattern_tile`）を `map/draws.mbt` へ。テストもシンボルの分を `worker/labels_test.mbt`、`style/text_test.mbt` へ。
- **定数**：`QUAD_INDICES`（6、worker/js/symbols.mjs の `* 6` と対応）、`ONE_EM`（24）、`CLIP_BUFFER_PX`（256）、`HEATMAP_SCREEN_SCALE`（0.25）、`HEATMAP_RAMP_WIDTH`（256）。遠近の比（5 か所）と画面への投影（4 か所）は `perspective_ratio`、`screen_x` / `screen_y` に。`fits_on_map` の `0.5 + 0.5 * cw / center_depth` は逆向きの量（箱が距離で大きくなる率）なので別のまま。
- **重複**：アンカーの符号と揃えは `@style.TextAnchor::code` / `from_code` / `align` の 1 か所に（ワーカーの `anchor_code`、地図の `anchor_align` を消した）。`@core.ByteWriter::append` でワーカーの 1 バイトずつのコピー（ラベル、feature の範囲）をやめた。`Labels::lines` の i16 の重複した切り詰めを削除。`lay_line_glyphs` の文字とアイコンで重複していた「アンカーの次の点」と左右の判定を `LineSet::backwards` に。JS の取り出し（`f32_at`、`length_of`、`get_bool`、`get_value`、`strings_of`、`has`）を `map/dom.mbt` へ。色の RGBA 化を `rgba_of` / `Paint::rgba` に。`show_icon` は普通の関数に。
- **公開の整理**：外から使われない `Expr::reads_line_progress`、`reads_heatmap_density`、`PatternPosition::display_size`、`PatternAtlas::take_dirty`、`LineAtlas::take_dirty` を非公開に（テストは wbtest へ。`reads_*` には直接のテストを足した）。heatmap-intensity がデータや feature state を読むと `Invalid`（パス `layers[0].paint.heatmap-intensity`）になるテストを足した。
- **確保を減らした（配置と毎フレーム）**：
  - 配置の `Grid` を毎回作らず、`Map` の 1 つを `Grid::reset` で空にして使う（セルの数が同じなら配列も再利用）。
  - `place_label` のクロージャ（`q`、`fits`、`box`、`insert`）を `snap`、`fits_box`、`insert_box` に。
  - `lay_line_glyphs` のクロージャ（`hide`、`clip`）と、`LineSet::along` の `Option` のタプルをやめた（`along` は Bool を返し、点を `at_x`、`at_y`、`at_angle` に残す）。`place_line_label` の `screen` クロージャ、`fits_on_map` の配列 3 つとクロージャも。
  - `draw_icons` は `icon-size` の入力（`feature_inputs`）をタイルごとでなくレイヤーごとに 1 回読む。
  - ワーカーの `symbol_layer` と `Labels::add` の地物ごとのクロージャ（`iter().any`、`map_or`、`Option::map`）をループの関数に。
  - 計測はこの PR の後でメインのセッションが行う（対象：ラベルの多い場面の `place_labels` と、線に沿ったラベルを動かしたときの 1 フレームの CPU、`worker:browser` の記号のタイル）。
- **大きさ**：表示（メイン）107.6 → 107.3KB、表示ワーカー 93.2 → 93.0KB。
- **残したもの**：
  - `Renderer::bind` のスロット数（2/3/4/6）はプログラムごとの定数にせず、`bind` の doc に各数の意味を書いた（定数にすると呼び出しが読みにくくなる）。
  - `place_line_label` の `head`、`tail`、`path`、`circles` の配列は線のラベルごとに確保したまま（使い回すには Map に作業用の配列を持たせて引き回す必要があり、計測してから判断する）。`draw_icons` の色と数のクロージャ、`placement_order` の比較のクロージャも（メッシュやレイヤーごとで、JS の呼び出しの方が重い）。
  - worker/js/symbols.mjs の `* 6` に `QUAD_INDICES` 相当の定数を置くのは TS 側の PR に任せた。

## Phase 15 の計測：アイコンの後（2026-11-03、main b7b389c）

- **`worker:browser`**（`process_tile` の中央値）：Chromium 7.65ms、Firefox 10.38ms、WebKit 8.12ms。アイコンの前（7.61 / 10.70 / 8.20ms）とぶれの範囲で同じ。出力の大きさも変わらない。
- **`render --labels`**（vsync あり、1 フレームの CPU 時間。中央値 / 95 パーセンタイル）：
  - パン：mbmap 0.37 / 1.10ms、MapLibre 1.59 / 2.22ms。
  - ズーム：mbmap 0.23 / 0.65ms、MapLibre 1.09 / 2.11ms。
- **`render --labels --line-labels`**：
  - パン：mbmap 0.46 / 1.23ms、MapLibre 1.76 / 2.55ms。
  - ズーム：mbmap 0.37 / 0.87ms、MapLibre 1.29 / 2.57ms。
- 前回の計測より両方とも速く出ているのは、マシンの状態の違いが大きい。比べるのは同じ回の mbmap と MapLibre の比で、どれも MapLibre の 1/4 から 1/3。

## Phase 15 の後のセキュリティチェック（2026-11-03）

状態：**完了**。Phase 15 で足したもの（スプライト、画像・動画のソース、PMTiles、ラスタ、ワーカーのメッセージ）を AGENTS.md §8 で見直した。

- 【中】スプライトの索引に上限がなかった（`npm/src/images.ts` `spriteImages`）。4096² のシートに全面の項目を 2 万個並べると、テラバイト単位を確保できた。アトラスに入らない項目（幅 1022、高さ 4094 を超えるもの）は飛ばし、`MAX_SPRITE_IMAGES`（10,000）個かシートの 2 倍のバイト数で打ち切る。
- 【低】PMTiles のヘッダを読む `npm/src/pmtiles.ts` は、Range を無視して 200 で全体を返すサーバでも全部読んだ。ワーカーと同じ `fetchRange`（206、または小さい content-length の 200 だけ。上限付きで読む）を使う。
- 【低】画像を、大きさを確かめる前にデコードしていた（ラスタタイル、DEM、スプライトのシート、画像のソース、解析ワーカーの DEM）。`worker/js/imagesize.mjs`（import なし）でヘッダ（PNG の IHDR、JPEG の SOF、WebP の VP8/VP8L/VP8X）から幅と高さを読み、上限（ラスタ 4096、DEM 1024、解析の DEM 4096、シートと画像 8192）を超えたらデコードせずに拒む。大きさを読めないもの（ほかの形式、読んだ範囲（Blob は先頭 256KB）に SOF のない JPEG）も拒む（fail closed。自動のセキュリティレビューの指摘で、最初の版はデコードに回していた）。GIF と AVIF も拒む：ヘッダの大きさとデコードされる大きさが食い違いうる（GIF のフレーム、AVIF のシーケンスや `moov`。AVIF の `ispe` を読む版はレビューで parser differential と指摘された）。ラスタのデコード後の確認も残した。
- 【低】タイルのテンプレート、スプライト、スタイルの URL、`loadImage` が `data:` や `blob:` も取りに行けた。`npm/src/urls.ts` に `httpUrl(url, base, what)` を置き、どれも http(s) に限る。`pmtiles://` は接頭辞の後が http(s) であること。解析の `load` と `loadDem`（`resolveTemplate` の `%7B` の直しの重複を解消）、`wasmUrl` も同じ関数を通す。表示ワーカーも、取りに行く前に http(s) を確かめる（`map/dom.mbt` の `tile_url` や `transformRequest` を経た URL も含めて）。
- 【低】GeoJSON と解析のワーカーが URL のデータを上限なく読んだ。`readCapped(res, MAX_INPUT_BYTES)`（256MB、`wasmio/memory.mbt` と同じ値）で読む。
- 【情報】表示ワーカーの `tile`、`drop`、`cancel`、`ranges` のメッセージの形を確かめ、`id` が整数でないものは無視する。`source` や `z` が整数でないタイルは `tile-error`。
- 頑健さ：表示ワーカーで `init_style` が一度失敗すると、`ready` が reject のままになり、以後のタイル、クエリ、`ranges` が黙って捨てられていた。スタイルの失敗は `{type: "error"}` で知らせて `ready` を使える状態に保つ。初期化が失敗したときも、タイルには `tile-error`、クエリと `ranges` には空の答えを返し、メインスレッドの待ちが終わるようにした。
- 問題がなかったもの：式の上限（深さ、配列）、プロトタイプ汚染（`__proto__` を普通のキーに）、ラベルとアトラスの上限、クラスタの範囲の確認、ワーカーの線形メモリの境界、credentials を送らないこと、カスタムレイヤーは JSON からは動かせないこと、`eval`・`innerHTML` を使わないこと、開発用サーバ。npm audit（bench、npm、examples/react）と Dependabot は 0 件。
- 残したもの：`loadImage` の画像は大きさを確かめずにデコードする（呼ぶのはページ自身で、メインの入口を大きくしないため）。GIF、AVIF（PMTiles の tileType avif も）、BMP、SVG などはラスタタイル、スプライト、画像のソースとしては読めなくなった（MapLibre は読む）。
- 大きさ（ヘッダを読む処理が各ファイルに入る）：スプライト 0.9 → 1.6KB（1644 バイト、予算 2KB）、画像・動画のソース 2.0 → 2.6KB（2617 バイト、3KB）、PMTiles のヘッダ 0.5 → 0.7KB、表示ワーカー 92.5 → 93.2KB、GeoJSON ワーカー 27.4 → 27.6KB、解析ワーカー 27.1 → 27.9KB（予算 30KB）。メインは 107.1KB のまま。

## Phase 15 の後の修正（2026-11-03）

Phase 15 の後の見直しで見つかった不具合を直した（セキュリティの修正は別の PR）。

- **複数行のラベルが、可変アンカーでも常に左寄せだった**：15.6a でアイコンの列を足したとき、レイアウトの数の列（`LABEL_VARIANTS = 9`）を直し忘れ、アイコンの箱の左端を読んでいた。ラベルの列をすべて名前付きの定数にし（`LABEL_BOX`、`ICON_LAYOUTS`、`LABEL_LAYOUTS` など）、描画側の `col` の既定値をやめて呼び出し側で渡す。`placed_labels` は選んだレイアウトも出し、`npm run labels:golden` は MapLibre の `markUsedJustification` と比べる（場面 `radial-multiline` を追加。直す前のコードでは不一致になることを確かめた）。**33 場面すべて一致**。
- **`render` の listener が 1 フレームに 2 回呼ばれていた**（`draw_frame` の終わりでも呼んでいた）。`toBlob` の部分ごとにも呼ばれていた。
- **画像ソースのレイヤーを隠して戻すと、`idle` が来なくなった**：エンジンが絵を捨て、ファサードは同じソースの絵を渡し直さない。エンジンは描かれないソースの GPU のコピーだけを捨て、絵は持ち続ける。pack test に、隠して戻して `idle` を待つ確認を足した（直す前は時間切れ）。
- **ワーカーが落ちると止まった**：表示ワーカーの `error` / `messageerror` で、そのワーカーは以後使わず、答えていないタイル（`tile-error` として）、クエリ、feature state の範囲を空で終える。全部落ちたらタイルはすぐ失敗にする。GeoJSON ワーカーも同じく、待っているタイルを null で、クラスタの問い合わせを reject で終える。
- **`toBlob`**：待っている間に `remove()` されたら reject する。スプライトや TileJSON を取りに行っている間（`idle` を止めているもの）も待つ。
- **pack test が CI で 180 秒の時間切れになっていた**：「消す」を押してから `once("idle")` を付けていたので、間に `idle` が来ると待ち続けた。`bench/npm/checks/step.mjs` にまとめ、待つ event を先に付けてから動かす（`step`、外からの操作は `awaitAfter`）。各段階に名前と時間切れを付け、時間切れのときは最後に入った段階と地図の状態（`isMoving()`、`loaded()`）を出す。
- `worker/js/worker.mjs` の `ready` がスタイルの失敗のあと reject のままになる件は、セキュリティチェックの PR で直した（上の節）。

## Phase 15.6b：線に沿ったアイコン（2026-11-03）

状態：**完了**。

- **スタイル**：`symbol-placement: line` / `line-center` で `icon-image` を読む。`icon-rotation-alignment` の `auto` は `map`（線に沿って回り、地図の面に寝る）。`viewport` なら、線の上のアンカーに画面に立てて置く。線に沿うときの `icon-offset`（MapLibre は 2 度足す）、`icon-text-fit`、`icon-rotation-alignment: map` と `icon-pitch-alignment: viewport` の組み合わせは Unsupported。
- **ワーカー**：アンカーの間隔と長さの判定は、MapLibre の `getShapedLabelLength` と同じく、文字（glyph 単位）とアイコン（大きさ 1 の px）の長い方。文字のない（アイコンだけの）ラベルは、角度の窓を使わず、同じ文字どうしの間隔（`anchorIsTooClose`）も取らない。アイコンはインスタンス（アンカー）ごとに 1 つ。
- **配置**（`map/line_labels.mbt`）：文字は円で、アイコンは箱を地図の面にアンカーで置いて投影する（MapLibre の `_projectCollisionBox`：角と辺の中点の 8 点、遠近の比で大きく。`Map::fits_on_map`）。文字とアイコンの組み合わせは点と同じ規則（`joint`、`show_icon` を点と共有）。
- **描画**：線に沿って回るアイコンは、カメラが動いたフレームごとに、アンカーに置いた 1 文字として位置と角度を求め（`icon-keep-upright` で反転）、頂点属性 `a_glyph` で描く。
- **`npm run labels:golden`**：等高線の場面を 5 個足した（文字とアイコン、アイコンだけで回した地図、傾けた地図と `icon-keep-upright`、`viewport` のアイコンと `line-center`、`text-optional` と点のラベル）。**32 場面すべて一致**（アイコン 1,123 個、線に沿う文字 370 個）。文字の位置の差は 0px（許容 0.5px）。
  - MapLibre の glyph offset の配列は文字とアイコンで共有なので、ページは文字の位置を頂点の番号（`vertexStartIndex`）から読むように直した。同じ地物のインスタンスはグリッドで同じキーなので、箱は最も近いものと比べる。
- **`npm run style:golden`**：`icons-lines`（線に沿うピンと、`viewport` の SDF の輪、回した地図）は平均 0.016 / p99 0、`icons-lines-tilted`（45° 傾き）は平均 0.027 / p99 1。回したアイコンの縁の補間の丸めの差。
- 大きさ：メイン 105.9 → 107.1KB（+1.2KB：箱の投影、アイコンの位置、配置の整理）、表示ワーカー 92.3 → 92.5KB。
- MapLibre との違い：線に沿うアイコンは、`icon-offset`、`icon-text-fit`（道路番号の盾など。文字を画面に立てて線に置く `text-rotation-alignment: viewport` もまだない）を描かない。
- **本線で測ってほしいもの**：`render --labels --line-labels`（線のラベルの配置にアイコンの箱が、フレームごとの配置にアイコンが加わる）。

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

## 方針の更新：スタイルの互換、表現の幅、Web サービス（2026-11-03、ユーザー判断）

- **未対応の扱いは方針 D**（VISION §6「スタイルの互換」）。既定では未対応があっても描く（プロパティは既定値に戻し、描けないレイヤーだけ外す）。必ず警告を出す。`strict: true` でいまの「スタイルごと拒む」に戻せる。
  - 「Phase 15 の終わりに決める」としていた件の結論。実装は Phase 16 で行う。
- **未対応は可能なかぎり対応する**。新しい Phase 16「スタイル互換の仕上げ（2D）」を Phase 15 の次に入れた（VISION §8）。
  - 対象は、黙って無視しているプロパティ約 30 個、拒んでいる式 14 種類、hillshade の方式、`color-relief`。
  - Phase 15 の終わりの時点の一覧は VISION §8 の Phase 16 の行。
- **見た目の作り込みの幅は 2D と 3D の両方で確保する**。Mapbox GL JS v3 と比べた差を VISION §10「スタイル表現」に書いた。
  - 3D の光と影（環境光・平行光、影、環境遮蔽、時間帯のプリセット）は 3D 第2弾（いまの Phase 20）に足した。
- **仕様が公開されている GIS の Web サービスを読む口を作る**。新しい Phase 18 をデータ形式（17）の次に入れ、解析 第2弾以降を 19〜21 に繰り下げた。
  - 対象は ArcGIS REST API（VectorTileServer、MapServer、ImageServer、FeatureServer）と OGC（WMS、WMTS、WFS、OGC API - Features・Tiles・Maps）。
  - I3S は「後回し」から 3D 第2弾（Phase 20）に移した。
  - どれも読み込みとして扱い、サーバーやポータル・OAuth は作らない（VISION §5）。認証は `transformRequest` でトークンやヘッダーを足す形にする。

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
  | 本線 | 15.6 | アイコン | 済み（15.6a 点、15.6b 線。`labels:golden` 32/32） |
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
- 分割の正しさは、面積と構造で確かめている。GEOS（JSTS）など、ほかの実装との黄金テストは Phase 19（空間関係）で行う。
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
- 測地線：GeographicLib を MoonBit に移植する。置き場所は、大きさを測ってから決めた（下の表）。**決定：新しい入口 `mbmap/geodesic`**（専用の Worker と wasm）。Phase 19 でデータを測るときは、解析の Worker も同じ `geodesic.wasm` を読める。

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
- 印刷はサーバーの印刷サービスではなく、クライアントで完結させる（ユーザーの指摘で「作らないもの」から外した）。高解像度に描いて Wasm で PDF を作り、ブラウザの PDF ビューアなどで印刷する（Phase 21）。
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
