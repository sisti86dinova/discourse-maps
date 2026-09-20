# frozen_string_literal: true

# ============================================================================
#  Discourse Maps
#  Plugin that allows inserting geographic information in topics and
#  displaying it on an interactive map (LocationIQ or Google Maps).
#  NOTE: this file is the plugin's entry point. In this first step it only
#  contains the basic structure (metadata, enabling, settings).
#  The features (composer, /map page, filters) will be added in later
#  steps.
# ============================================================================

# name: discourse-maps
# about: Associate geographic information in topics and display on an interactive map.
# version: 1.0.0
# authors: Stefano Sisti
# url: https://github.com/sisti86dinova/discourse-maps
# required_version: 2.7.0

# Enables/disables the whole plugin via the admin panel setting.
enabled_site_setting :discourse_maps_enabled

# Registers the common stylesheet (maps, /map page layout, etc.).
register_asset "stylesheets/common/discourse-maps.scss"

# Ensures the "Map" sidebar link icon is always available, regardless of
# the default icon set configured on the site.
register_svg_icon "globe"

# Icons for the button that opens/closes filters on mobile (/map page).
register_svg_icon "angle-up"
register_svg_icon "angle-down"

# Allows the composer to send the "discourse_maps_location" parameter when
# creating a topic. We declare it as :hash because it's an object with
# multiple fields (address + lat/lng coordinates).

# ----------------------------------------------------------------------------
#  Server-side initialization block.
# ----------------------------------------------------------------------------
after_initialize do

  add_permitted_post_create_param("discourse_maps_location", :hash)

  # Makes these parameters survive in the ReviewableQueuedPost payload, so
  # they can be retrieved in on(:approved_post) when a post from a
  # not-yet-approved user is put in the moderation queue and the actual
  # post is only created after staff approval (see apply_map_metadata
  # below).
  NewPostManager.add_plugin_payload_attribute("discourse_maps_location")
  NewPostManager.add_plugin_payload_attribute("discourse_maps_from_map")

  # Plugin module namespace.
  module ::DiscourseMaps
    PLUGIN_NAME = "discourse-maps"

    # Name of the topic custom field where we store the geographic data.
    # Contains: { address, lat, lng, display_name, country, start_date,
    # end_date }. "address" is the address typed by the user, the other
    # geocoding fields are the provider's result (the country arrives
    # already "interpreted", not hand-typed, to avoid different spellings
    # for the same country). start_date/end_date ("YYYY-MM-DD") are the
    # topic's reference period, also typed by the user in the modal.
    LOCATION_FIELD = "discourse_maps_location"

    # Returns the "map" tag configured in the admin panel (setting
    # `discourse_maps_map_tag_id`), or nil if it doesn't exist.
    def self.map_tag
      Tag.find_by(id: SiteSetting.discourse_maps_map_tag_id)
    end

    # Applies the geographic data and the "map" tag to the topic, based on
    # the "discourse_maps_location" / "discourse_maps_from_map"
    # parameters. Used both on direct post creation (on :post_created) and
    # on approval of a post that was in the moderation queue (on
    # :approved_post), because in that second case the post is recreated
    # by ReviewableQueuedPost and :post_created is not emitted.
    def self.apply_map_metadata(topic, location, from_map)
      return if location.blank? && from_map.blank?

      if location.present?
        topic.custom_fields[LOCATION_FIELD] = location
        topic.save_custom_fields(true)
      end

      tag = map_tag
      if tag && topic.tags.exclude?(tag)
        topic.tags << tag
        topic.save!
      end
    end

    # Base scope: topics with the "map" tag, a saved location, and visible
    # to the user (guardian). Doesn't apply the category/tag filters: it's
    # the base for both the topic list and the filter options calculation.
    def self.base_map_scope(guardian)
      tag = map_tag
      return nil unless tag

      topic_ids = TopicCustomField.where(name: LOCATION_FIELD).pluck(:topic_id)
      return nil if topic_ids.empty?

      scope =
        Topic
          .listable_topics
          .secured(guardian)
          .where(id: topic_ids)
          .joins(:topic_tags)
          .where(topic_tags: { tag_id: tag.id }) # "map" tag constraint

      { scope: scope, tag: tag }
    end

    # Filters a scope by tag: the topic must have ALL the given tags.
    def self.filter_by_tags(scope, tag_names)
      Tag
        .where(name: tag_names)
        .pluck(:id)
        .each { |tid| scope = scope.where(id: TopicTag.where(tag_id: tid).select(:topic_id)) }
      scope
    end

    # Filters a scope by country. The country is only stored inside the
    # JSON custom field (LOCATION_FIELD), it's not a column: the
    # comparison must be done by reading and parsing the JSON, not with a
    # SQL where.
    def self.filter_by_countries(scope, country_names)
      scope.where(id: topic_ids_matching_countries(scope, country_names))
    end

    def self.topic_ids_matching_countries(scope, country_names)
      TopicCustomField
        .where(topic_id: scope.distinct.pluck("topics.id"), name: LOCATION_FIELD)
        .pluck(:topic_id, :value)
        .select { |_, value| country_names.include?(parse_country(value)) }
        .map(&:first)
    end

    # (Sorted, de-duplicated) list of the countries present among the
    # topics of the given scope.
    def self.countries_for_scope(scope)
      names =
        TopicCustomField
          .where(topic_id: scope.distinct.pluck("topics.id"), name: LOCATION_FIELD)
          .pluck(:value)
          .map { |value| parse_country(value) }
          .reject(&:blank?)
          .uniq
          .sort

      names.map { |name| { id: name, name: name } }
    end

    # The custom field is stored as JSON: safely extracts the country (nil
    # if the value is missing or not valid JSON).
    def self.parse_country(raw_value)
      return nil if raw_value.blank?

      JSON.parse(raw_value)["country"]
    rescue JSON::ParserError
      nil
    end

    # Extracts the period (start/end date) from the JSON custom field.
    # Returns nil if the value is missing/invalid or if one of the two
    # dates is missing: both are required at creation time, but topics
    # saved before this feature was introduced don't have them, and will
    # simply never show up in the date filters (they remain visible
    # without a filter).
    def self.parse_date_range(raw_value)
      return nil if raw_value.blank?

      data = JSON.parse(raw_value)
      start_date = data["start_date"]
      end_date = data["end_date"]
      return nil if start_date.blank? || end_date.blank?

      [Date.parse(start_date), Date.parse(end_date)]
    rescue JSON::ParserError, ArgumentError, TypeError
      nil
    end

    # Validates the period (start/end) of a location as it arrives from
    # the composer (hash with symbol or string keys, not yet serialized
    # to JSON): both dates must be present and the end must not precede
    # the start. Used for the server-side check on post creation (see
    # NewPostManager.add_handler below), to guarantee the invariant even
    # if the client didn't validate correctly (bug, direct API call,
    # etc.).
    def self.valid_location_dates?(location)
      start_date = location[:start_date] || location["start_date"]
      end_date = location[:end_date] || location["end_date"]
      return false if start_date.blank? || end_date.blank?

      Date.parse(start_date.to_s) <= Date.parse(end_date.to_s)
    rescue ArgumentError, TypeError
      false
    end

    # Converts the (possibly partial) year/month/day filter parameters
    # into the corresponding date range, used for the "overlap" comparison
    # with each topic's period. nil if the year isn't given (no date
    # filter) or if the combination isn't a valid date.
    def self.date_filter_range(year, month, day)
      return nil if year.blank?

      year = year.to_i

      if month.present?
        month = month.to_i

        if day.present?
          date = Date.new(year, month, day.to_i)
          [date, date]
        else
          start = Date.new(year, month, 1)
          [start, start.end_of_month]
        end
      else
        [Date.new(year, 1, 1), Date.new(year, 12, 31)]
      end
    rescue ArgumentError
      nil
    end

    # Periods ([start, end] pairs) of the topics of the given scope, with
    # a valid period. Common base for calculating the year/month/day
    # options.
    def self.date_ranges_for_scope(scope)
      TopicCustomField
        .where(topic_id: scope.distinct.pluck("topics.id"), name: LOCATION_FIELD)
        .pluck(:value)
        .map { |value| parse_date_range(value) }
        .compact
    end

    # Filters a scope by period: the topic must have a period that
    # overlaps the given [filter_start, filter_end] interval.
    def self.filter_by_date_range(scope, filter_start, filter_end)
      scope.where(id: topic_ids_matching_date_range(scope, filter_start, filter_end))
    end

    def self.topic_ids_matching_date_range(scope, filter_start, filter_end)
      TopicCustomField
        .where(topic_id: scope.distinct.pluck("topics.id"), name: LOCATION_FIELD)
        .pluck(:topic_id, :value)
        .select { |_, value|
          range = parse_date_range(value)
          range && range[0] <= filter_end && range[1] >= filter_start
        }
        .map(&:first)
    end

    # Years available in the given scope: a topic whose period spans
    # multiple years shows up in each of them (consistent with the
    # "overlap" logic).
    def self.years_for_scope(scope)
      years =
        date_ranges_for_scope(scope)
          .flat_map { |start_date, end_date| (start_date.year..end_date.year).to_a }
          .uniq
          .sort

      years.map { |year| { id: year, name: year.to_s } }
    end

    # Months available in the given scope for the selected year: each
    # period is "clipped" to the year's boundaries before extracting its
    # months, so a topic spanning multiple years only contributes the
    # months that actually fall within that year.
    def self.months_for_scope(scope, year)
      year_start = Date.new(year, 1, 1)
      year_end = Date.new(year, 12, 31)

      months =
        date_ranges_for_scope(scope)
          .flat_map { |start_date, end_date|
            clipped_start = [start_date, year_start].max
            clipped_end = [end_date, year_end].min
            next [] if clipped_start > clipped_end

            (clipped_start.month..clipped_end.month).to_a
          }
          .uniq
          .sort

      months.map { |month| { id: month, name: month.to_s } }
    end

    # Days available in the given scope for the selected year/month: same
    # clipping logic as months, applied to the month's boundaries.
    def self.days_for_scope(scope, year, month)
      month_start = Date.new(year, month, 1)
      month_end = month_start.end_of_month

      days =
        date_ranges_for_scope(scope)
          .flat_map { |start_date, end_date|
            clipped_start = [start_date, month_start].max
            clipped_end = [end_date, month_end].min
            next [] if clipped_start > clipped_end

            (clipped_start.day..clipped_end.day).to_a
          }
          .uniq
          .sort

      days.map { |day| { id: day, name: day.to_s } }
    end

    # Collects the topics to show on the /map page, ordered by descending
    # creation date. Respects the user's permissions (guardian) and
    # returns only the data needed by the map and the list.
    #
    # Optional filters:
    #   - category_id   : shows only topics in the given category;
    #   - tag_names     : shows only topics that have ALL the given tags
    #                     (the "map" tag constraint is always applied);
    #   - country_names : shows only topics whose address is in one of the
    #                     given countries;
    #   - year/month/day: shows only topics whose period (start/end)
    #                     overlaps the given period (year, year+month or
    #                     exact date depending on which are present).
    def self.map_topics(guardian, category_id: nil, tag_names: [], country_names: [], year: nil, month: nil, day: nil)
      base = base_map_scope(guardian)
      return [] unless base

      scope = base[:scope]

      # Category filter.
      scope = scope.where(category_id: category_id) if category_id.present?

      # Tag filter: the topic must have all the selected tags.
      scope = filter_by_tags(scope, tag_names) if tag_names.present?

      # Country filter.
      scope = filter_by_countries(scope, country_names) if country_names.present?

      # Period filter.
      date_range = date_filter_range(year, month, day)
      scope = filter_by_date_range(scope, *date_range) if date_range

      topics = scope.includes(:tags).distinct.order(created_at: :desc).to_a

      # Preload custom fields to avoid N+1 queries.
      Topic.preload_custom_fields(topics, [LOCATION_FIELD])

      # Topics already read (at least one post) by the current user, for
      # the "visited" class in the list (like in the native topic list).
      visited_topic_ids =
        if guardian.user
          TopicUser
            .where(user_id: guardian.user.id, topic_id: topics.map(&:id))
            .where("last_read_post_number > 0")
            .pluck(:topic_id)
            .to_set
        else
          Set.new
        end

      topics.map do |topic|
        {
          id: topic.id,
          title: topic.title,
          fancy_title: topic.fancy_title,
          url: "/t/#{topic.slug}/#{topic.id}",
          category_id: topic.category_id,
          tags: topic.tags.map(&:name),
          location: topic.custom_fields[LOCATION_FIELD],
          image_url: topic.image_url,
          views: topic.views,
          like_count: topic.like_count,
          posts_count: topic.posts_count,
          last_posted_at: topic.last_posted_at,
          created_at: topic.created_at,
          visited: visited_topic_ids.include?(topic.id),
        }
      end
    end

    # Available options for the category/tag/country/period filters:
    # cross-referenced with each other (AND), so that choosing one filter
    # updates the other filters' options, showing only the ones that
    # wouldn't lead to zero results with the filters already set.
    # Year/month/day additionally have a hierarchy among them (month
    # depends on the chosen year, day on year+month): the options for a
    # more specific level are only calculated if the higher level is
    # already selected.
    def self.map_filter_options(guardian, category_id: nil, tag_names: [], country_names: [], year: nil, month: nil, day: nil)
      base = base_map_scope(guardian)
      return { category_ids: [], tags: [], countries: [], years: [], months: [], days: [] } unless base

      scope = base[:scope]
      tag = base[:tag]
      date_range = date_filter_range(year, month, day)

      # Available categories: respect the tag, country and period filters already set.
      scope_for_categories = scope
      scope_for_categories = filter_by_tags(scope_for_categories, tag_names) if tag_names.present?
      scope_for_categories = filter_by_countries(scope_for_categories, country_names) if country_names.present?
      scope_for_categories = filter_by_date_range(scope_for_categories, *date_range) if date_range
      category_ids = scope_for_categories.distinct.pluck(:category_id).compact

      # Available tags: respect the category, country and period filters already set.
      scope_for_tags = scope
      scope_for_tags = scope_for_tags.where(category_id: category_id) if category_id.present?
      scope_for_tags = filter_by_countries(scope_for_tags, country_names) if country_names.present?
      scope_for_tags = filter_by_date_range(scope_for_tags, *date_range) if date_range

      tag_ids =
        TopicTag
          .where(topic_id: scope_for_tags.distinct.pluck("topics.id"))
          .where.not(tag_id: tag.id)
          .distinct
          .pluck(:tag_id)

      tags = Tag.where(id: tag_ids).order(:name).pluck(:id, :name).map { |id, name| { id: id, name: name } }

      # Available countries: respect the category, tag and period filters already set.
      scope_for_countries = scope
      scope_for_countries = scope_for_countries.where(category_id: category_id) if category_id.present?
      scope_for_countries = filter_by_tags(scope_for_countries, tag_names) if tag_names.present?
      scope_for_countries = filter_by_date_range(scope_for_countries, *date_range) if date_range
      countries = countries_for_scope(scope_for_countries)

      # Available years/months/days: respect the category/tag/country
      # filters already set (not the period itself, which is hierarchical
      # among the three).
      scope_for_dates = scope
      scope_for_dates = scope_for_dates.where(category_id: category_id) if category_id.present?
      scope_for_dates = filter_by_tags(scope_for_dates, tag_names) if tag_names.present?
      scope_for_dates = filter_by_countries(scope_for_dates, country_names) if country_names.present?

      years = years_for_scope(scope_for_dates)
      months = year.present? ? months_for_scope(scope_for_dates, year.to_i) : []
      days = (year.present? && month.present?) ? days_for_scope(scope_for_dates, year.to_i, month.to_i) : []

      { category_ids: category_ids, tags: tags, countries: countries, years: years, months: months, days: days }
    end
  end

  # Registers the custom field type as JSON: reading returns a Hash,
  # writing automatically serializes it to JSON.
  Topic.register_custom_field_type(::DiscourseMaps::LOCATION_FIELD, :json)

  # --------------------------------------------------------------------------
  #  Server-side check, on post creation: a geolocated topic must have
  #  both a start date and an end date (see
  #  DiscourseMaps.valid_location_dates?). The composer modal already
  #  validates this constraint client-side, but without a check here a
  #  different client (bug, direct API call) could still create a topic
  #  with a location but no period, which would never show up in the
  #  /map date filters. This only applies to the creation of a new topic
  #  (manager.args[:topic_id] absent): the location/period concern only
  #  the first post, just like the location itself.
  # --------------------------------------------------------------------------
  NewPostManager.add_handler do |manager|
    location = manager.args[:discourse_maps_location] || manager.args["discourse_maps_location"]

    if manager.args[:topic_id].blank? && location.present? && !::DiscourseMaps.valid_location_dates?(location)
      next manager.create_error_result(I18n.t("discourse_maps.errors.missing_dates"))
    end

    nil
  end

  # --------------------------------------------------------------------------
  #  On creation of a topic's first post:
  #   1. we save the geographic data (if present) in the topic's custom field;
  #   2. we automatically assign the "map" tag configured in admin.
  # --------------------------------------------------------------------------
  on(:post_created) do |post, opts, _user|
    # We only care about the first post (the actual topic).
    next unless post.is_first_post?

    # The parameter can arrive with a symbol or string key: we handle both.
    location = opts[:discourse_maps_location] || opts["discourse_maps_location"]
    from_map = opts[:discourse_maps_from_map] || opts["discourse_maps_from_map"]

    # Automatic assignment of the "map" tag (id read from the setting) and
    # saving of the location. The tag is assigned even without a location
    # when the topic was created via the "New topic" button on the /map
    # page: the tag group is staff-only, so a normal user can't assign it
    # themselves through the composer (the selector hides it and the
    # server would filter it out anyway), and without this bypass it
    # would never show up in the /map list.
    ::DiscourseMaps.apply_map_metadata(post.topic, location, from_map)
  end

  # --------------------------------------------------------------------------
  #  Case of not-yet-approved users (or otherwise subject to new topic
  #  moderation): the actual post is NOT created immediately, but is
  #  queued (ReviewableQueuedPost) and recreated only when staff approves
  #  it. At that point :post_created is not emitted (skip_events is
  #  passed) and the custom opts don't arrive anyway, because
  #  ReviewableQueuedPost rebuilds the opts from its own "payload", which
  #  by default only contains raw/title/tags/category. This is why we
  #  register our parameters as "plugin payload attribute" (they survive
  #  in the payload) and apply them here, once approval has happened.
  # --------------------------------------------------------------------------
  on(:approved_post) do |reviewable, post|
    next unless post&.is_first_post?

    payload = reviewable.payload || {}
    location = payload["discourse_maps_location"]
    from_map = payload["discourse_maps_from_map"]

    ::DiscourseMaps.apply_map_metadata(post.topic, location, from_map)
  end

  # --------------------------------------------------------------------------
  #  Exposes the topic's geographic data to the client (topic page), so
  #  the map can be drawn. The attribute is only included if present.
  # --------------------------------------------------------------------------
  add_to_serializer(
    :topic_view,
    :discourse_maps_location,
    include_condition: -> { object.topic.custom_fields[::DiscourseMaps::LOCATION_FIELD].present? },
  ) { object.topic.custom_fields[::DiscourseMaps::LOCATION_FIELD] }

  # --------------------------------------------------------------------------
  #  /map page controller.
  #   - HTML request: boots the Ember app (which then renders the page);
  #   - JSON request: returns the topics with the map tag + location.
  # --------------------------------------------------------------------------
  class ::DiscourseMaps::MapController < ::ApplicationController
    requires_plugin ::DiscourseMaps::PLUGIN_NAME

    # For the direct (HTML) page load this isn't an XHR request.
    skip_before_action :check_xhr, only: [:index]

    def index
      respond_to do |format|
        # Boots the Ember application: the client route will then request the JSON.
        format.html { render "default/empty" }

        # Data for the map and the list, filtered by user permissions and
        # by any category/tag filters passed as query parameters.
        format.json do
          tag_names = Array(params[:tags]&.split(","))
          country_names = Array(params[:countries]&.split(","))

          topics =
            ::DiscourseMaps.map_topics(
              guardian,
              category_id: params[:category_id],
              tag_names: tag_names,
              country_names: country_names,
              year: params[:year],
              month: params[:month],
              day: params[:day],
            )
          filters =
            ::DiscourseMaps.map_filter_options(
              guardian,
              category_id: params[:category_id],
              tag_names: tag_names,
              country_names: country_names,
              year: params[:year],
              month: params[:month],
              day: params[:day],
            )

          render json: { topics: topics, filters: filters }
        end
      end
    end
  end

  # Registers the /map route (serves both the HTML and /map.json).
  Discourse::Application.routes.append { get "/map" => "discourse_maps/map#index" }
end

