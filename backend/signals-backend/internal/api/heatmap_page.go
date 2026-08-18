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
<title>Signals Heat Map</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<style>
  body { font-family: -apple-system, system-ui, sans-serif; margin: 0; color: #222; }
  h1 { font-size: 1.1rem; margin: 0.75rem 1rem; }
  .filters { margin: 0 1rem 0.75rem; display: flex; gap: 0.5rem; align-items: center; }
  .filters input, .filters select { padding: 0.3rem; }
  #map { height: calc(100vh - 4.5rem); width: 100%; }
  .empty { margin: 0 1rem; color: #888; }
</style>
</head>
<body>
<h1>Signals Heat Map &middot; <a href="/admin/signals">Table view</a></h1>
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

      const maxCount = data.points.reduce((m, p) => Math.max(m, p.count), 1);
      const heatPoints = data.points.map(p => [p.lat, p.lon, p.count / maxCount]);

      if (heatLayer) map.removeLayer(heatLayer);
      heatLayer = L.heatLayer(heatPoints, { radius: 20, blur: 15, maxZoom: 17 }).addTo(map);

      if (!hasFitBounds && data.points.length) {
        const bounds = L.latLngBounds(data.points.map(p => [p.lat, p.lon]));
        map.fitBounds(bounds, { maxZoom: 14 });
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
