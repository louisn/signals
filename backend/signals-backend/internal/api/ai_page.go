package api

// aiPageHTML is a self-contained (no external assets) natural-language
// summary/Q&A viewer, protected by adminBasicAuth. It talks to
// GET /admin/ai/summary.json and POST /admin/ai/ask, which share the same
// auth group/browser credential cache.
const aiPageHTML = `<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Signals AI Summary</title>
<style>
  * { box-sizing: border-box; }
  body { font-family: -apple-system, system-ui, sans-serif; margin: 1rem; color: #222; max-width: 48rem; }
  h1 { font-size: 1.1rem; }
  h1 a { white-space: nowrap; }
  .filters { margin-bottom: 0.5rem; display: flex; gap: 0.5rem; align-items: center; flex-wrap: wrap; }
  .filters label { display: flex; flex-direction: column; font-size: 0.8rem; color: #555; gap: 0.15rem; }
  .filters input, .filters select { padding: 0.5rem; font-size: 1rem; }
  #deviceId { min-width: 12rem; }
  button { padding: 0.5rem 0.9rem; font-size: 1rem; }
  section { margin-bottom: 1.75rem; }
  textarea { width: 100%; padding: 0.5rem; font: inherit; font-size: 1rem; }
  .output { white-space: pre-wrap; word-break: break-word; background: #f5f5f5; border-radius: 6px; padding: 0.8rem; margin-top: 0.75rem; min-height: 1.5rem; }
  .error { color: #b00020; }
  .hint { color: #888; font-size: 0.85rem; }
  @media (max-width: 600px) {
    body { margin: 0.6rem; }
    .filters { flex-direction: column; align-items: stretch; }
    .filters label, .filters input, .filters select { width: 100%; }
    button { width: 100%; }
  }
</style>
</head>
<body>
<h1>Signals AI &middot; <a href="/admin/signals">Table view</a> &middot; <a href="/admin/signals/heatmap">Heat map</a></h1>
<div class="filters">
  <label>Device ID <input id="deviceId" placeholder="uuid"></label>
  <label>Type
    <select id="signalType">
      <option value="">all</option>
      <option value="location">location</option>
      <option value="ble_advertisement">ble_advertisement</option>
      <option value="network_metadata">network_metadata</option>
      <option value="wifi_scan">wifi_scan</option>
      <option value="cell_info">cell_info</option>
    </select>
  </label>
</div>
<span class="hint">Filters apply to both the summary and questions below.</span>

<section>
  <h2>Summary</h2>
  <button id="summarizeBtn">Generate summary</button>
  <div class="output" id="summaryOutput"></div>
</section>

<section>
  <h2>Ask a question</h2>
  <textarea id="question" rows="3" placeholder="e.g. Which device has been seen in the most locations this week?"></textarea>
  <div>
    <button id="askBtn">Ask</button>
  </div>
  <div class="output" id="askOutput"></div>
</section>

<script>
function currentFilters() {
  const params = new URLSearchParams();
  const deviceId = document.getElementById('deviceId').value.trim();
  const signalType = document.getElementById('signalType').value;
  if (deviceId) params.set('device_id', deviceId);
  if (signalType) params.set('signal_type', signalType);
  return { deviceId, signalType, params };
}

function showOutput(el, text, isError) {
  el.textContent = text;
  el.classList.toggle('error', !!isError);
}

document.getElementById('summarizeBtn').addEventListener('click', () => {
  const out = document.getElementById('summaryOutput');
  const { params } = currentFilters();
  showOutput(out, 'Generating...', false);
  fetch('/admin/ai/summary.json?' + params.toString())
    .then(r => r.json().then(data => ({ ok: r.ok, data })))
    .then(({ ok, data }) => showOutput(out, ok ? data.summary : 'Error: ' + data.error, !ok))
    .catch(err => showOutput(out, 'Error: ' + err, true));
});

document.getElementById('askBtn').addEventListener('click', () => {
  const out = document.getElementById('askOutput');
  const question = document.getElementById('question').value.trim();
  if (!question) { showOutput(out, 'Enter a question first.', true); return; }
  const { deviceId, signalType } = currentFilters();
  showOutput(out, 'Thinking...', false);
  fetch('/admin/ai/ask', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ question, device_id: deviceId, signal_type: signalType }),
  })
    .then(r => r.json().then(data => ({ ok: r.ok, data })))
    .then(({ ok, data }) => showOutput(out, ok ? data.answer : 'Error: ' + data.error, !ok))
    .catch(err => showOutput(out, 'Error: ' + err, true));
});
</script>
</body>
</html>
`
