package api

// aiPageHTML is a self-contained (no external assets) natural-language
// summary/Q&A viewer, protected by adminBasicAuth. It talks to
// GET /admin/ai/summary.json and POST /admin/ai/ask, which share the same
// auth group/browser credential cache.
const aiPageHTML = `<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Signals AI Summary</title>
<style>
  body { font-family: -apple-system, system-ui, sans-serif; margin: 2rem; color: #222; max-width: 48rem; }
  h1 { font-size: 1.25rem; }
  .filters { margin-bottom: 1rem; display: flex; gap: 0.5rem; align-items: center; flex-wrap: wrap; }
  .filters input, .filters select { padding: 0.3rem; }
  button { padding: 0.4rem 0.9rem; }
  section { margin-bottom: 2rem; }
  textarea { width: 100%; box-sizing: border-box; padding: 0.5rem; font: inherit; }
  .output { white-space: pre-wrap; background: #f5f5f5; border-radius: 6px; padding: 0.8rem; margin-top: 0.75rem; min-height: 1.5rem; }
  .error { color: #b00020; }
  .hint { color: #888; font-size: 0.85rem; }
</style>
</head>
<body>
<h1>Signals AI &middot; <a href="/admin/signals">Table view</a> &middot; <a href="/admin/signals/heatmap">Heat map</a></h1>
<div class="filters">
  <label>Device ID <input id="deviceId" placeholder="uuid" size="36"></label>
  <label>Type
    <select id="signalType">
      <option value="">all</option>
      <option value="location">location</option>
      <option value="ble_advertisement">ble_advertisement</option>
      <option value="network_metadata">network_metadata</option>
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
