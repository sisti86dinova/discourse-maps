// ============================================================================
//  Discourse Maps - Template della rotta /map.
//
//  Passa dati e stato dei filtri (dal controller) al componente MapPage.
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
