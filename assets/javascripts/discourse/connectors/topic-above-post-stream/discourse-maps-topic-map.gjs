// ============================================================================
//  Discourse Maps - Connector: mappa nella pagina del topic.
//
//  Si aggancia all'outlet "topic-above-post-stream" (subito sopra i post) e,
//  se il topic contiene dati geografici, mostra la relativa mappa con il pin.
// ============================================================================

import Component from "@glimmer/component";
import DiscourseMapsMap from "../../components/discourse-maps-map";

export default class DiscourseMapsTopicMap extends Component {
  // Posizione salvata sul topic (serializzata dal server, se presente).
  get location() {
    return this.args.outletArgs?.model?.discourse_maps_location;
  }

  <template>
    {{#if this.location}}
      <div class="discourse-maps-topic">
        <DiscourseMapsMap @location={{this.location}} @interactive={{true}} />
      </div>
    {{/if}}
  </template>
}

