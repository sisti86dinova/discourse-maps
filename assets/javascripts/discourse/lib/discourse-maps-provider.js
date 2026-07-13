// ============================================================================
//  Discourse Maps - Astrazione dei provider di mappa e geocoding.
//
//  Questo modulo isola tutta la logica specifica dei due provider supportati:
//    - "locationiq" : tiles OpenStreetMap tramite Leaflet + geocoding REST
//    - "google"     : Google Maps JavaScript API + Geocoder JS
//
//  L'obiettivo è che il resto del plugin (composer, pagina /map) usi sempre le
//  stesse funzioni pubbliche, senza sapere quale provider è attivo:
//    - geocodeAddress(address, siteSettings) -> { lat, lng, display_name }
//    - createMap(element, options)          -> { instance, destroy() }
// ============================================================================

import loadScript from "discourse/lib/load-script";

// Leaflet è vendorizzato nel plugin (public/leaflet/) invece di essere
// caricato da una CDN esterna (unpkg): il forum potrebbe girare dietro una
// rete privata senza accesso a internet per le librerie statiche. I
// provider di geocoding/tiles (LocationIQ, Google, OpenStreetMap) restano
// invece servizi live e richiedono comunque accesso alla rete esterna.
const LEAFLET_JS = "/plugins/discourse-maps/leaflet/leaflet.js";
const LEAFLET_CSS = "/plugins/discourse-maps/leaflet/leaflet.css";

// Vista di default (centro Italia) quando non ci sono coordinate valide.
const DEFAULT_CENTER = { lat: 41.9, lng: 12.5 };
const DEFAULT_ZOOM = 5;
const SINGLE_MARKER_ZOOM = 14;

// Colore di fallback per i marker senza categoria (o categoria senza colore).
const DEFAULT_MARKER_COLOR = "#0088CC";
const MARKER_WIDTH = 25;
const MARKER_HEIGHT = 41;

// Marker con le stesse coordinate (arrotondate a questa precisione, ~1m)
// vengono raggruppati in un unico pin "cluster" con il conteggio.
const CLUSTER_PRECISION = 5;
const CLUSTER_SIZE = 32;
// Raggio (in pixel schermo) usato per disporre i pin quando un cluster
// viene aperto ("spiderfy"): non dipende dallo zoom, così i pin restano
// leggibili e cliccabili anche se le coordinate originali sono identiche.
const SPIDERFY_RADIUS = 45;
const SPIDERFY_RING_CAPACITY = 8;

// ---------------------------------------------------------------------------
//  Marker "a pin" colorato (SVG), usato sia da Leaflet (come divIcon) sia da
//  Google Maps (come icona data-URI): il fill riprende il colore nativo
//  della categoria del topic, con fallback a DEFAULT_MARKER_COLOR.
// ---------------------------------------------------------------------------
function markerSvg(color) {
  const fill = color || DEFAULT_MARKER_COLOR;
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="${MARKER_WIDTH}" height="${MARKER_HEIGHT}" ` +
    `viewBox="0 0 25 41">` +
    `<path fill="${fill}" stroke="#ffffff" stroke-width="1.5" ` +
    `d="M12.5 0C5.6 0 0 5.6 0 12.5 0 20 12.5 41 12.5 41S25 20 25 12.5C25 5.6 19.4 0 12.5 0Z"/>` +
    `<circle cx="12.5" cy="12.5" r="4.5" fill="#ffffff"/>` +
    `</svg>`
  );
}

// ---------------------------------------------------------------------------
//  Marker "a cluster" (cerchio numerato), usato quando più punti condividono
//  le stesse coordinate: mostra quanti topic si trovano in quella posizione.
// ---------------------------------------------------------------------------
function clusterSvg(count, color) {
  const fill = color || DEFAULT_MARKER_COLOR;
  const r = CLUSTER_SIZE / 2;
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="${CLUSTER_SIZE}" height="${CLUSTER_SIZE}" ` +
    `viewBox="0 0 ${CLUSTER_SIZE} ${CLUSTER_SIZE}">` +
    `<circle cx="${r}" cy="${r}" r="${r - 2}" fill="${fill}" stroke="#ffffff" stroke-width="2"/>` +
    `<text x="50%" y="52%" text-anchor="middle" dominant-baseline="middle" ` +
    `fill="#ffffff" font-size="13" font-weight="700" font-family="sans-serif">${count}</text>` +
    `</svg>`
  );
}

// ---------------------------------------------------------------------------
//  Raggruppa i marker che condividono la stessa posizione (coordinate
//  arrotondate a CLUSTER_PRECISION decimali, ~1 metro di tolleranza).
// ---------------------------------------------------------------------------
function groupMarkersByPosition(points) {
  const groups = new Map();
  points.forEach((m) => {
    const key = `${m.lat.toFixed(CLUSTER_PRECISION)},${m.lng.toFixed(CLUSTER_PRECISION)}`;
    if (!groups.has(key)) {
      groups.set(key, []);
    }
    groups.get(key).push(m);
  });
  return [...groups.values()];
}

// ---------------------------------------------------------------------------
//  Calcola gli offset (in pixel) su cui disporre i marker di un cluster
//  aperto, a raggiera su uno o più anelli concentrici a seconda del numero
//  di punti da mostrare.
// ---------------------------------------------------------------------------
function spiderfyOffsets(count) {
  const offsets = [];
  let placed = 0;
  let ring = 0;
  while (placed < count) {
    const ringCount = Math.min(SPIDERFY_RING_CAPACITY + ring * 4, count - placed);
    const radius = SPIDERFY_RADIUS * (ring + 1);
    for (let i = 0; i < ringCount; i++) {
      const angle = (2 * Math.PI * i) / ringCount;
      offsets.push({ dx: radius * Math.cos(angle), dy: radius * Math.sin(angle) });
    }
    placed += ringCount;
    ring++;
  }
  return offsets;
}

// ---------------------------------------------------------------------------
//  Utility: carica un foglio di stile esterno una sola volta.
// ---------------------------------------------------------------------------
function loadCss(url) {
  if (document.querySelector(`link[href="${url}"]`)) {
    return;
  }
  const link = document.createElement("link");
  link.rel = "stylesheet";
  link.href = url;
  document.head.appendChild(link);
}

// ---------------------------------------------------------------------------
//  Caricamento pigro delle librerie dei provider.
// ---------------------------------------------------------------------------
async function ensureLeaflet() {
  loadCss(LEAFLET_CSS);
  await loadScript(LEAFLET_JS);
  return window.L;
}

async function ensureGoogle(apiKey) {
  if (window.google && window.google.maps) {
    return window.google;
  }
  await loadScript(
    `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(apiKey)}`
  );
  return window.google;
}

// ---------------------------------------------------------------------------
//  Costruisce la stringa di ricerca a partire dai campi dell'indirizzo.
// ---------------------------------------------------------------------------
function buildQuery(address) {
  return [
    [address.street, address.house_number].filter(Boolean).join(" "),
    address.postcode,
    address.city,
    address.country,
  ]
    .filter(Boolean)
    .join(", ");
}

// ===========================================================================
//  GEOCODING
// ===========================================================================

// Geocoding tramite l'endpoint REST di LocationIQ (supporta CORS).
async function geocodeLocationIQ(query, apiKey) {
  const url =
    `https://us1.locationiq.com/v1/search?key=${encodeURIComponent(apiKey)}` +
    `&q=${encodeURIComponent(query)}&format=json&limit=1`;

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`LocationIQ error (${response.status})`);
  }

  const data = await response.json();
  if (!data || !data.length) {
    throw new Error("not_found");
  }

  return {
    lat: parseFloat(data[0].lat),
    lng: parseFloat(data[0].lon),
    display_name: data[0].display_name,
  };
}

// Geocoding tramite il Geocoder della Google Maps JS API (evita problemi CORS).
async function geocodeGoogle(query, apiKey) {
  const google = await ensureGoogle(apiKey);
  const geocoder = new google.maps.Geocoder();

  return new Promise((resolve, reject) => {
    geocoder.geocode({ address: query }, (results, status) => {
      if (status === "OK" && results && results[0]) {
        const location = results[0].geometry.location;
        resolve({
          lat: location.lat(),
          lng: location.lng(),
          display_name: results[0].formatted_address,
        });
      } else {
        reject(new Error(status || "not_found"));
      }
    });
  });
}

/**
 * Converte un indirizzo in coordinate usando il provider configurato.
 * @param {Object} address - { street, house_number, postcode, city, country }
 * @param {Object} siteSettings - servizio site-settings di Discourse
 * @returns {Promise<{lat:number, lng:number, display_name:string}>}
 */
export async function geocodeAddress(address, siteSettings) {
  const query = buildQuery(address);
  if (!query) {
    throw new Error("empty_address");
  }

  if (siteSettings.discourse_maps_provider === "google") {
    return geocodeGoogle(query, siteSettings.discourse_maps_google_api_key);
  }
  return geocodeLocationIQ(query, siteSettings.discourse_maps_locationiq_api_key);
}

// ===========================================================================
//  RENDERING DELLA MAPPA
// ===========================================================================

// Normalizza un marker: accetta lat/lng anche come stringhe.
function normalizeMarkers(markers) {
  return (markers || [])
    .map((m) => ({
      ...m,
      lat: parseFloat(m.lat),
      lng: parseFloat(m.lng),
    }))
    .filter((m) => !isNaN(m.lat) && !isNaN(m.lng));
}

// --- Mappa Leaflet (provider LocationIQ / OpenStreetMap) -------------------
async function createLeafletMap(element, { markers, interactive, apiKey }) {
  const L = await ensureLeaflet();

  const map = L.map(element, {
    scrollWheelZoom: interactive,
    dragging: interactive,
    zoomControl: interactive,
    doubleClickZoom: interactive,
  });

  // Se è disponibile la chiave LocationIQ usiamo i suoi tiles, altrimenti
  // ricadiamo sui tiles standard di OpenStreetMap.
  const tileUrl = apiKey
    ? `https://{s}-tiles.locationiq.com/v3/streets/r/{z}/{x}/{y}.png?key=${apiKey}`
    : "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png";

  L.tileLayer(tileUrl, {
    subdomains: "abc",
    maxZoom: 19,
    attribution:
      '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
  }).addTo(map);

  const points = normalizeMarkers(markers);
  const latLngs = points.map((m) => [m.lat, m.lng]);

  function addLeafletMarker(m) {
    const icon = L.divIcon({
      className: "discourse-maps-marker",
      html: markerSvg(m.color),
      iconSize: [MARKER_WIDTH, MARKER_HEIGHT],
      iconAnchor: [MARKER_WIDTH / 2, MARKER_HEIGHT],
      popupAnchor: [0, -MARKER_HEIGHT + 6],
    });

    const marker = L.marker([m.lat, m.lng], { icon }).addTo(map);
    if (m.popupHtml || m.display_name) {
      marker.bindPopup(m.popupHtml || m.display_name);
    }
    // Evita che il click sul pin si propaghi alla mappa: altrimenti il
    // listener di chiusura dei cluster (più sotto) richiuderebbe subito lo
    // "spiderfy" appena apparso.
    marker.on("click", (e) => L.DomEvent.stopPropagation(e));
    return marker;
  }

  // Cluster: un solo pin numerato per ogni posizione con più marker. Al
  // click si "apre" mostrando i singoli pin disposti a raggiera attorno al
  // punto, così l'utente può scegliere quello desiderato anche quando le
  // coordinate originali coincidono esattamente.
  const openClusters = [];

  function addLeafletCluster(group) {
    const center = L.latLng(group[0].lat, group[0].lng);
    const clusterIcon = L.divIcon({
      className: "discourse-maps-cluster",
      html: clusterSvg(group.length, group[0].color),
      iconSize: [CLUSTER_SIZE, CLUSTER_SIZE],
      iconAnchor: [CLUSTER_SIZE / 2, CLUSTER_SIZE / 2],
    });
    const clusterMarker = L.marker(center, {
      icon: clusterIcon,
      zIndexOffset: 1000,
    }).addTo(map);

    let spiderMarkers = [];
    let spiderLegs = [];
    let open = false;

    function collapse() {
      if (!open) {
        return;
      }
      spiderMarkers.forEach((mk) => map.removeLayer(mk));
      spiderLegs.forEach((leg) => map.removeLayer(leg));
      spiderMarkers = [];
      spiderLegs = [];
      open = false;
      clusterMarker.setOpacity(1);
    }

    function expand() {
      const centerPoint = map.latLngToLayerPoint(center);
      const offsets = spiderfyOffsets(group.length);
      group.forEach((m, i) => {
        const point = centerPoint.add(L.point(offsets[i].dx, offsets[i].dy));
        const latlng = map.layerPointToLatLng(point);
        spiderMarkers.push(addLeafletMarker({ ...m, lat: latlng.lat, lng: latlng.lng }));
        spiderLegs.push(
          L.polyline([center, latlng], {
            color: "#999999",
            weight: 1,
            dashArray: "3,4",
            interactive: false,
          }).addTo(map)
        );
      });
      clusterMarker.setOpacity(0.6);
      open = true;
    }

    clusterMarker.on("click", (e) => {
      L.DomEvent.stopPropagation(e);
      if (open) {
        collapse();
      } else {
        openClusters.forEach((c) => c !== api && c.collapse());
        expand();
      }
    });

    // Coordinate schermo diverse dopo uno zoom/pan: richiudiamo per evitare
    // pin posizionati in punti non più coerenti con il cluster.
    map.on("zoomstart movestart", collapse);

    const api = { collapse };
    openClusters.push(api);
  }

  groupMarkersByPosition(points).forEach((group) => {
    if (group.length > 1) {
      addLeafletCluster(group);
    } else {
      addLeafletMarker(group[0]);
    }
  });

  // Click su un punto vuoto della mappa: richiude eventuali cluster aperti.
  map.on("click", () => openClusters.forEach((c) => c.collapse()));

  if (latLngs.length === 1) {
    map.setView(latLngs[0], SINGLE_MARKER_ZOOM);
  } else if (latLngs.length > 1) {
    map.fitBounds(latLngs, { padding: [30, 30] });
  } else {
    map.setView([DEFAULT_CENTER.lat, DEFAULT_CENTER.lng], DEFAULT_ZOOM);
  }

  // Leaflet a volte calcola male le dimensioni se il contenitore era nascosto:
  // forziamo un ricalcolo appena possibile.
  setTimeout(() => map.invalidateSize(), 200);

  return { instance: map, destroy: () => map.remove() };
}

// Google Maps non espone direttamente la conversione lat/lng -> pixel
// schermo: serve un OverlayView "invisibile" per ottenere la projection
// dopo il primo giro di rendering della mappa.
function getGoogleProjection(google, map) {
  return new Promise((resolve) => {
    const helper = new google.maps.OverlayView();
    helper.onAdd = () => {};
    helper.onRemove = () => {};
    helper.draw = function () {
      resolve(this.getProjection());
    };
    helper.setMap(map);
  });
}

// --- Mappa Google Maps -----------------------------------------------------
async function createGoogleMap(element, { markers, interactive, apiKey }) {
  const google = await ensureGoogle(apiKey);

  const map = new google.maps.Map(element, {
    center: DEFAULT_CENTER,
    zoom: DEFAULT_ZOOM,
    gestureHandling: interactive ? "auto" : "none",
    disableDefaultUI: !interactive,
    zoomControl: interactive,
  });

  const points = normalizeMarkers(markers);
  const bounds = new google.maps.LatLngBounds();
  points.forEach((m) => bounds.extend({ lat: m.lat, lng: m.lng }));

  const projectionPromise = getGoogleProjection(google, map);

  // Un solo InfoWindow alla volta: prima di aprire quello di un pin chiudiamo
  // l'eventuale popup lasciato aperto da un click precedente.
  let activeInfoWindow = null;

  function addGoogleMarker(m) {
    const position = { lat: m.lat, lng: m.lng };
    const icon = {
      url: `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(markerSvg(m.color))}`,
      scaledSize: new google.maps.Size(MARKER_WIDTH, MARKER_HEIGHT),
      anchor: new google.maps.Point(MARKER_WIDTH / 2, MARKER_HEIGHT),
    };
    const marker = new google.maps.Marker({ position, map, icon });

    if (m.popupHtml || m.display_name) {
      const info = new google.maps.InfoWindow({
        content: m.popupHtml || m.display_name,
      });
      marker.addListener("click", () => {
        activeInfoWindow?.close();
        info.open(map, marker);
        activeInfoWindow = info;
      });
    }
    return marker;
  }

  // Cluster: un solo pin numerato per ogni posizione con più marker. Al
  // click si "apre" mostrando i singoli pin disposti a raggiera attorno al
  // punto (i click sui marker di Google non si propagano alla mappa, quindi
  // non serve stopPropagation come in Leaflet).
  const openClusters = [];

  function addGoogleCluster(group) {
    const center = { lat: group[0].lat, lng: group[0].lng };
    const clusterIcon = {
      url: `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(clusterSvg(group.length, group[0].color))}`,
      scaledSize: new google.maps.Size(CLUSTER_SIZE, CLUSTER_SIZE),
      anchor: new google.maps.Point(CLUSTER_SIZE / 2, CLUSTER_SIZE / 2),
    };
    const clusterMarker = new google.maps.Marker({
      position: center,
      map,
      icon: clusterIcon,
      zIndex: 1000,
    });

    let spiderMarkers = [];
    let spiderLegs = [];
    let open = false;

    function collapse() {
      if (!open) {
        return;
      }
      spiderMarkers.forEach((mk) => mk.setMap(null));
      spiderLegs.forEach((leg) => leg.setMap(null));
      spiderMarkers = [];
      spiderLegs = [];
      open = false;
      clusterMarker.setOpacity(1);
    }

    async function expand() {
      const projection = await projectionPromise;
      const centerLatLng = new google.maps.LatLng(center);
      const centerPoint = projection.fromLatLngToDivPixel(centerLatLng);
      const offsets = spiderfyOffsets(group.length);
      group.forEach((m, i) => {
        const point = new google.maps.Point(
          centerPoint.x + offsets[i].dx,
          centerPoint.y + offsets[i].dy
        );
        const latlng = projection.fromDivPixelToLatLng(point);
        spiderMarkers.push(addGoogleMarker({ ...m, lat: latlng.lat(), lng: latlng.lng() }));
        spiderLegs.push(
          new google.maps.Polyline({
            path: [centerLatLng, latlng],
            strokeColor: "#999999",
            strokeOpacity: 0.8,
            strokeWeight: 1,
            clickable: false,
            map,
          })
        );
      });
      clusterMarker.setOpacity(0.6);
      open = true;
    }

    clusterMarker.addListener("click", () => {
      if (open) {
        collapse();
      } else {
        openClusters.forEach((c) => c !== api && c.collapse());
        expand();
      }
    });

    // Coordinate schermo diverse dopo uno zoom: richiudiamo per evitare pin
    // posizionati in punti non più coerenti con il cluster.
    map.addListener("zoom_changed", collapse);
    map.addListener("dragstart", collapse);

    const api = { collapse };
    openClusters.push(api);
  }

  groupMarkersByPosition(points).forEach((group) => {
    if (group.length > 1) {
      addGoogleCluster(group);
    } else {
      addGoogleMarker(group[0]);
    }
  });

  // Click su un punto vuoto della mappa: richiude eventuali cluster aperti.
  map.addListener("click", () => openClusters.forEach((c) => c.collapse()));

  if (points.length === 1) {
    map.setCenter(bounds.getCenter());
    map.setZoom(SINGLE_MARKER_ZOOM);
  } else if (points.length > 1) {
    map.fitBounds(bounds);
  }

  return { instance: map, destroy: () => {} };
}

/**
 * Crea una mappa nel contenitore indicato usando il provider configurato.
 * @param {HTMLElement} element - il div che ospiterà la mappa
 * @param {Object} options - { provider, apiKey, markers, interactive }
 * @returns {Promise<{instance:Object, destroy:Function}>}
 */
export async function createMap(element, options) {
  const opts = { interactive: true, markers: [], ...options };

  if (opts.provider === "google") {
    return createGoogleMap(element, opts);
  }
  return createLeafletMap(element, opts);
}

