// ============================================================================
//  Discourse Maps - Mappa statica (usata nella pagina del topic).
//
//  Un'unica immagine (nessun SDK Leaflet/Google Maps caricato, quindi niente
//  tile né chiamate "dinamiche"), centrata sul punto. Il provider NON riceve
//  alcun marker: il pin, colorato in base alla categoria del topic, è un SVG
//  disegnato sopra via CSS, sempre al centro dell'immagine (il punto è per
//  definizione il centro della mappa statica, quindi non serve calcolare
//  nessuna proiezione lat/lng -> pixel).
//
//  Argomenti:
//    @location - { lat, lng, display_name, color } (color opzionale, usa il
//                fallback se assente)
// ============================================================================

import Component from "@glimmer/component";
import { service } from "@ember/service";
import {
  DEFAULT_MARKER_COLOR,
  MARKER_HEIGHT,
  MARKER_WIDTH,
  staticMapUrl,
} from "../lib/discourse-maps-provider";

export default class DiscourseMapsStaticMap extends Component {
  @service siteSettings;

  get imageUrl() {
    return staticMapUrl(this.args.location, this.siteSettings);
  }

  get pinColor() {
    return this.args.location?.color || DEFAULT_MARKER_COLOR;
  }

  <template>
    <div class="discourse-maps-static">
      <img
        src={{this.imageUrl}}
        alt={{@location.display_name}}
        class="discourse-maps-static__image"
      />
      <svg
        class="discourse-maps-static__pin"
        xmlns="http://www.w3.org/2000/svg"
        width={{MARKER_WIDTH}}
        height={{MARKER_HEIGHT}}
        viewBox="0 0 25 41"
      >
        <path
          fill={{this.pinColor}}
          stroke="#ffffff"
          stroke-width="1.5"
          d="M12.5 0C5.6 0 0 5.6 0 12.5 0 20 12.5 41 12.5 41S25 20 25 12.5C25 5.6 19.4 0 12.5 0Z"
        />
        <circle cx="12.5" cy="12.5" r="4.5" fill="#ffffff" />
      </svg>
    </div>
  </template>
}
