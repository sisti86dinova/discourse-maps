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
| `discourse_maps_max_topics` | Maximum number of topics returned to the `/map` page, most recent first (default: `500`). When there are more, the page asks to narrow the results with the filters. |
| `discourse_maps_requests_per_minute` | Maximum `/map` data requests per minute for each user, or IP address for anonymous visitors (default: `60`). Staff is not limited. |
| `discourse_maps_cluster_color` | Background color of the "cluster" pin (the numbered circle shown when multiple topics share the same map location). |
| `discourse_maps_provider` | Map/geocoding provider: `locationiq` or `google`. |
| `discourse_maps_locationiq_api_key` | LocationIQ API key (required with the `locationiq` provider). |
| `discourse_maps_google_api_key` | Google Maps API key (required with the `google` provider). |

## Supported providers

The plugin is built to work interchangeably with either provider — geocoding,
interactive map, and static map all switch together based on
`discourse_maps_provider`:

- **LocationIQ** — OpenStreetMap tiles + geocoding (5K free requests/day).
- **Google Maps** — Maps JavaScript API + Google Geocoding + Static Maps API
  (10K free requests/month).

## Deployment checklist

Recommended configuration for a production forum, in this order.

1. **Install the plugin** in the container's `app.yml` and rebuild:

   ```yaml
   hooks:
     after_code:
       - exec:
           cd: $home/plugins
           cmd:
             - git clone https://github.com/sisti86dinova/discourse-maps.git
   ```

   ```sh
   ./launcher rebuild app
   ```

2. **Create the map tag and restrict it to staff.** Create the tag (e.g.
   `mappa`), then in **Admin > Tags > Tag groups** add it to a tag group
   visible to **everyone** but usable only by **staff**. Without this, users
   can add the tag by hand: it can't put their topic on the map (only a saved
   location does), but it hides the topic from the lists selected in
   `discourse_maps_hide_from_lists`.

3. **Point the plugin at the tag.** Set `discourse_maps_map_tag_id` to the
   tag's id, shown by `/tags.json` (the default `295` is only an example).

4. **Configure the provider and lock down its key** (see
   [API keys are public](#api-keys-are-public)):
   - LocationIQ: a `pk.` token with an HTTP referrer restriction for the
     forum's domain, plus usage limits;
   - Google: a browser key with an HTTP referrer restriction, API
     restrictions (Maps JavaScript, Geocoding, Maps Static), quota caps and
     billing alerts.

5. **Choose who can publish.** Add the groups allowed to put topics on the map
   to `discourse_maps_new_topic_groups`. Admins can always publish;
   moderators can't unless they're in one of these groups.

6. **Choose where map topics appear.** Pick the lists in
   `discourse_maps_hide_from_lists`. A common setup is `latest` and
   `suggested`, with `discourse_maps_hide_on_category_pages` and
   `discourse_maps_hide_on_tag_pages` off: map topics then only show on
   `/map` and on their category and tag pages.

7. **Review the limits.** The defaults (`discourse_maps_max_topics` 500,
   `discourse_maps_requests_per_minute` 60) suit most forums; raise the first
   only if users need to see more events at once without filtering.

8. **Pick the default period** shown on `/map` in
   `discourse_maps_default_date_filter` (`today` or `upcoming`).

9. **Upgrading from a version without country codes?** Run the backfill once:

   ```sh
   ./launcher enter app
   rake discourse_maps:backfill_country_codes
   ```

10. **Check it works:** open `/map` as an anonymous visitor (the map loads,
    no "not configured" notice), create a topic from its **New topic** button
    with a location, and check that it appears on `/map` and is hidden from
    the lists you selected.

## Known limitations

- **Location edits and revisions:** core runs the plugin's edit handler before
  validating the rest of the edit. A location change made while editing the
  first post is applied even if the text edit is then refused, and it isn't
  recorded in the post's revision history. Only users allowed to edit the post
  can do this.
- **Wiki topics:** anyone who can edit a wiki first post can move or remove
  its location, as with the rest of the post.
- **Categories missing on the client:** category names and colors on `/map`
  come from the categories Discourse sends to the browser. If a category isn't
  among them (e.g. with lazy-loaded categories), its topics still show, but
  without the category in the filter and in the popup.

## Security

### API keys are public

Geocoding, tiles and static maps are requested directly by the visitor's
browser, so the configured API key is sent to every visitor (anonymous ones
included) and can be read from the page. Treat it as a public key and lock it
down with the provider before going live:

- **Google Maps**: use a dedicated browser key with an **HTTP referrer**
  restriction (your forum's domain only) and **API restrictions** limited to
  Maps JavaScript API, Geocoding API and Maps Static API. Set daily quota caps
  and billing alerts. Static map URLs can't be signed by the plugin (the
  signing secret would have to reach the browser), so keep the Maps Static API
  quota for unsigned requests low.
- **LocationIQ**: use a public `pk.` token with an **HTTP referrer**
  restriction for your forum's domain, never an `sk.` token. Referrer
  restrictions can be spoofed outside a browser, so also set usage limits and
  rotate the token if it gets abused.

### An API key is required

Without a key for the configured provider, the maps show a "not configured"
notice instead of loading. There's no fallback to the public
`tile.openstreetmap.org` servers: their
[tile usage policy](https://operations.osmfoundation.org/policies/tiles/)
doesn't allow heavy use.

### Load on the `/map` page

`/map.json` is public and rebuilds the result and the filter options on every
request. It returns at most `discourse_maps_max_topics` topics and is limited
to `discourse_maps_requests_per_minute` requests per minute per user (or IP
address), so it can't easily be used to load the server.

### Leaflet CVE-2025-69993

The bundled Leaflet 1.9.4 is affected by CVE-2025-69993 (HTML injection
through `bindPopup`, no fixed release). The plugin never passes unescaped
text to popups: topic titles, categories, tags and the geocoder's address
(OpenStreetMap data that anyone can edit) are escaped before being rendered.
Security scanners will still flag the Leaflet version.

### Who can publish to the map

Only admins and the groups in `discourse_maps_new_topic_groups` can put a
topic on the map, also when the location is sent directly through the API.
Once a topic is on the map, its location can be corrected by anyone who can
edit its first post.
