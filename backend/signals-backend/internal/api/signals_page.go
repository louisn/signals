package api

// signalsPageHTML is a self-contained (no external assets) viewer for
// browsing recent observations, protected by adminBasicAuth. It talks to
// GET /admin/signals.json, which shares the same auth group/browser
// credential cache.
const signalsPageHTML = `<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Signals</title>
<style>
  * { box-sizing: border-box; }
  body { font-family: -apple-system, system-ui, sans-serif; margin: 1rem; color: #222; }
  h1 { font-size: 1.1rem; margin: 0 0 0.75rem; }
  h1 a { white-space: nowrap; }
  .filters { margin-bottom: 0.75rem; display: flex; flex-wrap: wrap; gap: 0.5rem; align-items: center; }
  .filters label { display: flex; flex-direction: column; font-size: 0.8rem; color: #555; gap: 0.15rem; }
  .filters input, .filters select { padding: 0.5rem; font-size: 1rem; }
  #deviceId { min-width: 12rem; }
  .pager { display: flex; flex-wrap: wrap; gap: 0.5rem; align-items: center; margin-bottom: 0.75rem; }
  .pager .info { font-size: 0.85rem; color: #555; }
  button { padding: 0.5rem 0.9rem; font-size: 1rem; }
  .scroll { overflow-x: auto; -webkit-overflow-scrolling: touch; border: 1px solid #eee; border-radius: 6px; }
  table { border-collapse: collapse; width: 100%; font-size: 0.8rem; }
  th, td { border-bottom: 1px solid #ddd; padding: 0.5rem 0.6rem; text-align: left; vertical-align: top; }
  th { background: #f5f5f5; position: sticky; top: 0; white-space: nowrap; }
  td.mono { font-variant-numeric: tabular-nums; }
  pre { margin: 0; white-space: pre-wrap; word-break: break-word; max-width: 60vw; font-size: 0.75rem; }
  .empty { color: #888; padding: 1rem 0; }
  @media (max-width: 600px) {
    body { margin: 0.6rem; }
    .filters { flex-direction: column; align-items: stretch; }
    .filters label { width: 100%; }
    .filters input, .filters select { width: 100%; }
    pre { max-width: 78vw; }
  }
</style>
</head>
<body>
<h1>Signals &middot; <a href="/admin/signals/heatmap">Heat map</a> &middot; <a href="/admin/ai">AI summary</a></h1>
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
  <button id="applyBtn">Apply</button>
</div>
<div class="pager">
  <button id="prevBtn">&larr; Prev</button>
  <button id="nextBtn">Next &rarr;</button>
  <span class="info" id="pageInfo"></span>
</div>
<div class="scroll">
  <table>
    <thead>
      <tr><th>Captured At</th><th>Device</th><th>Type</th><th>Lat</th><th>Lon</th><th>Payload</th></tr>
    </thead>
    <tbody id="rows"></tbody>
  </table>
</div>
<div class="empty" id="empty" style="display:none">No signals found.</div>
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
          '<td class="mono">' + s.captured_at + '</td>' +
          '<td>' + s.device_id + '</td>' +
          '<td>' + s.signal_type + '</td>' +
          '<td class="mono">' + (s.lat ?? '') + '</td>' +
          '<td class="mono">' + (s.lon ?? '') + '</td>' +
          '<td><pre></pre></td>';
        tr.querySelector('pre').textContent = JSON.stringify(s.payload);
        rowsEl.appendChild(tr);
      }
      const start = data.total === 0 ? 0 : offset + 1;
      const end = offset + data.signals.length;
      pageInfoEl.textContent = start + '–' + end + ' of ' + data.total + ' rows';
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
