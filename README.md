# Discourse Maps

A Discourse plugin that lets users attach a geographic location to a topic
and shows it on a map — a single pin on the topic page, and an interactive
map with all geolocated topics on a dedicated `/map` page.

## Dependencies

- [Discourse](https://github.com/discourse/discourse) 2.7.0 or higher
- [Leaflet](https://github.com/leaflet/Leaflet) 1.9.3 or higher (for the interactive map)
- [LocationIQ](https://my.locationiq.com/dashboard#accesstoken)
  or [Google Maps API key](https://console.cloud.google.com/apis/credentials) (for geocoding and map tiles)

## Features

### Adding a location (composer)

- One free-text address field in the location modal (toolbar button in the
  composer). The user types a full address; the configured provider
  (LocationIQ or Google) geocodes it and returns coordinates, a formatted
  address, and the country — all parsed automatically, nothing typed by hand
  besides the address itself. This keeps the country value consistent (no
  "Italy" vs "italy" duplicates from free typing).
- On first post creation, the resolved location is saved on the topic and the
  configured "map" tag is automatically added, which is what makes the topic
  show up on `/map`.

### Topic page

- Shows a **static map image** (no Leaflet/Google Maps JavaScript SDK
  loaded) centered on the saved location — this avoids the API/quota cost of
  loading a full interactive map for a single, non-interactive pin.
- The pin itself is a plain SVG overlaid via CSS on top of the static image
  (always exactly centered, so no lat/lng-to-pixel projection is needed),
  colored with the topic's category color — same color used everywhere else
  in the plugin.

### `/map` page

- Interactive map (Leaflet + OpenStreetMap/LocationIQ tiles, or Google Maps
  JavaScript API) with one colored pin per topic (color = topic category).
- **Clustering**: multiple topics sharing the exact same coordinates collapse
  into a single numbered "cluster" pin (background color configurable, see
  Settings). Clicking a cluster "spiderfies" it — the individual pins fan out
  around the point so each one can be picked and clicked, then collapses
  again on an outside click, on zoom/pan, or when another cluster/marker is
  opened.
- **Filters**: category, tag, and country — each populated only with values
  actually present among the currently geolocated topics, cross-filtered
  against each other (choosing a category narrows the tag/country options
  and vice versa, without ever hiding the option that's currently selected).
  Filters are query params (shareable/bookmarkable URLs) but are reset when
  leaving the `/map` route, so returning to the page via a plain link (e.g.
  from the sidebar) always starts from a clean state.
- **Reset filters** button, enabled whenever any filter is active.
- **New topic** button, right-aligned in the filter bar, visible only to
  admins and to the groups configured in
  `discourse_maps_new_topic_groups` (see Settings).
- Topic list below the map: paginated (infinite scroll), one card per
  geolocated topic with thumbnail (or a placeholder icon when the topic has
  no featured image), category badge, tags, and stats (views/likes/comments/
  last activity). Each list item also carries `category-<slug>` and
  `tag-<slug>` CSS classes for further theme/CSS customization.
- The category filter's dropdown rows show the category's own icon (when the
  category uses the "icon" badge style) tinted with the category's color.

### Hiding map topics from other lists

Topics with the "map" tag can be kept out of Discourse's regular topic lists,
so they mostly live on `/map`. It's configured with three settings (all off by
default, see Settings):

- `discourse_maps_hide_from_lists` picks the lists to filter: `latest` (which
  also covers the homepage, the "categories + latest" layout and the RSS
  feed), `new`, `unread`, `top`, `hot`, `suggested` (the suggested topics at
  the bottom of a topic).
- By default category pages (`/c/...`) and tag pages (`/tag/...`) keep
  showing map topics. `discourse_maps_hide_on_category_pages` and
  `discourse_maps_hide_on_tag_pages` apply the filter there too.
- `/map` always shows them.

For example, to show map topics only on `/map` and on category pages, select
just `latest` and leave the other two settings off.

Not affected: search results, the featured topics of the categories-only
homepage layout, and personal lists (user activity, bookmarks, messages).

## Settings

Configurable from **Admin > Settings > Plugins**:

| Setting | Description |
| --- | --- |
| `discourse_maps_enabled` | Enables/disables the plugin. |
| `discourse_maps_map_tag_id` | ID of the tag automatically assigned to topics that use the map feature (default: `295`). |
| `discourse_maps_new_topic_groups` | Groups (besides admins, who always see it) allowed to see the "New topic" button on `/map`. Empty = admins only. |
| `discourse_maps_hide_from_lists` | Topic lists that hide topics with the map tag: `latest` (also the homepage), `new`, `unread`, `top`, `hot`, `suggested`. Empty = none (default). |
| `discourse_maps_hide_on_category_pages` | Also hide them from the lists above on category pages (default: off). |
| `discourse_maps_hide_on_tag_pages` | Also hide them from the lists above on tag pages (default: off). |
| `discourse_maps_default_date_filter` | Period shown on `/map` before any filter is picked: `today` (only today's events) or `upcoming` (today's and future ones). |
| `discourse_maps_cluster_color` | Background color of the "cluster" pin (the numbered circle shown when multiple topics share the same map location). |
| `discourse_maps_provider` | Map/geocoding provider: `locationiq` or `google`. |
| `discourse_maps_locationiq_api_key` | LocationIQ API key. |
| `discourse_maps_google_api_key` | Google Maps API key. |

## Supported providers

The plugin is built to work interchangeably with either provider — geocoding,
interactive map, and static map all switch together based on
`discourse_maps_provider`:

- **LocationIQ** — OpenStreetMap tiles + geocoding (5K free requests/day).
- **Google Maps** — Maps JavaScript API + Google Geocoding + Static Maps API
  (10K free requests/month).
