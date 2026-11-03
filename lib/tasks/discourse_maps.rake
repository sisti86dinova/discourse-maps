# frozen_string_literal: true

# ============================================================================
#  Discourse Maps - maintenance tasks.
# ============================================================================

# Reverse geocoding (coordinates -> country) through the configured provider.
# It lives here, and not in the plugin's runtime code, because it's the only
# server-side call to the providers: the plugin geocodes from the browser,
# this is needed just once by the backfill task below.
module DiscourseMapsBackfill
  # Delay between two calls: LocationIQ's free tier allows 2 requests per
  # second, and the task is a one-off, so we stay well under the limit.
  DELAY = 1.0

  def self.reverse_geocode(lat, lng, provider, api_key, locale)
    body = get_json(reverse_url(lat, lng, provider, api_key, locale))
    return nil if body.nil?

    provider == "google" ? google_country(body) : locationiq_country(body)
  end

  def self.reverse_url(lat, lng, provider, api_key, locale)
    if provider == "google"
      "https://maps.googleapis.com/maps/api/geocode/json?latlng=#{lat},#{lng}" \
        "&language=#{CGI.escape(locale)}&key=#{CGI.escape(api_key)}"
    else
      "https://us1.locationiq.com/v1/reverse?key=#{CGI.escape(api_key)}" \
        "&lat=#{lat}&lon=#{lng}&format=json&accept-language=#{CGI.escape(locale)}"
    end
  end

  def self.get_json(url)
    response = Excon.get(url, read_timeout: 10, connect_timeout: 10)
    return nil if response.status != 200

    JSON.parse(response.body)
  rescue Excon::Error, JSON::ParserError => e
    puts "  request failed: #{e.class}"
    nil
  end

  def self.locationiq_country(body)
    address = body["address"]
    code = address&.dig("country_code")
    return nil if code.blank?

    { code: code.upcase, name: address["country"] }
  end

  def self.google_country(body)
    component =
      body["results"]&.first&.dig("address_components")&.find { |c| c["types"].include?("country") }
    code = component&.dig("short_name")
    return nil if code.blank?

    { code: code.upcase, name: component["long_name"] }
  end
end

# ----------------------------------------------------------------------------
#  Reverse-geocodes the topics saved before the country was identified by its
#  ISO 3166-1 alpha-2 code, so the /map filter stops listing the same country
#  once per language it happened to be saved in ("Italia" / "Italy").
#
#  Only locations without a country_code are touched, and each distinct
#  position is resolved once: re-running the task after a partial run
#  (interrupted, provider temporarily unreachable) only does the rest.
#
#  Usage: bin/rake discourse_maps:backfill_country_codes
# ----------------------------------------------------------------------------
desc "Adds the ISO country code to geolocated topics saved without one"
task "discourse_maps:backfill_country_codes" => :environment do
  locale = SiteSetting.default_locale.to_s.tr("_", "-")
  provider = SiteSetting.discourse_maps_provider
  api_key =
    if provider == "google"
      SiteSetting.discourse_maps_google_api_key
    else
      SiteSetting.discourse_maps_locationiq_api_key
    end

  abort("No API key configured for the \"#{provider}\" provider.") if api_key.blank?

  # Several topics at the same position (a recurring venue): one call each.
  resolved = {}
  updated = 0
  failed = 0

  TopicCustomField
    .where(name: ::DiscourseMaps::LOCATION_FIELD)
    .find_each do |field|
      data = ::DiscourseMaps.parse_location(field.value)
      next if data.nil? || data["country_code"].present?

      lat = data["lat"]
      lng = data["lng"]
      if lat.blank? || lng.blank?
        puts "topic #{field.topic_id}: no coordinates, skipped"
        next
      end

      key = [lat.to_f.round(5), lng.to_f.round(5)]

      unless resolved.key?(key)
        sleep(DiscourseMapsBackfill::DELAY) if resolved.any?
        resolved[key] = DiscourseMapsBackfill.reverse_geocode(*key, provider, api_key, locale)
      end

      country = resolved[key]
      if country.nil?
        failed += 1
        puts "topic #{field.topic_id}: reverse geocoding failed, left unchanged"
        next
      end

      data["country_code"] = country[:code]
      data["country"] = country[:name] if country[:name].present?
      field.update!(value: data.to_json)
      updated += 1
      puts "topic #{field.topic_id}: #{country[:code]} (#{country[:name]})"
    end

  puts "Done: #{updated} topic(s) updated, #{failed} failed."
end
