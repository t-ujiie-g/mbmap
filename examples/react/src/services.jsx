// GIS Web services read with mbmap/services in React, over the loader the plain-DOM examples draw with the DOM.
import { useEffect, useState } from "react";
import { createServiceLoader } from "../../shared/services.js";
import { useController } from "./use-controller.js";

/** The service's URL, its layers to add and the overlays added, the loader made once per map. */
export function ServicesPanel({ map }) {
  const [loader] = useState(() => createServiceLoader(map));
  const [url, setUrl] = useState("");
  const s = useController(loader);
  useEffect(() => {
    window.__services = loader;
  }, [loader]);
  const submit = (e) => {
    e.preventDefault();
    if (url) void loader.open(url);
  };
  return (
    <div id="services">
      <form className="service-form" onSubmit={submit}>
        <input type="url" placeholder="WMS・WMTS・ArcGIS の URL" aria-label="サービスの URL" value={url} onChange={(e) => setUrl(e.target.value)} />
        <button>読む</button>
      </form>
      <div className="chips">
        <button disabled={s.loading} onClick={() => void loader.openSample()}>地理院タイル（WMTS）を読む</button>
      </div>
      <p className="hint">{s.title ? `${s.title}：重ねるレイヤーを選ぶ` : ""}</p>
      <div className="chips service-layers">
        {s.choices.map((c) => <button key={c.id} onClick={() => void loader.add(c)}>{c.title}</button>)}
      </div>
      {s.error && <p className="data-error">{s.error}</p>}
      <ul className="datasets">
        {s.items.map((item) => (
          <li key={item.id}>
            <b>{item.name}</b>
            <div className="chips"><button onClick={() => loader.remove(item.id)}>消す</button></div>
          </li>
        ))}
      </ul>
    </div>
  );
}
