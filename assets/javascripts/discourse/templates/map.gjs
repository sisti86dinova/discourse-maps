// ============================================================================
//  Discourse Maps - /map route template.
//
//  Passes the data and filter state (from the controller) to the MapPage
//  component.
// ============================================================================

import RouteTemplate from "ember-route-template";
import MapPage from "../components/map-page";

export default RouteTemplate(
  <template>
    <MapPage
      @topics={{@controller.model.topics}}
      @filters={{@controller.model.filters}}
      @categoryId={{@controller.category_id}}
      @selectedTags={{@controller.selectedTags}}
      @countryName={{@controller.countryName}}
      @year={{@controller.year}}
      @month={{@controller.month}}
      @day={{@controller.day}}
      @onChangeCategory={{@controller.updateCategory}}
      @onChangeTags={{@controller.updateTags}}
      @onChangeCountry={{@controller.updateCountry}}
      @onChangeYear={{@controller.updateYear}}
      @onChangeMonth={{@controller.updateMonth}}
      @onChangeDay={{@controller.updateDay}}
      @onResetDate={{@controller.resetDateFilter}}
    />
  </template>
);
