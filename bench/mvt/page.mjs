const worker = new Worker("/bench/dist/mvt-worker.mjs", { type: "module" });
window.__result = new Promise((resolve) => {
  worker.onmessage = (e) => {
    document.getElementById("log").textContent = JSON.stringify(e.data, null, 2);
    resolve(e.data);
  };
  worker.onerror = (e) => resolve({ error: String(e.message ?? e) });
});
