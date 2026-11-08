// The places' attribute table and its field form in React, from the controllers the plain-DOM
// examples draw with the same shared helpers.
import { useEffect, useState } from "react";
import { cellText } from "mbmap/ui";
import { FIELD_ACTIONS, FIELD_DEFAULTS, FIELD_PLACEHOLDERS, chooseRow, createPlacesFields, createPlacesTable, onTableKey, runField, sortOf, tableCounts, tableHeadings } from "../../shared/table.js";
import { useController } from "./use-controller.js";

/** The table, its controller made once per map. */
export function AttributeTable({ map }) {
  const [table, setTable] = useState(null);
  useEffect(() => {
    const t = createPlacesTable(map);
    setTable({ table: t, fields: createPlacesFields(map, t) });
    return () => t.destroy();
  }, [map]);
  return table && <Table table={table.table} fields={table.fields} />;
}

function Table({ table, fields }) {
  const s = useController(table);
  const c = tableCounts(s);
  const [form, setForm] = useState(FIELD_DEFAULTS);
  const [status, setStatus] = useState("");
  return (
    <div id="table">
      {/* The native event carries `isComposing`, which React's does not. */}
      <input type="search" placeholder="名前や種別で絞り込む" value={s.query} onChange={(e) => table.setQuery(e.target.value)} onKeyDown={(e) => onTableKey(table, e.nativeEvent)} />
      <table className="attributes">
        <thead>
          <tr>
            {tableHeadings(s).map(([key, title]) => {
              const sort = sortOf(s, key);
              return (
                <th key={key} aria-sort={sort.aria}>
                  <button onClick={() => table.setSort(key)}>{title + sort.mark}</button>
                </th>
              );
            })}
          </tr>
        </thead>
        <tbody>
          {s.rows.map((row, i) => (
            <tr key={row.id ?? `#${i}`} aria-selected={row.id !== null && s.selected.includes(String(row.id))} onClick={(e) => chooseRow(table, row, e.nativeEvent)}>
              {s.columns.map((key) => <td key={key}>{cellText(row.properties[key])}</td>)}
            </tr>
          ))}
        </tbody>
      </table>
      <div className="table-pager">
        <button disabled={s.page === 0} onClick={() => table.previous()}>◀</button>
        <span>{c.page}</span>
        <button disabled={s.page >= s.pages - 1} onClick={() => table.next()}>▶</button>
        <span className="table-count">{c.count}</span>
      </div>
      <div className="field-form">
        {Object.keys(FIELD_DEFAULTS).map((k) => <input key={k} id={`field-${k}`} placeholder={FIELD_PLACEHOLDERS[k]} value={form[k]} onChange={(e) => setForm({ ...form, [k]: e.target.value })} />)}
        <div className="chips">
          {FIELD_ACTIONS.map(([action, label]) => <button key={action} data-field={action} onClick={async () => setStatus(await runField(fields, action, form))}>{label}</button>)}
        </div>
        <p id="field-status" className="hint">{status}</p>
      </div>
    </div>
  );
}
