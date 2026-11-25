// URL of the plugin's map page, also used for its JSON endpoint
// (MAP_PATH + ".json"). Not "/map": the widely used Locations plugin
// registers "map" as a core topic list filter, whose server route is drawn
// before any plugin route and would take over both the page and the data.
// Must match DiscourseMaps::MAP_PATH in plugin.rb.
export const MAP_PATH = "/mappa";
