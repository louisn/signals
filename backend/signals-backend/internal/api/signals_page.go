package api

// signalsPageHTML is a self-contained (no external assets) viewer for
// browsing recent observations, protected by adminBasicAuth. It talks to
// GET /admin/signals.json, which shares the same auth group/browser
// credential cache.
const signalsPageHTML = `<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Signals</title>
<style>
  body { font-family: -apple-system, system-ui, sans-serif; margin: 2rem; color: #222; }
  h1 { font-size: 1.25rem; }
  .filters { margin-bottom: 1rem; display: flex; gap: 0.5rem; align-items: center; }
  .filters input, .filters select { padding: 0.3rem; }
  table { border-collapse: collapse; width: 100%; font-size: 0.85rem; }
  th, td { border-bottom: 1px solid #ddd; padding: 0.4rem 0.6rem; text-align: left; vertical-align: top; }
  th { background: #f5f5f5; position: sticky; top: 0; }
  pre { margin: 0; white-space: pre-wrap; word-break: break-word; max-width: 40rem; }
  .pager { margin-top: 1rem; display: flex; gap: 0.5rem; align-items: center; }
  button { padding: 0.3rem 0.8rem; }
  .empty { color: #888; padding: 1rem 0; }
</style>
</head>
<body>
<h1>Signals &middot; <a href="/admin/signals/heatmap">Heat map</a></h1>
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
  <button id="applyBtn">Apply</button>
</div>
<table>
  <thead>
    <tr><th>Captured At</th><th>Device</th><th>Type</th><th>Lat</th><th>Lon</th><th>Payload</th></tr>
  </thead>
  <tbody id="rows"></tbody>
</table>
<div class="empty" id="empty" style="display:none">No signals found.</div>
<div class="pager">
  <button id="prevBtn">&larr; Prev</button>
  <span id="pageInfo"></span>
  <button id="nextBtn">Next &rarr;</button>
</div>
<script>
const limit = 50;
let offset = 0;

const rowsEl = document.getElementById('rows');
const emptyEl = document.getElementById('empty');
const pageInfoEl = document.getElementById('pageInfo');
const prevBtn = document.getElementById('prevBtn');
const nextBtn = document.getElementById('nextBtn');

function load() {
  const params = new URLSearchParams({ limit, offset });
  const deviceId = document.getElementById('deviceId').value.trim();
  const signalType = document.getElementById('signalType').value;
  if (deviceId) params.set('device_id', deviceId);
  if (signalType) params.set('signal_type', signalType);

  fetch('/admin/signals.json?' + params.toString())
    .then(r => r.json())
    .then(data => {
      rowsEl.innerHTML = '';
      emptyEl.style.display = data.signals.length ? 'none' : 'block';
      for (const s of data.signals) {
        const tr = document.createElement('tr');
        tr.innerHTML =
          '<td>' + s.captured_at + '</td>' +
          '<td>' + s.device_id + '</td>' +
          '<td>' + s.signal_type + '</td>' +
          '<td>' + (s.lat ?? '') + '</td>' +
          '<td>' + (s.lon ?? '') + '</td>' +
          '<td><pre></pre></td>';
        tr.querySelector('pre').textContent = JSON.stringify(s.payload);
        rowsEl.appendChild(tr);
      }
      pageInfoEl.textContent = 'offset ' + offset;
      prevBtn.disabled = offset === 0;
      nextBtn.disabled = !data.has_more;
    });
}

document.getElementById('applyBtn').addEventListener('click', () => { offset = 0; load(); });
prevBtn.addEventListener('click', () => { offset = Math.max(0, offset - limit); load(); });
nextBtn.addEventListener('click', () => { offset += limit; load(); });

load();
</script>
</body>
</html>
`
