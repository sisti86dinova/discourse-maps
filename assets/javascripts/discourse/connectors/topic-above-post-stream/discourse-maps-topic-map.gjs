// ============================================================================
//  Discourse Maps - Connector: map on the topic page.
//
//  Hooks into the "topic-above-post-stream" outlet (right above the
//  posts) and, if the topic has geographic data, shows the corresponding
//  map with the pin.
// ============================================================================

import Component from "@glimmer/component";
import { service } from "@ember/service";
import DiscourseMapsStaticMap from "../../components/discourse-maps-static-map";
import { DEFAULT_MARKER_COLOR } from "../../lib/discourse-maps-provider";

export default class DiscourseMapsTopicMap extends Component {
  @service site;

  get topic() {
    return this.args.outletArgs?.model;
  }

  // Location saved on the topic (serialized by the server, if present).
  get location() {
    return this.topic?.discourse_maps_location;
  }

  get category() {
    const categoryId = this.topic?.category_id;
    if (!categoryId) {
      return null;
    }
    return this.site.categories?.find((c) => c.id === categoryId) || null;
  }

  // Same category-colored pin as the /map page: without this, the
  // marker here always used the fallback color, because @location
  // doesn't carry any information about the topic's category.
  get markerLocation() {
    return {
      ...this.location,
      color: this.category?.color ? `#${this.category.color}` : DEFAULT_MARKER_COLOR,
    };
  }

  <template>
    {{#if this.location}}
      <div class="discourse-maps-topic">
        <DiscourseMapsStaticMap @location={{this.markerLocation}} />
      </div>
    {{/if}}
  </template>
}
