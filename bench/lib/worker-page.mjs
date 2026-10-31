// Runs the module Worker named by ?worker= and exposes its message as window.__result.
const worker = new Worker(new URLSearchParams(location.search).get("worker"), { type: "module" });
window.__result = new Promise((resolve) => {
  worker.onmessage = (e) => {
    document.getElementById("log").textContent = JSON.stringify(e.data, null, 2);
    resolve(e.data);
  };
  worker.onerror = (e) => resolve({ error: String(e.message ?? e) });
});
