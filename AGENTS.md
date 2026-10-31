# AGENTS.md — mbmap

Tool-agnostic contributor & AI-agent guide (Claude Code, Codex, Cursor, …).
`CLAUDE.md` is a symlink to this file, so there is exactly one guide to maintain.

mbmap: a MoonBit vector-tile map rendering engine for the Web, aiming to be lighter and faster than MapLibre GL JS.

- `docs/VISION.md` is the authoritative spec: goals, perf targets (§2), architecture (§3), design principles (§4), scope (§5), API (§6), work rules (§7), phase plan (§8).
- `PROGRESS.md` records per-phase results, benchmark numbers, known issues and user decisions. Read both before starting a phase.
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

Dependency direction (never reverse): `core ← pbf ← mvt ← tess/style ← worker` and `core ← render_webgl2 ← map ← (npm, element) ← adapters`. Nothing under `map/` may depend on a UI framework.

- `core`, `pbf`, `mvt`, `tess`, `style` are pure MoonBit and must pass tests on every backend.
- `worker` ships as **wasm-gc** (decided in Phase 0). Tile bytes and output buffers cross the JS boundary through a linear-memory region managed by the worker, using inline-wasm load/store. Keep that wasm-gc-specific I/O inside `worker/` only. Do not pass data element-by-element through exported functions: per-element calls on GC arrays were 5–50× slower in Phase 0 benchmarks.
- `render_webgl2` and `map` are js-target only (`supported_targets = "js"`). On the js backend `FixedArray[Byte]`/`Bytes` are `Uint8Array`, but `FixedArray[Float]` is a plain JS `Array`, so GPU buffers need `extern "js"` typed-array wrappers.
- `npm/`, `element/`, `adapters/`, `examples/` are not MoonBit packages (TS/HTML side).
- `bench/backend/{kernel,entry}` are MoonBit packages inside this module used only for the Phase 0 backend comparison. The decode loop is intentionally duplicated there (safe arrays vs raw addresses vs JS typed array); do not "deduplicate" it.

- `pbf` reads never raise: a `Reader` records its first error, jumps to the end so loops stop, and its `error()` is checked once at a boundary. Nested messages are read in place with `enter`/`exit`; `reset` re-points one reader instead of allocating another.
- `tess` triangulates fills with a port of earcut 3.2.4 whose output matches the JS library exactly, after grouping rings like MapLibre's `classifyRings`, and extrudes lines into quads plus join/cap geometry (vertex layout in `LINE_VERTEX_STRIDE`). Tessellators and buffers are reusable objects so steady-state use does not allocate.
- `mvt` decodes layer tables, feature headers and tags in `Tile::parse` (raising `MvtError` once per tile) and stores features column-wise; per-feature calls take an index (`layer.decode_geometry(i, out)`, `layer.property(i, key)`) and don't raise. Geometry is decoded lazily into a reusable `Geometry` buffer.

Backend facts measured so far (see PROGRESS.md):
- **In wasm-gc every call to a `raise` function allocates its result object, even on success.** Keep `raise` off hot paths: report errors through sticky state or return values, and raise only at coarse boundaries. This alone made the mvt decoder go from 1.3–2.2× slower than JS to faster than JS.
- wasm (linear memory) uses refcount + TLSF and is 6–9× slower than wasm-gc/JS on allocation-heavy code.
- `wasm-opt -O3` made the wasm-gc mvt decoder 12–45% *slower* in every browser; do not run it on wasm-gc builds. For wasm (linear memory) it helps only on Node 22, whose older V8 does not inline small wasm functions (flags in `bench/backend/opt.mjs`).
- In hot loops `FixedArray` beats `Array` (an `Array` access also loads and checks its length): switching earcut's node pool cut its time by about 25%. Prefer incremental rotation over per-vertex `sin`/`cos`/`atan2` (it made line extrusion about 40% faster).
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
Promote magic numbers and repeated literals that name a concept to a `pub let` in the owning package, defined exactly once. Examples: MVT extent (4096) and the quantization scale (8192, VISION §4-2), protobuf wire types and field numbers, Style Spec keys, vertex attribute layouts and strides, Worker message type tags.

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

### 7.5 Performance invariants
- Hot paths (pbf/mvt decode, tessellation, per-frame rendering) stay allocation-free and write into preallocated `FixedArray`/`Bytes` (VISION §4).
- A refactor touching a hot path reruns the relevant bench and records any regression in PROGRESS.md before merging.
- Bundle size is a budget (VISION §2), so a refactor must not add dependencies or runtime code to the main-thread bundle without measuring.

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
- `npm audit` in every directory with a `package.json` (currently `bench/`, later `npm/`). Also check GitHub Dependabot / security advisories for the repo: `gh api repos/{owner}/{repo}/dependabot/alerts`.
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
