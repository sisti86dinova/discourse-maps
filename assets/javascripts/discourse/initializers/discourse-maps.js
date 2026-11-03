// ============================================================================
//  Discourse Maps - Main client-side initializer.
//
//  Responsibilities at this step:
//    - add a button to the composer toolbar that opens the modal for
//      entering the geographic location;
//    - register serialization of the "discourse_maps_location" data so
//      that it's sent to the server on topic creation and is available
//      on the model of the just-created topic.
// ============================================================================

import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";
import DiscourseMapsLocationModal from "../components/discourse-maps-location-modal";

export default {
  name: "discourse-maps",

  initialize() {
    withPluginApi("1.8.0", (api) => {
      const siteSettings = api.container.lookup("service:site-settings");

      // If the plugin is disabled we don't add anything.
      if (!siteSettings.discourse_maps_enabled) {
        return;
      }

      // --- Hides the "map" tag in the tag selection dropdowns --------------
      // Extra visual protection, on top of the read-only tag group
      // server-side (which prevents assigning it from the composer):
      // hides the entry even if it were to show up in a tag selection
      // widget not covered by that permission.
      const mapTagId = siteSettings.discourse_maps_map_tag_id;
      if (mapTagId) {
        const style = document.createElement("style");
        style.textContent = `.tags-input li[data-value="${mapTagId}"] { display: none !important; }`;
        document.head.appendChild(style);
      }

      // --- Link to the /map page in the sidebar -----------------------------
      api.addCommunitySectionLink({
        name: "discourse-maps",
        route: "map",
        title: i18n("discourse_maps.page_title"),
        text: i18n("discourse_maps.page_title"),
        icon: "globe",
      });

      // --- Serialization of geographic data -----------------------------
      // Sends "discourse_maps_location" to the server on topic creation...
      api.serializeOnCreate("discourse_maps_location");
      // ...and copies it onto the just-created topic's model (for rendering).
      api.serializeToTopic(
        "discourse_maps_location",
        "topic.discourse_maps_location"
      );
      // ...and also when editing the first post, so a correction or a
      // removal (modal's "Remove location" sets it to null) reaches the
      // server (see add_permitted_post_update_param in plugin.rb).
      api.serializeOnUpdate("discourse_maps_location");

      // Sends "discourse_maps_from_map" when the topic was opened from the
      // "New topic" button on the /map page (see map-page.gjs): the
      // server needs this to still assign the "map" tag, even if the
      // user didn't fill in the location via the composer modal.
      api.serializeOnCreate("discourse_maps_from_map");

      // --- Button in the composer toolbar -----------------------------
      // Shown only in the two editors where a location makes sense:
      // creating a new topic from the /map page's "New topic" button
      // (flagged by discourse_maps_from_map, set in map-page.gjs), and
      // editing the first post of a topic that already has one (lets a
      // wrong address be corrected, or the location removed entirely,
      // without deleting and recreating the post).
      api.onToolbarCreate((toolbar) => {
        toolbar.addButton({
          id: "discourse-maps-location",
          group: "extras",
          icon: "location-dot",
          title: "discourse_maps.composer.button_title",
          condition: () => {
            const model = api.container.lookup("service:composer")?.model;
            return Boolean(
              model?.discourse_maps_from_map ||
                (model?.editingFirstPost && model?.topic?.discourse_maps_location)
            );
          },
          action: () => {
            const modal = api.container.lookup("service:modal");
            modal.show(DiscourseMapsLocationModal);
          },
        });
      });
    });
  },
};

