// The search in React: the combobox of the plain-DOM examples, from the same controller.
import { useEffect, useState } from "react";
import { createShowcaseSearch, onSearchKey, pinSelection } from "../../shared/search.js";
import { useController } from "./use-controller.js";

export function SearchBar({ map, places }) {
  const [search] = useState(() => {
    const s = createShowcaseSearch(map, places);
    pinSelection(map, s, document.body);
    return s;
  });
  useEffect(() => () => search.destroy(), [search]);
  const s = useController(search);
  const status = s.loading ? "検索中…" : s.errors.map((e) => `${e.provider}: ${e.message}`).join(" / ") || (s.query && !s.open && !s.results.length ? "見つかりません" : "");
  return (
    <div id="search">
      <input
        type="search"
        role="combobox"
        aria-autocomplete="list"
        aria-expanded={s.open}
        aria-controls="search-results"
        aria-activedescendant={s.active >= 0 ? `search-result-${s.active}` : undefined}
        placeholder="地点名や座標で検索"
        value={s.query}
        onChange={(e) => search.setQuery(e.target.value)}
        onKeyDown={(e) => onSearchKey(search, e.nativeEvent)}
      />
      {s.open && (
        <ul id="search-results" role="listbox">
          {s.results.map((r, i) => (
            <li key={i} id={`search-result-${i}`} role="option" aria-selected={i === s.active} onMouseDown={(e) => (e.preventDefault(), search.select(i))}>
              <span>{r.label}</span>
              <small>{` ${r.detail ?? r.provider}`}</small>
            </li>
          ))}
        </ul>
      )}
      <p className="search-status">{status}</p>
    </div>
  );
}
