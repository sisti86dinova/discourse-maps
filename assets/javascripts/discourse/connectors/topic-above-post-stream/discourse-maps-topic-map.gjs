// ============================================================================
//  Discourse Maps - Connector: mappa nella pagina del topic.
//
//  Si aggancia all'outlet "topic-above-post-stream" (subito sopra i post) e,
//  se il topic contiene dati geografici, mostra la relativa mappa con il pin.
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

  // Posizione salvata sul topic (serializzata dal server, se presente).
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

  // Stesso pin colorato per categoria della pagina /map: senza questo il
  // marker qui usava sempre il colore di fallback, perché @location non
  // porta con sé alcuna informazione sulla categoria del topic.
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
