# AGENTS.md — mbmap

Tool-agnostic contributor & AI-agent guide (Claude Code, Codex, Cursor, …).
`CLAUDE.md` is a symlink to this file, so there is exactly one guide to maintain.

mbmap: a MoonBit vector-tile map rendering engine for the Web, aiming to be lighter and faster than MapLibre GL JS.

- `docs/VISION.md` is the authoritative spec: goals, perf targets (§2), architecture (§3), design principles (§4), scope (§5), API (§6), work rules (§7), phase plan (§8).
- `PROGRESS.md` records per-phase results, benchmark numbers, known issues and user decisions. Read both before starting a phase.
- `docs/FORMATS.md` is the reference for the binary formats and worker messages; code cites its section names instead of restating layouts.
- If a task is not in the current phase of VISION §8, confirm scope with the user before widening it.

MoonBit skills (`moonbit-agent-guide`, `moonbit-orientation`, `moonbit-refactoring`, …) come from the `moonbit-skills` plugin (`/plugin` → marketplace `moonbitlang/skills`). They auto-engage in `.mbt` files.

## 1. Commands

MoonBit (run from repo root):

```sh
moon check --target all          # type-check every backend (wasm, wasm-gc, js, native)
moon test --target all           # all tests on all backends
moon test <pkg-dir> --target all # one package, e.g. moon test bench/backend/kernel
moon test <pkg-dir> -F "glob"    # filter tests by name
moon test <pkg-dir> -u           # update snapshots (single target only; -u fails with --target all)
moon fmt && moon info            # before committing; regenerates pkg.generated.mbti
```

npm package (from `npm/`): `npm ci && npm run build` writes `dist/` (index.js + .d.ts, worker.js, mbmap.wasm); `npm run size` checks the gzip budgets of VISION §2; `npm test` runs the TS unit tests (`npm/test/*.test.ts`, `element/*.test.ts`) with Node type stripping, so modules under test must be import-free or import other `.ts` files only.

Benchmarks (from `bench/`, Node + Playwright):

```sh
npm ci && npx playwright install chromium firefox webkit
npm run fixtures          # download GSI tiles, verify against sha256 manifest
npm run backend:node      # backend comparison in Node (builds MoonBit + wasm-opt first)
npm run backend:browser   # same, inside a module Worker in Chromium/Firefox/WebKit
npm run maplibre:parse    # MapLibre WorkerTile.parse baseline
npm run maplibre          # MapLibre first-render / frame-time / bundle-size baseline
npm test                  # Node tests for bench tooling (lib/*.test.mjs)
npm run mvt:golden        # mvt vs @mapbox/vector-tile on all fixtures (must stay 35/35)
npm run mvt:node          # mvt decode bench in Node
npm run mvt:browser       # same, inside a module Worker in Chromium/Firefox/WebKit
npm run tess:golden       # fills vs MapLibre's classifyRings + earcut on all fixtures (must stay 35/35)
npm run tess:node         # decode + tessellation vs MapLibre WorkerTile.parse in Node
npm run tess:browser      # same, inside a module Worker in Chromium/Firefox/WebKit
npm run worker:browser    # worker process_tile per fixture, cold and warm, in three browsers
npm run geojson:golden    # tiler vs @maplibre/geojson-vt, every tile in range (js in full, wasm-gc by hash; must stay 0 differ)
npm run geojson:node      # GeoJSON read + index + tiles vs geojson-vt in Node (also geojson:browser)
npm run analysis:golden   # analysis wasm vs Turf.js 7.4.0 / flatbush 4.6.2 on all fixtures (must stay all identical)
npm run analysis:node     # analysis vs Turf.js + flatbush in Node (also analysis:browser)
npm run render            # mbmap vs MapLibre: first render, frame CPU, bundle sizes (same style)
npm run example           # serve the repo; open http://127.0.0.1:8080/examples/ (basic needs only this)
npm run examples          # also pack npm/ into examples/{npm,element,react} (bench/npm/prepare.mjs), then serve
npm run npm:pack          # build + npm pack npm/, install into examples/{npm,element,react}, check them in Chromium (CI runs this)
```

Bench entry points that import TypeScript or MapLibre sources run through `node lib/run-bundled.mjs <entry>`; the MoonBit side of every mvt/tess bench is the single export package `bench/entry`.

Results go to `bench/results/*.json`; numbers in PROGRESS.md must come from there (VISION §2: never claim "fast" without a reproducible script).

## 2. Workflow

- Never commit to `main` directly: `git switch -c <kind>/<short-description>` (`feat/`, `fix/`, `chore/`, `docs/`, `refactor/`, `phaseN/`), then `gh pr create`.
- Validation loop before reporting complete or committing:
  ```sh
  moon check --target all
  moon test --target all
  moon fmt
  moon info                            # commit .mbti diffs with the code
  ```
  A `.mbti` diff means the public API changed; check it is intended.
- A change that claims a perf effect reruns the relevant `bench/` script and updates PROGRESS.md with the new numbers.
- Major design changes (Wasm backend, package split, rendering approach) require presenting measurements and options and getting user confirmation first (VISION §7).

## 3. Toolchain notes

- moon 0.1.20261028 uses the **new DSL config files `moon.mod` / `moon.pkg`**, not `moon.mod.json` / `moon.pkg.json`. MoonBit syntax and tooling change quickly: verify APIs with `moon ide doc`, generated `.mbti`, or docs.moonbitlang.com instead of guessing from memory.
- `bench/backend/entry` shows the working patterns for exports (`pkgtype(kind: "foreign_library")` + `#export_name`), `export-memory-name`, and per-file conditional compilation (`options(targets: {...})`).
- `moon info` writes `.mbti` from the canonical backend (wasm), so js-only packages (`map`, `render_webgl2`) currently get none; `moon info --target js` only prints the diff against wasm. Settle how to track their interface before they gain public API.
- Inline wasm via `extern "wasm" fn f(...) = #|(func ...)` works on both wasm and wasm-gc and is how linear memory is accessed.
- Current idioms the compiler insists on: `derive(Eq, Debug)` on a public type needs a `pub extend T with ...` entry in the package's `extends.mbt` (copy a neighbouring one); `extend` is a keyword; `Ref(x)`, `Map([], capacity=n)`, `Array(capacity=n)`, `@cmp.minimum`; `try?` is gone (`try Some(e) catch { _ => None }`). In a function with a bare `raise`, `catch` can match constructors of several suberror types.
- Script mode (`moon run x.mbtx`) currently fails with a core `gzip` alias conflict, so automation stays in Node scripts under `bench/`.

## 4. Architecture

Dependency direction (never reverse): `core ← pbf ← mvt ← tess/style ← worker`, `core ← geom ← formats/tiler ← geojson_worker`, `geom ← analysis ← analysis_worker` and `core ← render_webgl2 ← map ← (npm, element) ← adapters`. Nothing under `map/` may depend on a UI framework.
Planned data/analysis/3D packages (VISION §3) ship as separate npm entry points with their own lazily loaded wasm and size budgets: `map` must never import them, and they exchange data with the display only through columnar (GeoArrow-compatible) buffers. Granularity (decided in Phase 6.5): one wasm module per entry, run in its own lazily started worker; split a feature group into its own module once its own code exceeds ~20KB gzip (each module duplicates ~6KB of core: trig, int formatting). Never link analysis into the display worker. A new entry or module needs a row in `npm/scripts/size.mjs`.

- `core`, `pbf`, `mvt`, `tess`, `style` are pure MoonBit and must pass tests on every backend.
- `worker` ships as **wasm-gc** (decided in Phase 0). Tile bytes and output buffers cross the JS boundary through a linear-memory region managed by the worker, using inline-wasm load/store. Keep that wasm-gc-specific I/O inside wasm-gc-only packages: `wasmio` (input at `PAGE`, output after it; the entries wrap its functions in their own `#export_name`s, which imported packages do not export) serves `geojson_worker` and `analysis_worker`, and its JS side `wasmio/js/host.mjs` gives them `hostNumber`. An all-targets package cannot import a wasm-gc-only one, so `worker` (and the bench entries) keep their own few load/store helpers. Do not pass data element-by-element through exported functions: per-element calls on GC arrays were 5–50× slower in Phase 0 benchmarks.
- Tile pipeline: `map` (main thread) asks a worker for a tile → `worker/js/worker.mjs` fetches it, places it in linear memory and calls the wasm-gc exports of `worker` (`prepare_input`, `init_style`, `process_tile`, `output_addr`) → `TileProcessor` decodes, tessellates and packs every fill/line layer of the style into one `PackedTile` blob (header of `LAYER_ENTRY_WORDS` u32s per layer, Int16 positions, 16- or 32-bit indices, coordinates rescaled to `@core.TILE_EXTENT`; layers with the same geometry, like a road and its casing, share one buffer) → the glue slices it into ArrayBuffers and transfers them → `render_webgl2` uploads them as they are. In wasm-gc the blob is written in place in linear memory (`store_memory.mbt`); other targets use an array (`store_array.mbt`). The linear-memory files are wasm-gc only: in the wasm backend MoonBit's own heap lives in linear memory. The main thread never touches geometry (VISION §4-3).
- `map` must not import `worker` (it would pull mvt/tess into the main bundle); shared constants live in `core` or are mirrored with a pointer to the original. `style` compiles filters and paint into `Expr` (the subset in `style/expr.mbt`, nesting capped by `MAX_EXPR_DEPTH`) and reports anything else as `Unsupported` with its JSON path; `Expr::eval` is generic over a `FeatureContext`.
- Data-driven paint: the worker splits a layer's features into groups by the values its paint reads (`feature_inputs`, at most `MAX_GROUPS` per layer and tile) and gives each group its own entry carrying those values as JSON; the main thread evaluates paint per group at the current zoom and draws it with uniforms. The main thread evaluates through one context type (`JsProps`), so `Expr::eval` is compiled into the bundle once.
- Camera math and tile covering live in `core` (`Transform`), pure and tested on all targets; `map` only wires DOM events, workers and the frame loop (renders on demand, falls back to a loaded ancestor or loaded children). The camera has bearing and pitch (≤ `MAX_PITCH` 60°, so the horizon stays off screen): `Transform` keeps a MapLibre-style view-projection (`Mat4`, column-major) over world pixels relative to the center, so precision holds at every zoom. `covering_tiles(min_z, max_z)` walks a quadtree over the view's ground footprint and drops a zoom level per doubling of distance beyond `LOD_DISTANCE` camera distances; leaves never overlap. Shaders take a per-tile `mat4`; lines extrude in tile units (they thin with distance) and scale their antialiasing by depth; an ancestor standing in for a missing tile is clipped in the fragment shader (`u_clip`, tile units), since scissor rectangles fail once the map turns. Circles (`KIND_CIRCLE`) reuse the line vertex layout, one quad per point inside the tile (`@tess.add_points`); the shader expands it around the projected center in screen space scaled by depth (MapLibre's `pitch-alignment: viewport`, `pitch-scale: map`).
- `render_webgl2` and `map` are js-target only (`supported_targets = "js"`). On the js backend `FixedArray[Byte]`/`Bytes` are `Uint8Array`, but `FixedArray[Float]` is a plain JS `Array`, so GPU buffers need `extern "js"` typed-array wrappers.
- `npm/`, `element/`, `adapters/`, `examples/` are not MoonBit packages (TS/HTML side). `npm/src/index.ts` is a MapLibre-shaped TS facade (`Map`, `on`/`once`, `jumpTo`, …) over the `bundle/main` exports; esbuild aliases `mbmap-engine` to that build and `npm/src/engine.d.ts` types it, so keep both in sync with `bundle/main/main.mbt`. The facade resolves tile URLs against the style URL and loads `worker.js`/`mbmap.wasm` next to itself via `new URL(..., import.meta.url)`.
- `element/element.ts` is `<mb-map>` (entry `mbmap/element`, ~1KB on top of the main entry, which it imports as `./index.js` rather than bundling). The map lives in an open shadow root; attributes are parsed strictly (invalid values fire `mb-error` and are kept out); `center`/`zoom` properties also take the attribute strings because React 19 sets props as properties when the element has one. Style the shadow box inline: a `div` rule in the shadow stylesheet also hit the facade's attribution overlay.
- CI (`.github/workflows/ci.yml`) installs a pinned MoonBit toolchain verified by sha256; bumping `moon` means updating `MOONBIT_VERSION` and both hashes there.
- `bench/backend/{kernel,entry}` are MoonBit packages inside this module used only for the Phase 0 backend comparison. The decode loop is intentionally duplicated there (safe arrays vs raw addresses vs JS typed array); do not "deduplicate" it.

- `pbf` reads never raise: a `Reader` records its first error, jumps to the end so loops stop, and its `error()` is checked once at a boundary. Nested messages are read in place with `enter`/`exit`; `reset` re-points one reader instead of allocating another.
- `tess` triangulates fills with a port of earcut 3.2.4 whose output matches the JS library exactly, after grouping rings like MapLibre's `classifyRings`, and extrudes lines into quads plus join/cap geometry (vertex layout in `LINE_VERTEX_STRIDE`). Tessellators and buffers are reusable objects so steady-state use does not allocate.
- `geom` holds columnar feature tables (`Table`: kinds, nested part/ring/point offsets over interleaved coordinates, GeoArrow's multipolygon layout for every kind; properties as one `Column` per key, padded by `TableBuilder::finish`). `formats` reads GeoJSON straight from UTF-8 into a table (no JSON tree; sticky errors; `MAX_GEOJSON_DEPTH` and `MAX_GEOJSON_KEYS`; numbers take Clinger's exact fast path up to 15 digits and core `strconv` beyond, which is the reader's main cost on full-precision data). `tiler` is an exact port of @maplibre/geojson-vt 6.3.0 (`npm run geojson:golden` must stay at 0 differences): clipped features live in per-clip `Store`s referenced by `FRef`, so a feature kept whole is shared and stores are freed like geojson-vt's objects; `Trig` lets a wasm-gc build project with the host's `Math.sin`/`Math.log` (bit-identical to geojson-vt; the pure `@math` differs in the last bit now and then, which changed 314 of 4336 golden tiles), which moonrun cannot provide, so tests use the default.
- GeoJSON sources (`mbmap/geojson`, loaded by the facade with a dynamic `import("./geojson.js")` only when a style has one): `npm/src/geojson.ts` starts `geojson_worker` (wasm-gc: `formats` + `tiler`, host `Math` for `Trig`), sends each source's data (URL fetched in the worker without credentials, or the object as UTF-8), and serves tiles by source id. `map` asks the facade's provider (`map/dom.mbt` `Provider`) for a GeoJSON tile, gets an `@tiler.encode_tile` buffer and posts it to a display worker as `bytes`; the display worker reads it as a `ColumnTile` (bounds-checked) behind the same `Features` enum as MVT layers, so filters, grouping and tessellation are shared. `map` keeps one `SourceTiles` per source its layers use; the facade strips GeoJSON `data` from the style the engine parses. Every tile is clipped to its own extent in the fragment shader (features reach into a buffer the neighbours draw too).
- Analysis (`mbmap/analysis`, its own entry, worker and wasm; never imported by `map` or the facade): `analysis` is pure MoonBit (a flatbush port `Index`, measures and `contains_point` matching Turf.js bit for bit given the host's `Math`, `points_within`, `collect`, `grid_count`); `analysis_worker` keeps datasets by handle with their index built on first use; `npm/src/analysis.ts` is the Promise API (`load` → `Dataset`). `npm run analysis:golden` must stay all identical.
- wasm-gc entries that read GeoJSON (`geojson_worker`, `analysis_worker`) pass `read_geojson` a `slow_number` that parses numbers over 15 digits with the host's `Number()` straight from linear memory; leaving out core strconv halves those modules (about 24KB gzip each). Firefox reads full-precision data about 20% slower that way (PROGRESS.md).
- Labels (symbol layers, point placement): the worker wasm packs each point's anchor, `text-size` and `text-field` parts (`worker/labels.mbt`); the worker glue draws SDF glyphs with TinySDF on an `OffscreenCanvas` (`worker/js/symbols.mjs`, each glyph sent once per worker in the tile message's `glyphs`) and lays text out in CSS pixels (`worker/js/text.mjs`, import-free and unit-tested by `npm test`). The main thread packs glyphs into one atlas (`label.Atlas`), turns each quad's glyph index into atlas pixels before upload (the one place it touches vertices), and places labels with a screen grid (`label.Grid`) from the top layer down when tiles arrive or every `PLACEMENT_INTERVAL` while the camera moves, uploading only the shown labels' indices. Text keeps a constant screen size and faces the viewer; fonts come from the browser (`fontFamily`), not glyph PBFs.
- Binary forms that cross workers (group properties, columnar tiles, `Table` bytes; docs/FORMATS.md) are written and read with `@core.ByteWriter`/`ByteReader` (sticky errors) and share the `@core.PROP_*` value tags. Group properties are binary, not JSON, because stringify pulled float printing into the worker; `worker/js/worker.mjs` decodes them into prototype-less objects. Layers share buffers when their filters are written identically (`filter_id`), not by comparing `Expr`s.
- `mvt` decodes layer tables, feature headers and tags in `Tile::parse` (raising `MvtError` once per tile) and stores features column-wise; per-feature calls take an index (`layer.decode_geometry(i, out)`, `layer.property(i, key)`) and don't raise. Geometry is decoded lazily into a reusable `Geometry` buffer.

Backend facts measured so far (see PROGRESS.md):
- **In wasm-gc every call to a `raise` function allocates its result object, even on success.** Keep `raise` off hot paths: report errors through sticky state or return values, and raise only at coarse boundaries. This alone made the mvt decoder go from 1.3–2.2× slower than JS to faster than JS.
- wasm (linear memory) uses refcount + TLSF and is 6–9× slower than wasm-gc/JS on allocation-heavy code.
- `wasm-opt -O3` made the wasm-gc mvt decoder 12–45% *slower* in every browser; do not run it on wasm-gc builds. For wasm (linear memory) it helps only on Node 22, whose older V8 does not inline small wasm functions (flags in `bench/backend/opt.mjs`).
- In hot loops `FixedArray` beats `Array` (an `Array` access also loads and checks its length): switching earcut's node pool cut its time by about 25%. Prefer incremental rotation over per-vertex `sin`/`cos`/`atan2` (it made line extrusion about 40% faster).
- V8 does not switch a running wasm call to optimized code, so a worker's first tile runs in baseline code (about 3–5× slower than warm). Warming up with a synthetic tile at init did not help first render in measurements and was removed.
- Sharing one buffer between layers with the same geometry and packing in place instead of copying made `process_tile` 23–27% faster (median tile) and the output 17% smaller. Compiling the worker wasm once on the main thread and sending the module to every worker made no difference to first render and was reverted.
- Line output size matters more than tessellation speed: round caps are square extensions that the line shader cuts with `length(side, along)`, and layers with at most 65536 vertices use 16-bit indices; together they cut the center tile's packed size from 2.0 MB to 0.8 MB and `process_tile` from 5.4 to 3.2 ms.
- Bundle size: `Repr`/`Debug` output and `@string.parse_double` (strconv) pulled about 28KB gzip into the main bundle (49.1 → 20.6KB once removed); shipped code reports errors with `message()` strings instead. A second instantiation of `Expr::eval` cost about 11KB minified but only 0.2KB gzip.
- Copying linear memory into GC `Bytes` is fast when done 4 bytes per load into a `FixedArray[Byte]` and reinterpreted (`bench/entry/linear_memory.mbt`); `Bytes::makei` calls a closure per byte and is 2–6× slower.

## 5. Benchmark gotchas

- Headless Chromium defaults to SwiftShader; GPU benches must launch with `--use-angle=metal --enable-gpu --ignore-gpu-blocklist`.
- On the M2 dev machine frame time is vsync-capped at 16.67ms even for MapLibre; use per-frame render CPU time (and `--uncapped`) as the proxy metric. Real Android measurement is out of scope for now.
- Bundling MapLibre `src/` with esbuild requires `useDefineForClassFields: false` and an alias to `node_modules/maplibre-gl/src` (package `exports` blocks deep imports).
- Inline `<script type="module">` in bench pages did not execute under Playwright; keep page code in external `.mjs` files.
- Register MapLibre `load`/`idle` listeners immediately after constructing the map (idle can fire in the same task as load).
- `bench/fixtures/gsi-bvmap/` (~13MB) is gitignored; only the manifest is committed. Attribution: 国土地理院ベクトルタイル提供実験.

## 6. Testing conventions

- Golden data: compare against existing JS implementations (@mapbox/vector-tile, earcut JS) via scripts in `bench/` or `test/fixtures/`. Tessellation must also check that total triangle area equals polygon area.
- Every `pub fn` gets ≥1 direct test; every error path (`raise`, `None`) is covered. Tests run on all backends.
- Prefer `assert_eq` (or `assert_true(x is Pattern(...))`) over snapshots for stable results; derive `Debug` + `debug_inspect` for structured output.
- A test that only re-runs the type checker (`let _ = …`) duplicates `moon check`; delete it.
- Fixtures from external sources carry their attribution (fixtures README and `NOTICE`).

## 7. Refactoring checklist

When the user says **「リファクタリング」 / "refactor" / "tidy up" / "clean up"**, walk these lenses **in order** and write a concrete findings list **before** changing code (consider the `moonbit-refactoring` skill). This applies whether the target is one file or the whole tree.

### 7.1 Constants
Promote magic numbers and repeated literals that name a concept to a `pub let` in the owning package, defined exactly once. Examples: MVT and packed extents (`@core.TILE_EXTENT`, VISION §4-2), protobuf wire types and field numbers, Style Spec keys, vertex attribute layouts and strides, Worker message type tags.

### 7.2 Duplicate / dead code
- Consolidate identical helpers in the lowest package that may own them, respecting the dependency direction in §4.
- Delete stub files that are comment-only `.mbt` files once a package holds real API.
- Drop unused imports (`unused_package`).
- Make `pub` items with no external caller private, or delete them.
- Exception: the intentional duplicates in `bench/backend` (§4).

### 7.3 File splitting
A `.mbt` file over ~500 lines is a smell, not a rule. Split only at a logical boundary (e.g. varint reader vs message walker; earcut vs line extrusion), never to hit a line count. Keep blackbox (`*_test.mbt`) and whitebox (`*_wbtest.mbt`) tests separate.

### 7.4 Test adequacy
- §6 holds: golden tests at every decode/tessellation boundary, the area check for tessellation, and every error path covered.
- Tests assert on values, not just shapes.
- Tests pass on all four targets.

### 7.5 Performance
Invariants:
- Hot paths (pbf/mvt decode, tessellation, worker packing, per-frame rendering) stay allocation-free and write into preallocated `FixedArray`/`Bytes` (VISION §4).
- A refactor touching a hot path reruns the relevant bench and records any regression in PROGRESS.md before merging.
- Bundle size is a budget (VISION §2), so a refactor must not add dependencies or runtime code to the main-thread bundle without measuring.

Speed opportunities — every refactor also looks for measurable wins in the code it covers:
- Find the cost first: profile or break the bench down (per-stage rows, `--output-wat` for wasm-gc) instead of guessing. Known traps: `raise` on hot paths, `Array` vs `FixedArray` in tight loops, per-element boundary calls, per-vertex trig, oversized output (§4).
- List each candidate with its expected effect before changing code; keep a change only if the bench shows a win beyond run-to-run noise on the target browsers and no regression elsewhere.
- Record what was tried in PROGRESS.md, including changes that did not help and were reverted, so they are not retried blindly.

### 7.6 Documentation freshness
- PROGRESS.md and VISION.md match the code state.
- Public APIs have `///` doc comments.
- `.mbti` is regenerated and its diff is the intended public-API change.

### 7.7 Comment hygiene
**The default is no comment.** Comment only where a reader cannot recover the intent from the code. Keep it to one or two lines, three at most.

- **Delete what the code already says.** If code needs a paraphrase, fix the code instead: use a better name, a named intermediate, or a smaller function.
- **Delete documentation that wandered into source.** Design rationale and package tours belong in VISION.md, PROGRESS.md or README. The source may cite them but must not restate them. File-header essays and section banners are this failure mode; `///|` already separates blocks.
- **Delete narration of the past** (what used to happen, what a commit changed). If a bug explains a non-obvious line, keep the reason in one clause and cite the issue (`#N`).
- **Keep the constraint the code can't show**: a spec rule (MVT spec section, Style Spec property, WebGL2 limit), an invariant the compiler doesn't enforce, or a deliberate deviation.
- **No phase codes in comments** (`Phase 2`). Name the thing instead. Issue numbers and spec section references are fine.
- Struct fields carry no `///` of their own: describe the fields in the type's own doc. A one-line note on an enum variant is fine when the variant name alone doesn't say what it selects.
- Tests get the same treatment: the test name says what it asserts.

### 7.8 Latest MoonBit language-spec conformance
- Migrate deprecated constructs rather than suppressing the warnings.
- Verify constructs against `moon ide doc`, the `moonbit-orientation` skill and local sources, not memory.
- Adopt current idioms where they help clarity: `raise` error handling, pattern-match views, labelled/optional args, method syntax, iterators, derive macros.
- If a `moon` version bump changes formatting or generated output, land that diff on its own.

### 7.9 Validation loop after refactoring
```sh
moon check --target all --deny-warn
moon test --target all
moon fmt
moon info
```
Then run the §8 security check on the touched area. Push only when everything is clean.

## 8. Security check

Run this when the user says **「セキュリティチェック」 / "security check"**, as part of every refactor (§7.9), and before adding or upgrading any dependency or cutting a release. Report findings as a list (severity, location, fix) before changing code.

### 8.1 Dependencies and supply chain
- `npm audit` in every directory with a `package.json` (`bench/`, `npm/`). Also check GitHub Dependabot / security advisories for the repo: `gh api repos/{owner}/{repo}/dependabot/alerts`.
- Recent advisories move faster than `npm audit` sometimes reflects. For each direct dependency, check its GitHub Security Advisories and release notes for the pinned version, especially MapLibre, Playwright, esbuild, binaryen and anything in the shipped bundle.
- Pin exact versions (`--save-exact`) and commit the lockfile. CI uses `npm ci`, never `npm install`.
- Before adding a package, check its maintainer, download history, install scripts (`preinstall`/`postinstall`), and whether it is a typosquat. Prefer no new dependency when a few lines will do (bundle budget, VISION §2).
- MoonBit deps (`moon.mod` `import`): pin versions, and review the source of new mooncakes packages (`moon fetch`) before depending on them. Keep the toolchain current with `moon upgrade` and record the version in PROGRESS.md.
- Never pipe a remote script to a shell, and never run downloaded code from its own directory. Fixtures and downloaded tiles are data: verify them against the sha256 manifest.

### 8.2 Untrusted input (tiles, styles, GeoJSON, URLs)
Everything fetched at runtime is attacker-controllable. Decoders must fail safely on malformed input:
- **pbf/mvt**: bounds-check every read. Reject varints longer than 10 bytes and length-delimited fields that exceed the remaining buffer. Cap nesting, feature, key and value counts. Make sure no input can produce an infinite loop (zero-length fields, `ClosePath`/`MoveTo` command counts of 0 or huge).
- **tess**: cap vertex and index counts per tile, guard against degenerate or self-intersecting rings blowing up earcut, and check that integer math on quantized coordinates (Int16, VISION §4-2) cannot overflow silently.
- **style**: expression evaluation is bounded (depth, array sizes); no `eval`/`new Function`. Unknown expressions fail with a diagnostic, never execute.
- **GeoJSON**: limit size and coordinate count before tiling. `JSON.parse` only, and keep `__proto__` keys out of property maps (prototype pollution).
- **worker linear memory**: raw-address load/store in `worker/` must validate every offset and length against the region it owns. A bad length must never read or write outside it. This is the one place where MoonBit's bounds checks don't protect us.

### 8.3 Web platform
- No `innerHTML`/`outerHTML`/`insertAdjacentHTML` with data from tiles, styles or attributes. Use `textContent` and DOM APIs, which matters most for future labels and attribution strings in `<mb-map>`.
- Work under a strict CSP: no `eval`, no `new Function`, and workers loaded from same-origin URLs (no blob or data-URL workers unless documented).
- Fetches for tiles, styles and sprites send no credentials by default. URL templates may only substitute `{z}/{x}/{y}` (no open redirects or arbitrary schemes). Any request transform hook is the caller's responsibility and documented as such.
- `postMessage` handlers check message shape and type and ignore unknown messages.
- `<mb-map>` attributes (`style-url`, `center`, …) are parsed strictly; invalid values are rejected, not coerced.

### 8.4 Repo and tooling hygiene
- No secrets, tokens or personal data in code, fixtures, bench results or commit messages. Bench results record the environment, not user identifiers.
- `bench/lib/serve.mjs` is a dev-only server: it must bind to `127.0.0.1`, refuse paths outside the repo root and dotfiles (`.git`, `.env`), and survive malformed URLs. `bench/lib/serve.test.mjs` pins this down.
- Ported code keeps its license header and a `NOTICE` entry (VISION §7). License review is part of the dependency check.

## 9. Things to avoid

- ❌ Planning docs outside VISION.md / PROGRESS.md.
- ❌ Reversing the package dependency direction, or UI-framework dependencies under `map/`.
- ❌ Allocation in hot paths without a measured reason.
- ❌ Perf claims without a `bench/` script and a results JSON.
- ❌ Adding dependencies without the §8.1 check and a note in PROGRESS.md.
- ❌ Trusting tile, style or GeoJSON input (see §8.2).
- ❌ Suppressing deprecation or `unused_*` warnings instead of fixing them.
- ❌ Skipping `moon fmt` / `moon info` before committing, or bypassing hooks with `--no-verify`.
