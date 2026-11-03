// The showcase's search from `mbmap/search`: coordinates (projected ones through mbmap/analysis) and the places,
// without a server; `?gsi-search=1` adds GSI's place-name search as an external provider (no published terms; see the README).
import { transform } from "mbmap/analysis";
import { coordinates, createSearch, datasetSearch } from "mbmap/search";

/** An external provider: GSI's place-name search, the shape any web API takes. */
export function gsiPlaceSearch() {
  return {
    name: "国土地理院 地名検索",
    async search(query, { signal, limit }) {
      const url = `https://msearch.gsi.go.jp/address-search/AddressSearch?q=${encodeURIComponent(query)}`;
      const res = await fetch(url, { signal, credentials: "omit" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const found = await res.json();
      return (Array.isArray(found) ? found : []).slice(0, limit).flatMap((f) => {
        const [lng, lat] = f?.geometry?.coordinates ?? [];
        const title = f?.properties?.title;
        return Number.isFinite(lng) && Number.isFinite(lat) && typeof title === "string" ? [{ provider: this.name, label: title, lngLat: { lng, lat } }] : [];
      });
    },
  };
}

/** The search over `map`, `places()` giving the current places. */
export function createShowcaseSearch(map, places) {
  const providers = [coordinates({ transform, name: "座標" }), datasetSearch(places, { fields: ["name"], name: "地点" })];
  if (new URLSearchParams(location.search).get("gsi-search") === "1") providers.push(gsiPlaceSearch());
  const search = createSearch(map, { providers });
  window.__search = search;
  return search;
}

/**
 * The search box's keys: ↑↓ move through the results, Enter chooses (searching first if needed), Esc
 * closes. Keys that confirm or pick an IME conversion (Japanese input) are left to the IME: Safari
 * sends the confirming Enter after `compositionend`, with keyCode 229.
 */
export function onSearchKey(search, e) {
  if (e.isComposing || e.keyCode === 229) return;
  if (e.key === "ArrowDown" || e.key === "ArrowUp") {
    e.preventDefault();
    search.move(e.key === "ArrowDown" ? 1 : -1);
  } else if (e.key === "Enter") {
    if (search.state.results.length) search.select();
    else void search.submit().then(() => search.select());
  } else if (e.key === "Escape") search.close();
}

/** A pin on the chosen result, kept on its place with `track`. */
export function pinSelection(map, search, parent) {
  const pin = document.createElement("div");
  pin.className = "pin selection";
  pin.hidden = true;
  parent.append(pin);
  let tracker = null;
  search.subscribe((s) => {
    if (!s.selected || tracker?.place === s.selected) return;
    tracker?.remove();
    pin.textContent = s.selected.label;
    pin.hidden = false;
    tracker = map.track(s.selected.lngLat, ({ x, y }) => (pin.style.transform = `translate(${x}px, ${y}px)`));
    tracker.place = s.selected;
  });
}

/** The search box as a combobox in `#search` for the plain-DOM examples. */
export function mountSearch(map, places) {
  const search = createShowcaseSearch(map, places);
  const box = document.getElementById("search");
  const input = Object.assign(document.createElement("input"), { type: "search", placeholder: "地点名・座標（35.68, 139.76 / 第IX系 X … Y … / 54N …）" });
  input.setAttribute("role", "combobox");
  input.setAttribute("aria-autocomplete", "list");
  input.setAttribute("aria-controls", "search-results");
  const list = Object.assign(document.createElement("ul"), { id: "search-results" });
  list.setAttribute("role", "listbox");
  const status = document.createElement("p");
  status.className = "search-status";
  box.append(input, list, status);
  input.addEventListener("input", () => search.setQuery(input.value));
  input.addEventListener("keydown", (e) => onSearchKey(search, e));
  search.subscribe((s) => {
    input.setAttribute("aria-expanded", String(s.open));
    if (s.active >= 0) input.setAttribute("aria-activedescendant", `search-result-${s.active}`);
    else input.removeAttribute("aria-activedescendant");
    list.hidden = !s.open;
    list.replaceChildren(
      ...s.results.map((r, i) => {
        const li = Object.assign(document.createElement("li"), { id: `search-result-${i}` });
        li.setAttribute("role", "option");
        li.setAttribute("aria-selected", String(i === s.active));
        li.append(Object.assign(document.createElement("span"), { textContent: r.label }), Object.assign(document.createElement("small"), { textContent: ` ${r.detail ?? r.provider}` }));
        li.addEventListener("mousedown", (e) => (e.preventDefault(), search.select(i)));
        return li;
      }),
    );
    status.textContent = s.loading ? "検索中…" : s.errors.map((e) => `${e.provider}: ${e.message}`).join(" / ") || (s.query && !s.open && !s.results.length ? "見つかりません" : "");
  });
  pinSelection(map, search, document.body);
  return search;
}
