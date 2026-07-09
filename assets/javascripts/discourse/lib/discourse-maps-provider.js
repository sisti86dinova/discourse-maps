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

// URL delle librerie esterne (CDN).
const LEAFLET_JS = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js";
const LEAFLET_CSS = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css";

// Vista di default (centro Italia) quando non ci sono coordinate valide.
const DEFAULT_CENTER = { lat: 41.9, lng: 12.5 };
const DEFAULT_ZOOM = 5;
const SINGLE_MARKER_ZOOM = 14;

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
  const latLngs = [];

  points.forEach((m) => {
    const marker = L.marker([m.lat, m.lng]).addTo(map);
    if (m.popupHtml || m.display_name) {
      marker.bindPopup(m.popupHtml || m.display_name);
    }
    latLngs.push([m.lat, m.lng]);
  });

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

  points.forEach((m) => {
    const position = { lat: m.lat, lng: m.lng };
    const marker = new google.maps.Marker({ position, map });

    if (m.popupHtml || m.display_name) {
      const info = new google.maps.InfoWindow({
        content: m.popupHtml || m.display_name,
      });
      marker.addListener("click", () => info.open(map, marker));
    }
    bounds.extend(position);
  });

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

