// The search in React: a bar floating over the map with result cards, from
// the controller the plain-DOM examples draw as a combobox in the panel.
import { useEffect, useState, useSyncExternalStore } from "react";
import { createShowcaseSearch, onSearchKey, pinSelection } from "../../shared/search.js";

export function SearchBar({ map, places }) {
  const [search] = useState(() => {
    const s = createShowcaseSearch(map, places);
    pinSelection(map, s, document.body);
    return s;
  });
  useEffect(() => () => search.destroy(), [search]);
  const s = useSyncExternalStore(search.subscribe, () => search.state);
  // The native event carries `isComposing`, which React's does not.
  const onKeyDown = (e) => onSearchKey(search, e.nativeEvent);
  return (
    <div className="react-search">
      <input
        type="search"
        role="combobox"
        aria-expanded={s.open}
        aria-controls="react-search-results"
        aria-activedescendant={s.active >= 0 ? `react-result-${s.active}` : undefined}
        placeholder="地点名や座標で検索"
        value={s.query}
        onChange={(e) => search.setQuery(e.target.value)}
        onKeyDown={onKeyDown}
      />
      {s.loading && <span className="react-search-loading">…</span>}
      {s.open && (
        <div id="react-search-results" role="listbox" className="react-search-results">
          {s.results.map((r, i) => (
            <div key={i} id={`react-result-${i}`} role="option" aria-selected={i === s.active} onMouseDown={(e) => (e.preventDefault(), search.select(i))}>
              <b>{r.label}</b>
              <span>{r.detail ?? r.provider}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
