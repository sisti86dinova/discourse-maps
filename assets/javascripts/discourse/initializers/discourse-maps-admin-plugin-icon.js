import { withPluginApi } from "discourse/lib/plugin-api";

const PLUGIN_ID = "discourse-maps";

// Replaces the default gear next to the plugin's entry in the admin
// sidebar. The icon is a custom symbol from svg-icons/, which core adds to
// the sprite automatically.
export default {
  name: "discourse-maps-admin-plugin-icon",

  initialize(container) {
    const currentUser = container.lookup("service:current-user");
    if (!currentUser?.admin) {
      return;
    }

    withPluginApi((api) => {
      api.setAdminPluginIcon(PLUGIN_ID, "discourse-maps-globe-italy");
    });
  },
};
