/* Annadata map helper: free OpenStreetMap tiles (Leaflet) + free OSRM routing.
   Used by the shop (location pin, order tracking), rider panel (navigation) and admin (stores). */
window.AFMap = (() => {
  "use strict";
  const BASE = "assets/leaflet/";
  const SIKAR = [27.6094, 75.1398];
  let loading = null;

  function load() {
    if (window.L) return Promise.resolve(window.L);
    if (loading) return loading;
    loading = new Promise((res, rej) => {
      const css = document.createElement("link"); css.rel = "stylesheet"; css.href = BASE + "leaflet.css"; document.head.appendChild(css);
      const st = document.createElement("style");
      st.textContent = `.afpin{display:grid;place-items:center;width:38px;height:38px;border-radius:50% 50% 50% 4px;transform:rotate(-45deg);border:2px solid #fff;box-shadow:0 3px 10px rgba(0,0,0,.35);font-size:19px}
.afpin span{transform:rotate(45deg)}.afpin.home{background:#B8862B}.afpin.store{background:#1F4D2B}
.afrider{display:grid;place-items:center;width:40px;height:40px;border-radius:50%;background:#fff;border:3px solid #1F4D2B;box-shadow:0 3px 12px rgba(0,0,0,.35);font-size:21px}
.afme{width:20px;height:20px;border-radius:50%;background:#1A73E8;border:3px solid #fff;box-shadow:0 0 0 6px rgba(26,115,232,.25)}
.leaflet-container{font-family:Mukta,system-ui,sans-serif}`;
      document.head.appendChild(st);
      const js = document.createElement("script"); js.src = BASE + "leaflet.js";
      js.onload = () => res(window.L); js.onerror = () => { loading = null; rej(new Error("MAP_LOAD")); };
      document.head.appendChild(js);
    });
    return loading;
  }

  function make(el, center, zoom) {
    const L = window.L;
    const m = L.map(el, { zoomControl: true, attributionControl: true }).setView(center || SIKAR, zoom || 15);
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", { maxZoom: 19, attribution: "© OpenStreetMap" }).addTo(m);
    setTimeout(() => m.invalidateSize(), 60);
    return m;
  }

  function icon(kind) {
    const L = window.L;
    if (kind === "rider") return L.divIcon({ className: "", html: `<div class="afrider">🛵</div>`, iconSize: [40, 40], iconAnchor: [20, 20] });
    if (kind === "me") return L.divIcon({ className: "", html: `<div class="afme"></div>`, iconSize: [20, 20], iconAnchor: [10, 10] });
    const e = kind === "store" ? "🏪" : "🏠";
    return L.divIcon({ className: "", html: `<div class="afpin ${kind}"><span>${e}</span></div>`, iconSize: [38, 38], iconAnchor: [19, 38] });
  }

  const gmapsDir = (lat, lng) => `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}&travelmode=two-wheeler`;

  function km(a, b) {
    const R = 6371, r = x => x * Math.PI / 180, dLa = r(b[0] - a[0]), dLo = r(b[1] - a[1]);
    const h = Math.sin(dLa / 2) ** 2 + Math.cos(r(a[0])) * Math.cos(r(b[0])) * Math.sin(dLo / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(h));
  }

  // ---- routing (free OSRM server) ----
  async function route(from, to) {
    const url = `https://router.project-osrm.org/route/v1/driving/${from[1]},${from[0]};${to[1]},${to[0]}?overview=full&geometries=geojson&steps=true`;
    const ctl = new AbortController(); const tm = setTimeout(() => ctl.abort(), 9000);
    try {
      const r = await fetch(url, { signal: ctl.signal }); const j = await r.json();
      if (j.code !== "Ok" || !j.routes?.length) throw new Error("NO_ROUTE");
      const rt = j.routes[0];
      const coords = rt.geometry.coordinates.map(c => [c[1], c[0]]);
      const steps = rt.legs[0].steps.map(s => ({ type: s.maneuver.type, mod: s.maneuver.modifier || "", exit: s.maneuver.exit, name: s.name || "", at: [s.maneuver.location[1], s.maneuver.location[0]], dist: s.distance }));
      // map each step to its nearest point on the line so progress can be tracked
      steps.forEach(s => { let best = 0, bd = 1e9; coords.forEach((c, i) => { const d = km(c, s.at); if (d < bd) { bd = d; best = i; } }); s.idx = best; });
      return { coords, steps, km: rt.distance / 1000, min: Math.round(rt.duration / 60) };
    } finally { clearTimeout(tm); }
  }

  // Hinglish turn text
  function say(step, meters) {
    const m = step.mod, t = step.type;
    const dir = { left: "left mudo", right: "right mudo", "slight left": "halka left lo", "slight right": "halka right lo", "sharp left": "tez left mudo", "sharp right": "tez right mudo", straight: "seedha chalo", uturn: "U-turn lo" }[m] || "aage badho";
    let what;
    if (t === "arrive") what = "Pahunch gaye! Customer ka ghar yahin hai";
    else if (t === "depart") what = "Chalna shuru karo";
    else if (t === "roundabout" || t === "rotary") what = `Gol chakkar se ${step.exit || 1}${["", "la", "ra", "ra", "tha"][step.exit] || "va"} raasta lo`;
    else if (t === "fork") what = m.includes("left") ? "Do raste mein left wala lo" : "Do raste mein right wala lo";
    else what = dir;
    const d = meters == null ? "" : meters < 30 ? "Abhi " : meters < 1000 ? `${Math.round(meters / 10) * 10} meter baad ` : `${(meters / 1000).toFixed(1)} km baad `;
    return (t === "arrive" ? (meters != null && meters > 40 ? d : "") : d) + what;
  }
  const arrow = step => ({ left: "⬅️", "slight left": "↖️", "sharp left": "⬅️", right: "➡️", "slight right": "↗️", "sharp right": "➡️", uturn: "↩️", straight: "⬆️" }[step.mod] || (step.type === "arrive" ? "🏁" : "⬆️"));

  // nearest index on the route line and how far the point is from it (km)
  function snap(coords, p) {
    let best = 0, bd = 1e9;
    for (let i = 0; i < coords.length; i++) { const d = km(coords[i], p); if (d < bd) { bd = d; best = i; } }
    return { idx: best, off: bd };
  }
  // nearest segment [i, i+1] on the line: progress is "on segment i"
  function snapSeg(coords, p) {
    const k = Math.cos(p[0] * Math.PI / 180), xy = c => [c[1] * k, c[0]];
    const P = xy(p); let best = 0, bd = 1e9, bp = coords[0];
    for (let i = 0; i < coords.length - 1; i++) {
      const A = xy(coords[i]), B = xy(coords[i + 1]), dx = B[0] - A[0], dy = B[1] - A[1], L2 = dx * dx + dy * dy;
      const t = L2 ? Math.max(0, Math.min(1, ((P[0] - A[0]) * dx + (P[1] - A[1]) * dy) / L2)) : 0;
      const q = [coords[i][0] + (coords[i + 1][0] - coords[i][0]) * t, coords[i][1] + (coords[i + 1][1] - coords[i][1]) * t];
      const d = km(p, q); if (d < bd) { bd = d; best = i; bp = q; }
    }
    return { seg: best, off: bd, at: bp };
  }
  function alongKm(coords, from, to) { let s = 0; for (let i = from; i < to && i < coords.length - 1; i++) s += km(coords[i], coords[i + 1]); return s; }

  return { load, make, icon, gmapsDir, km, route, say, arrow, snap, snapSeg, alongKm, SIKAR };
})();
