// ============================================================================
//  Discourse Maps - Abstraction of the map and geocoding providers.
//
//  This module isolates all the logic specific to the two supported
//  providers:
//    - "locationiq" : OpenStreetMap tiles via Leaflet + REST geocoding
//    - "google"     : Google Maps JavaScript API + Geocoder JS
//
//  The goal is for the rest of the plugin (composer, /map page) to always
//  use the same public functions, without knowing which provider is active:
//    - geocodeAddress(address, siteSettings) -> { lat, lng, display_name }
//    - createMap(element, options)          -> { instance, destroy() }
// ============================================================================

import loadScript from "discourse/lib/load-script";

// Leaflet is vendored in the plugin (public/leaflet/) instead of being
// loaded from an external CDN (unpkg): the forum might run behind a
// private network without internet access for static libraries. The
// geocoding/tile providers (LocationIQ, Google, OpenStreetMap) remain
// live services and still require access to the external network.
const LEAFLET_JS = "/plugins/discourse-maps/leaflet/leaflet.js";
const LEAFLET_CSS = "/plugins/discourse-maps/leaflet/leaflet.css";

// Default view (center of Italy) when there are no valid coordinates.
const DEFAULT_CENTER = { lat: 41.9, lng: 12.5 };
const DEFAULT_ZOOM = 5;
// Exported: the topic's static map uses the same zoom for visual
// consistency with the single-marker interactive map.
export const SINGLE_MARKER_ZOOM = 15;

// Fallback color for markers without a category (or a category with no color).
// Exported because the pin overlaid on the static map (on the topic page)
// must also have the same fallback size/color as the interactive map's markers.
export const DEFAULT_MARKER_COLOR = "#0088CC";
export const MARKER_WIDTH = 25;
export const MARKER_HEIGHT = 41;

// Markers with the same coordinates (rounded to this precision, ~1m) are
// grouped into a single numbered "cluster" pin.
const CLUSTER_PRECISION = 5;
const CLUSTER_SIZE = 32;
// Radius (in screen pixels) used to lay out the pins when an opened
// cluster is "spiderfied": it doesn't depend on the zoom level, so the
// pins stay readable and clickable even if the original coordinates are
// identical.
const SPIDERFY_RADIUS = 45;
const SPIDERFY_RING_CAPACITY = 8;

// ---------------------------------------------------------------------------
//  Colored "pin" marker (SVG), used both by Leaflet (as a divIcon) and by
//  Google Maps (as a data-URI icon): the fill matches the topic category's
//  native color, falling back to DEFAULT_MARKER_COLOR.
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
//  "Cluster" marker (numbered circle), used when multiple points share the
//  same coordinates: shows how many topics are at that location.
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
//  Groups the markers that share the same position (coordinates rounded to
//  CLUSTER_PRECISION decimals, ~1 meter of tolerance).
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
//  Computes the offsets (in pixels) used to lay out the markers of an
//  opened cluster, radially over one or more concentric rings depending on
//  how many points need to be shown.
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
//  Utility: loads an external stylesheet only once.
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
//  Lazy loading of the provider libraries.
// ---------------------------------------------------------------------------
async function ensureLeaflet() {
  loadCss(LEAFLET_CSS);
  await loadScript(LEAFLET_JS);
  return window.L;
}

async function ensureGoogle(apiKey, language) {
  if (window.google && window.google.maps) {
    return window.google;
  }
  const langParam = language ? `&language=${encodeURIComponent(language)}` : "";
  await loadScript(
    `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(apiKey)}${langParam}`
  );
  return window.google;
}

// ===========================================================================
//  GEOCODING
// ===========================================================================
//  The user enters the full address in a single free-text field: it's the
//  provider (LocationIQ/Nominatim or Google) that interprets it and
//  returns, besides the coordinates, the structured components from which
//  we extract the country (used by the /map page's country filter).
//
//  The country name is NOT taken as-is from the provider's response: the
//  language of that string depends on the language of the typed address
//  and on the request's preferences (e.g. "Italy" if the user writes
//  "... bologna italy"), which would create duplicates in the country
//  filter ("Italia" / "Italy"). Instead we take the country's ISO 3166-1
//  alpha-2 code and translate it into the site's language with
//  Intl.DisplayNames: the stored name is thus always canonical and in a
//  single language.
// ===========================================================================

// Site language (e.g. "it"), used for geocoding requests and for the
// country name. Discourse's locale uses an underscore (e.g. "en_GB"), the
// Intl constructors and the providers want a hyphen.
function siteLocale(siteSettings) {
  return (siteSettings.default_locale || "en").replace("_", "-");
}

// Converts an ISO 3166-1 alpha-2 code (e.g. "IT") into the country name in
// the given language (e.g. "Italia"). Returns null if the code is missing
// or unrecognized, so the caller can fall back to the provider's name.
function countryNameFromCode(code, locale) {
  if (!code) {
    return null;
  }
  try {
    const upper = code.toUpperCase();
    const name = new Intl.DisplayNames([locale], { type: "region" }).of(upper);
    // For unknown codes .of() returns the code itself.
    return name && name !== upper ? name : null;
  } catch {
    return null;
  }
}

// Geocoding via the LocationIQ REST endpoint (supports CORS).
// "accept-language" forces the site's language in the response
// (display_name); the country is still derived from country_code, not
// from the string.
async function geocodeLocationIQ(query, apiKey, locale) {
  const url =
    `https://us1.locationiq.com/v1/search?key=${encodeURIComponent(apiKey)}` +
    `&q=${encodeURIComponent(query)}&format=json&addressdetails=1&limit=1` +
    `&accept-language=${encodeURIComponent(locale)}`;

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
    country:
      countryNameFromCode(data[0].address?.country_code, locale) ||
      data[0].address?.country ||
      null,
  };
}

// Geocoding via the Google Maps JS API's Geocoder (avoids CORS issues).
// The library is loaded with the site's language (consistent
// formatted_address); the country is derived from the short_name (ISO
// code), not from the long_name, whose language depends on how the script
// was loaded.
async function geocodeGoogle(query, apiKey, locale) {
  const google = await ensureGoogle(apiKey, locale);
  const geocoder = new google.maps.Geocoder();

  return new Promise((resolve, reject) => {
    geocoder.geocode({ address: query }, (results, status) => {
      if (status === "OK" && results && results[0]) {
        const location = results[0].geometry.location;
        const countryComponent = results[0].address_components?.find((c) =>
          c.types.includes("country")
        );
        resolve({
          lat: location.lat(),
          lng: location.lng(),
          display_name: results[0].formatted_address,
          country:
            countryNameFromCode(countryComponent?.short_name, locale) ||
            countryComponent?.long_name ||
            null,
        });
      } else {
        reject(new Error(status || "not_found"));
      }
    });
  });
}

/**
 * Converts an address (free text) into coordinates using the configured
 * provider.
 * @param {string} query - full address entered by the user
 * @param {Object} siteSettings - Discourse's site-settings service
 * @returns {Promise<{lat:number, lng:number, display_name:string, country:?string}>}
 */
export async function geocodeAddress(query, siteSettings) {
  if (!query || !query.trim()) {
    throw new Error("empty_address");
  }

  const locale = siteLocale(siteSettings);

  if (siteSettings.discourse_maps_provider === "google") {
    return geocodeGoogle(query, siteSettings.discourse_maps_google_api_key, locale);
  }
  return geocodeLocationIQ(
    query,
    siteSettings.discourse_maps_locationiq_api_key,
    locale
  );
}

// ===========================================================================
//  STATIC MAP (topic page)
// ===========================================================================
//  A single image (no call to the Leaflet/Google Maps JS, hence no tiles
//  nor "dynamic" quota consumption) centered on the point, with no marker
//  requested from the provider: the category-colored pin is drawn on top
//  via CSS by the component that uses this URL, it's not part of the image.
// ===========================================================================

/**
 * Builds the static image URL for the configured provider.
 * @param {{lat:number, lng:number}} location
 * @param {Object} siteSettings
 * @param {{width?:number, height?:number, zoom?:number}} [options]
 * @returns {string}
 */
export function staticMapUrl(location, siteSettings, options = {}) {
  const { width = 1200, height = 500, zoom = SINGLE_MARKER_ZOOM } = options;
  const { lat, lng } = location;

  if (siteSettings.discourse_maps_provider === "google") {
    const apiKey = siteSettings.discourse_maps_google_api_key;
    return (
      `https://maps.googleapis.com/maps/api/staticmap?center=${lat},${lng}` +
      `&zoom=${zoom}&size=${width}x${height}&key=${encodeURIComponent(apiKey)}`
    );
  }

  const apiKey = siteSettings.discourse_maps_locationiq_api_key;
  return (
    `https://maps.locationiq.com/v3/staticmap?key=${encodeURIComponent(apiKey)}` +
    `&center=${lat},${lng}&zoom=${zoom}&size=${width}x${height}&format=png`
  );
}

// ===========================================================================
//  MAP RENDERING
// ===========================================================================

// Normalizes a marker: accepts lat/lng even as strings.
function normalizeMarkers(markers) {
  return (markers || [])
    .map((m) => ({
      ...m,
      lat: parseFloat(m.lat),
      lng: parseFloat(m.lng),
    }))
    .filter((m) => !isNaN(m.lat) && !isNaN(m.lng));
}

// --- Leaflet map (LocationIQ / OpenStreetMap provider) -------------------
async function createLeafletMap(element, { markers, interactive, apiKey, clusterColor }) {
  const L = await ensureLeaflet();

  const map = L.map(element, {
    scrollWheelZoom: interactive,
    dragging: interactive,
    zoomControl: interactive,
    doubleClickZoom: interactive,
  });

  // If the LocationIQ key is available we use its tiles, otherwise we
  // fall back to the standard OpenStreetMap tiles.
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
    // Prevents the click on the pin from propagating to the map:
    // otherwise the cluster-closing listener (below) would immediately
    // close the "spiderfy" that just appeared.
    marker.on("click", (e) => L.DomEvent.stopPropagation(e));
    return marker;
  }

  // Cluster: a single numbered pin for each position with multiple
  // markers. On click it "opens", showing the individual pins arranged
  // radially around the point, so the user can pick the one they want
  // even when the original coordinates coincide exactly.
  const openClusters = [];

  function addLeafletCluster(group) {
    const center = L.latLng(group[0].lat, group[0].lng);
    const clusterIcon = L.divIcon({
      className: "discourse-maps-cluster",
      html: clusterSvg(group.length, clusterColor),
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

    // Different screen coordinates after a zoom/pan: we collapse to
    // avoid pins placed at points no longer consistent with the cluster.
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

  // Click on an empty point of the map: closes any open clusters.
  map.on("click", () => openClusters.forEach((c) => c.collapse()));

  if (latLngs.length === 1) {
    map.setView(latLngs[0], SINGLE_MARKER_ZOOM);
  } else if (latLngs.length > 1) {
    map.fitBounds(latLngs, { padding: [30, 30] });
  } else {
    map.setView([DEFAULT_CENTER.lat, DEFAULT_CENTER.lng], DEFAULT_ZOOM);
  }

  // Leaflet sometimes miscalculates the size if the container was
  // hidden: we force a recalculation as soon as possible.
  setTimeout(() => map.invalidateSize(), 200);

  return { instance: map, destroy: () => map.remove() };
}

// Google Maps doesn't directly expose the lat/lng -> screen pixel
// conversion: an "invisible" OverlayView is needed to get the projection
// after the map's first rendering pass.
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

// --- Google Maps map -----------------------------------------------------
async function createGoogleMap(
  element,
  { markers, interactive, apiKey, clusterColor, language }
) {
  const google = await ensureGoogle(apiKey, language);

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

  // Only one InfoWindow at a time: before opening a pin's, we close any
  // popup left open by a previous click.
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

  // Cluster: a single numbered pin for each position with multiple
  // markers. On click it "opens", showing the individual pins arranged
  // radially around the point (clicks on Google's markers don't
  // propagate to the map, so stopPropagation isn't needed like in Leaflet).
  const openClusters = [];

  function addGoogleCluster(group) {
    const center = { lat: group[0].lat, lng: group[0].lng };
    const clusterIcon = {
      url: `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(clusterSvg(group.length, clusterColor))}`,
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

    // Different screen coordinates after a zoom: we collapse to avoid
    // pins placed at points no longer consistent with the cluster.
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

  // Click on an empty point of the map: closes any open clusters.
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
 * Creates a map in the given container using the configured provider.
 * @param {HTMLElement} element - the div that will host the map
 * @param {Object} options - { provider, apiKey, markers, interactive, language }
 * @returns {Promise<{instance:Object, destroy:Function}>}
 */
export async function createMap(element, options) {
  const opts = { interactive: true, markers: [], ...options };

  if (opts.provider === "google") {
    return createGoogleMap(element, opts);
  }
  return createLeafletMap(element, opts);
}
