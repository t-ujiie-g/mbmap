// Files read with mbmap/data in React, over the loader the plain-DOM examples draw with the DOM.
import { useEffect, useState } from "react";
import { WRITE_FORMATS, createDataLoader } from "../../shared/data.js";
import { useController } from "./use-controller.js";

/** The drop zone and the datasets read, the loader made once per map. */
export function DataPanel({ map }) {
  const [loader] = useState(() => createDataLoader(map));
  const [over, setOver] = useState(false);
  const s = useController(loader);
  useEffect(() => {
    window.__data = loader;
  }, [loader]);
  const drop = (e) => {
    e.preventDefault();
    setOver(false);
    void loader.addFiles(e.dataTransfer.files);
  };
  return (
    <div id="data">
      <label className={over ? "drop over" : "drop"} onDragOver={(e) => (e.preventDefault(), setOver(true))} onDragLeave={() => setOver(false)} onDrop={drop}>
        ファイルを選ぶか、ここへドロップ
        <input type="file" multiple onChange={(e) => void loader.addFiles(e.target.files)} />
      </label>
      <div className="chips" style={{ marginTop: 6 }}>
        <button disabled={s.loading} onClick={() => void loader.addSample()}>サンプルを読む</button>
      </div>
      <p className="hint">CSV、Shapefile（zip）、KML/KMZ、GPX、TopoJSON、FlatGeobuf、GeoJSON</p>
      {s.error && <p className="data-error">{s.error}</p>}
      <ul className="datasets">
        {s.items.map((item) => (
          <li key={item.id}>
            <b>{item.name}</b><small>{`  ${item.count} 件`}</small>
            <div className="chips">
              {WRITE_FORMATS.map(([format, label]) => <button key={format} onClick={() => void loader.save(item, format)}>{label}</button>)}
              <button onClick={() => loader.remove(item.id)}>消す</button>
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}
