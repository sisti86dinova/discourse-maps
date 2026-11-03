// ============================================================================
//  Discourse Maps - Connector: period (start/end date) on the topic page.
//
//  Hooks into the "topic-category-wrapper__before" outlet, rendering
//  right before div.topic-category inside div.title-wrapper. Shows the
//  period saved on the topic, if present.
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
