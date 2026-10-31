# PROGRESS

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
