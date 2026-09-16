// ============================================================================
//  Discourse Maps - Connector: periodo (data inizio/fine) nella pagina del
//  topic.
//
//  Si aggancia all'outlet "topic-category-wrapper__before", renderizzando
//  subito prima di div.topic-category dentro div.title-wrapper. Mostra il
//  periodo salvato sul topic, se presente.
// ============================================================================

import Component from "@glimmer/component";
import formatDateRange from "../../lib/discourse-maps-date-range";

export default class DiscourseMapsTopicDates extends Component {
  get location() {
    return this.args.outletArgs?.topic?.discourse_maps_location;
  }

  get dateRange() {
    return formatDateRange(this.location);
  }

  <template>
    {{#if this.dateRange}}
      <div class="discourse-maps-topic-dates">{{this.dateRange}}</div>
    {{/if}}
  </template>
}
