// ============================================================================
//  Discourse Maps - Connector: periodo (data inizio/fine) nella pagina del
//  topic.
//
//  Si aggancia all'outlet "topic-category-wrapper__before", renderizzando
//  subito prima di div.topic-category dentro div.title-wrapper. Mostra il
//  periodo salvato sul topic, se presente.
// ============================================================================

import Component from "@glimmer/component";
import { formatDateParts } from "../../lib/discourse-maps-date-range";

export default class DiscourseMapsTopicDates extends Component {
  get location() {
    return this.args.outletArgs?.topic?.discourse_maps_location;
  }

  get dateParts() {
    return formatDateParts(this.location);
  }

  <template>
    {{#if this.dateParts}}
      <div class="discourse-maps-topic-dates">
        <span class="discourse-maps-topic-dates__date">{{this.dateParts.start}}</span>
        {{#unless this.dateParts.sameDay}}
          <span class="discourse-maps-topic-dates__separator" aria-hidden="true">–</span>
          <span class="discourse-maps-topic-dates__date">{{this.dateParts.end}}</span>
        {{/unless}}
      </div>
    {{/if}}
  </template>
}
