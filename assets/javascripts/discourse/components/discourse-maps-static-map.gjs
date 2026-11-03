// ============================================================================
//  Discourse Maps - Static map (used on the topic page).
//
//  A single image (no Leaflet/Google Maps SDK loaded, hence no tiles nor
//  "dynamic" calls), centered on the point. The provider receives NO
//  marker: the pin, colored based on the topic's category, is an SVG
//  drawn on top via CSS, always at the center of the image (the point is
//  by definition the center of the static map, so no lat/lng -> pixel
//  projection needs to be computed).
//
//  Arguments:
//    @location - { lat, lng, display_name, color } (color optional, uses
//                the fallback if absent)
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
