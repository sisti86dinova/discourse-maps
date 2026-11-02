// ============================================================================
//  Discourse Maps - /map route template.
//
//  Passes the data and filter state (from the controller) to the MapPage
//  component.
// ============================================================================


import MapPage from "../components/map-page.gjs";

export default <template>
    <MapPage
      @categoryId={{@controller.category_id}}
      @countryCode={{@controller.countryCode}}
      @day={{@controller.day}}
      @filters={{@controller.model.filters}}
      @month={{@controller.month}}
      @onChangeCategory={{@controller.updateCategory}}
      @onChangeCountry={{@controller.updateCountry}}
      @onChangeDay={{@controller.updateDay}}
      @onChangeMonth={{@controller.updateMonth}}
      @onChangeTags={{@controller.updateTags}}
      @onChangeYear={{@controller.updateYear}}
      @onResetDate={{@controller.resetDateFilter}}
      @selectedTags={{@controller.selectedTags}}
      @topics={{@controller.model.topics}}
      @upcoming={{@controller.upcoming}}
      @year={{@controller.year}}
    />
  </template>;
