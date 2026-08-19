package api

// heatmapPageHTML is a heat map viewer for observation density, protected by
// adminBasicAuth. It talks to GET /admin/signals/heatmap.json, which shares
// the same auth group/browser credential cache. Unlike signals_page.go this
// pulls Leaflet + the leaflet.heat plugin from a CDN -- rendering an actual
// map already requires fetching tile images over the network, so there's no
// "fully self-contained" option here regardless.
const heatmapPageHTML = `<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Signals Heat Map</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<style>
  * { box-sizing: border-box; }
  body { font-family: -apple-system, system-ui, sans-serif; margin: 0; color: #222;
         display: flex; flex-direction: column; height: 100vh; }
  h1 { font-size: 1.1rem; margin: 0.6rem 0.75rem 0.4rem; }
  h1 a { white-space: nowrap; }
  .filters { margin: 0 0.75rem 0.6rem; display: flex; flex-wrap: wrap; gap: 0.5rem; align-items: center; }
  .filters label { display: flex; flex-direction: column; font-size: 0.8rem; color: #555; gap: 0.15rem; }
  .filters input, .filters select { padding: 0.5rem; font-size: 1rem; }
  #deviceId { min-width: 12rem; }
  button { padding: 0.5rem 0.9rem; font-size: 1rem; }
  #count { font-size: 0.85rem; color: #555; }
  #map { flex: 1; min-height: 0; width: 100%; }
  .empty { margin: 0 0.75rem 0.6rem; color: #888; }
  @media (max-width: 600px) {
    .filters { flex-direction: column; align-items: stretch; }
    .filters label, .filters input, .filters select, .filters button { width: 100%; }
  }
</style>
</head>
<body>
<h1>Signals Heat Map &middot; <a href="/admin/signals">Table view</a> &middot; <a href="/admin/ai">AI summary</a></h1>
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
  <label>Grid
    <select id="precision">
      <option value="2">~1km</option>
      <option value="3" selected>~100m</option>
      <option value="4">~10m</option>
    </select>
  </label>
  <button id="applyBtn">Apply</button>
  <span id="count"></span>
</div>
<div class="empty" id="empty" style="display:none">No located signals found.</div>
<div id="map"></div>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<script src="https://unpkg.com/leaflet.heat@0.2.0/dist/leaflet-heat.js"></script>
<script>
const map = L.map('map').setView([0, 0], 2);
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
  attribution: '&copy; OpenStreetMap contributors',
  maxZoom: 19,
}).addTo(map);

let heatLayer = null;
let hasFitBounds = false;

function load() {
  const params = new URLSearchParams();
  const deviceId = document.getElementById('deviceId').value.trim();
  const signalType = document.getElementById('signalType').value;
  const precision = document.getElementById('precision').value;
  if (deviceId) params.set('device_id', deviceId);
  if (signalType) params.set('signal_type', signalType);
  params.set('precision', precision);

  fetch('/admin/signals/heatmap.json?' + params.toString())
    .then(r => r.json())
    .then(data => {
      document.getElementById('empty').style.display = data.points.length ? 'none' : 'block';
      document.getElementById('count').textContent = data.points.length + ' grid cells';

      // Log-scale intensity so a handful of outlier-dense cells don't wash
      // out everything else down near minOpacity -- with raw linear counts,
      // one cell with 300 observations makes every cell with 1-5 essentially
      // invisible even though it's still a real data point worth seeing.
      const maxLog = data.points.reduce((m, p) => Math.max(m, Math.log1p(p.count)), 1);
      const heatPoints = data.points.map(p => [p.lat, p.lon, Math.log1p(p.count) / maxLog]);

      if (heatLayer) map.removeLayer(heatLayer);
      heatLayer = L.heatLayer(heatPoints, {
        radius: 30,
        blur: 20,
        maxZoom: 17,
        minOpacity: 0.45,
        gradient: { 0.2: '#2c7bb6', 0.4: '#abd9e9', 0.6: '#ffffbf', 0.8: '#fdae61', 1.0: '#d7191c' },
      }).addTo(map);

      if (!hasFitBounds && data.points.length) {
        const bounds = L.latLngBounds(data.points.map(p => [p.lat, p.lon]));
        // A tiny cluster of points makes fitBounds pick a barely-zoomed-in
        // view since the bounds themselves are minuscule -- pad it out so a
        // single cell isn't rendered as a speck on a half-world map.
        map.fitBounds(bounds.pad(0.5), { maxZoom: 15 });
        hasFitBounds = true;
      }
    });
}

document.getElementById('applyBtn').addEventListener('click', load);
load();
</script>
</body>
</html>
`
