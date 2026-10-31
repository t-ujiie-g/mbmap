// <mb-map> from React 19: attributes and properties as props, the element's
// CustomEvents as `on<event>` props. The map's own state stays in the
// element; React only sends camera changes in and listens to moves.
import { StrictMode, useState } from "react";
import { createRoot } from "react-dom/client";
import "mbmap/element";

function App() {
  const [zoom, setZoom] = useState(14.5);
  const [camera, setCamera] = useState(null);
  const current = camera?.zoom ?? zoom;
  return (
    <>
      <mb-map
        style-url="/examples/basic/style.json"
        center="139.7671,35.6812"
        zoom={String(zoom)}
        onmb-load={() => { window.__loaded = performance.now(); }}
        onmb-move={(e) => setCamera({ zoom: e.detail.zoom, center: e.detail.center })}
        style={{ height: "100%" }}
      />
      <div className="panel">
        zoom <output>{current.toFixed(2)}</output>{" "}
        <button onClick={() => setZoom(Math.min(24, current + 1))}>+</button>
        <button onClick={() => setZoom(Math.max(0, current - 1))}>−</button>
      </div>
    </>
  );
}

createRoot(document.getElementById("root")).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
