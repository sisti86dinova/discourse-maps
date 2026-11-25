# frozen_string_literal: true

# Adversarial checks: each example tries to break a security property of
# the plugin through a direct request, bypassing the UI.
RSpec.describe "Discourse Maps attack surface" do
  fab!(:admin)
  fab!(:user) { Fabricate(:user, refresh_auto_groups: true) }
  fab!(:allowed_group, :group)
  fab!(:allowed_user) do
    Fabricate(:user, refresh_auto_groups: true).tap { |u| allowed_group.add(u) }
  end
  fab!(:map_tag) { Fabricate(:tag, name: "map") }
  fab!(:category)

  let(:location) do
    {
      address: "Piazza del Colosseo, Roma",
      lat: 41.89,
      lng: 12.49,
      display_name: "Colosseo, Roma, Italia",
      country_code: "IT",
      country: "Italia",
      start_date: "2026-12-01",
      end_date: "2026-12-02"
    }
  end

  before do
    SiteSetting.tagging_enabled = true
    SiteSetting.discourse_maps_enabled = true
    SiteSetting.discourse_maps_map_tag_id = map_tag.id
    SiteSetting.discourse_maps_new_topic_groups = allowed_group.id.to_s
  end

  def geolocate(topic, data = location)
    topic.custom_fields[DiscourseMaps::LOCATION_FIELD] = data
    topic.save_custom_fields(true)
    topic.tags << map_tag if topic.tags.exclude?(map_tag)
    topic
  end

  def map_json(params = {})
    get "/mappa.json", params: params
    expect(response.status).to eq(200)
    response.parsed_body
  end

  def create_topic(as:, **extra)
    sign_in(as)
    post "/posts.json",
         params: {
           title: "A geolocated event for the map page",
           raw: "This is the body of a geolocated event topic.",
           category: category.id
         }.merge(extra)
    response
  end

  describe "read-restricted categories" do
    fab!(:secret_group, :group)
    fab!(:secret_category) do
      Fabricate(:private_category, group: secret_group, name: "Secret plans")
    end
    fab!(:secret_tag) { Fabricate(:tag, name: "secret-only-tag") }
    fab!(:secret_topic) do
      Fabricate(:topic, category: secret_category, tags: [secret_tag])
    end
    fab!(:public_topic) { Fabricate(:topic, category:) }

    before do
      geolocate(
        secret_topic,
        location.merge(
          country_code: "JP",
          start_date: "2031-05-05",
          end_date: "2031-05-06"
        )
      )
      geolocate(public_topic)
    end

    it "leaks nothing about them through the topics or the filter options" do
      sign_in(user)
      body = map_json

      expect(body["topics"].map { |t| t["id"] }).to eq([public_topic.id])
      expect(body["filters"]["category_ids"]).not_to include(secret_category.id)
      expect(body["filters"]["tags"].map { |t| t["name"] }).not_to include(
        secret_tag.name
      )
      expect(body["filters"]["countries"].map { |c| c["id"] }).not_to include(
        "JP"
      )
      expect(body["filters"]["years"].map { |y| y["id"] }).not_to include(2031)
    end

    it "can't be reached by filtering on their category id" do
      sign_in(user)
      expect(map_json(category_id: secret_category.id)["topics"]).to be_empty
    end

    it "are visible to members of the group" do
      secret_group.add(user)
      sign_in(user)
      expect(map_json["topics"].map { |t| t["id"] }).to include(secret_topic.id)
    end
  end

  describe "hidden tags" do
    fab!(:hidden_tag) { Fabricate(:tag, name: "staff-eyes-only") }
    fab!(:tag_group) do
      Fabricate(
        :tag_group,
        permissions: {
          "staff" => 1
        },
        tag_names: [hidden_tag.name]
      )
    end
    fab!(:topic) { Fabricate(:topic, category:, tags: [hidden_tag]) }

    before { geolocate(topic) }

    it "aren't exposed to regular users in the topics" do
      sign_in(user)
      tags = map_json["topics"].flat_map { |t| t["tags"] }
      expect(tags).not_to include(hidden_tag.name)
    end

    it "aren't exposed to regular users in the filter options" do
      sign_in(user)
      names = map_json["filters"]["tags"].map { |t| t["name"] }
      expect(names).not_to include(hidden_tag.name)
    end

    it "can't be used to probe which topics carry them" do
      sign_in(user)
      expect(map_json(tags: hidden_tag.name)["topics"]).to be_empty
    end

    it "are shown to staff" do
      sign_in(admin)
      expect(map_json["topics"].flat_map { |t| t["tags"] }).to include(
        hidden_tag.name
      )
    end
  end

  describe "topics that must never be on the map" do
    it "excludes deleted topics" do
      topic = geolocate(Fabricate(:topic, category:))
      topic.trash!
      sign_in(admin)
      expect(map_json["topics"]).to be_empty
    end

    it "excludes private messages, even carrying a location and the tag" do
      pm = geolocate(Fabricate(:private_message_topic, user: admin))
      sign_in(admin)
      expect(map_json["topics"].map { |t| t["id"] }).not_to include(pm.id)
    end

    it "doesn't geolocate a private message sent by an allowed user" do
      sign_in(admin)
      post "/posts.json",
           params: {
             title: "A private message with a location",
             raw: "This is the body of a private message.",
             archetype: Archetype.private_message,
             target_recipients: user.username,
             discourse_maps_location: location
           }
      expect(response.status).to eq(200)
      expect(map_json["topics"]).to be_empty
    end
  end

  describe "payload tampering on topic creation" do
    def stored_location
      topic_id = response.parsed_body["topic_id"]
      Topic.find(topic_id).custom_fields[DiscourseMaps::LOCATION_FIELD]
    end

    it "drops unknown keys and keeps only the whitelisted ones" do
      create_topic(
        as: allowed_user,
        discourse_maps_location:
          location.merge(:is_admin => true, "__proto__" => { polluted: 1 })
      )
      expect(response.status).to eq(200)
      expect(stored_location.keys).to match_array(
        %w[
          address
          lat
          lng
          display_name
          country_code
          country
          start_date
          end_date
        ]
      )
    end

    it "truncates oversized strings" do
      create_topic(
        as: allowed_user,
        discourse_maps_location:
          location.merge(address: "A" * 100_000, display_name: "B" * 100_000)
      )
      expect(response.status).to eq(200)
      expect(stored_location["address"].length).to be <= 500
      expect(stored_location["display_name"].length).to be <= 500
    end

    it "rejects an invalid country code instead of storing it" do
      create_topic(
        as: allowed_user,
        discourse_maps_location:
          location.merge(country_code: "<script>alert(1)</script>")
      )
      expect(response.status).to eq(200)
      expect(stored_location["country_code"]).to be_nil
    end

    %w[NaN Infinity -Infinity 1e400 91 abc].each do |bad_lat|
      it "refuses a topic whose latitude is #{bad_lat}" do
        create_topic(
          as: allowed_user,
          discourse_maps_location: location.merge(lat: bad_lat)
        )
        expect(response.status).to eq(422)
      end
    end

    it "refuses dates that aren't dates" do
      create_topic(
        as: allowed_user,
        discourse_maps_location:
          location.merge(start_date: "'; DROP TABLE topics;--")
      )
      expect(response.status).to eq(422)
    end

    it "refuses an end date before the start date" do
      create_topic(
        as: allowed_user,
        discourse_maps_location:
          location.merge(start_date: "2026-12-10", end_date: "2026-12-01")
      )
      expect(response.status).to eq(422)
    end

    it "ignores a location sent with a reply" do
      topic = Fabricate(:topic, category:)
      Fabricate(:post, topic:)
      sign_in(allowed_user)
      post "/posts.json",
           params: {
             topic_id: topic.id,
             raw: "A reply trying to geolocate the topic.",
             discourse_maps_location: location
           }
      expect(response.status).to eq(200)
      expect(
        topic.reload.custom_fields[DiscourseMaps::LOCATION_FIELD]
      ).to be_nil
      expect(topic.tags).not_to include(map_tag)
    end
  end

  describe "the from_map flag" do
    it "doesn't tag the topic for users outside the allowed groups" do
      create_topic(as: user, discourse_maps_from_map: true)
      expect(response.status).to eq(200)
      topic = Topic.find(response.parsed_body["topic_id"])
      expect(topic.tags).not_to include(map_tag)
    end

    it "tags the topic for allowed users, even without a location" do
      create_topic(as: allowed_user, discourse_maps_from_map: true)
      expect(response.status).to eq(200)
      topic = Topic.find(response.parsed_body["topic_id"])
      expect(topic.tags).to include(map_tag)
    end
  end

  describe "moderation queue" do
    # Only admins and moderators skip the queue.
    before do
      SiteSetting.approve_unless_allowed_groups = "1|2"
      SiteSetting.approve_new_topics_unless_allowed_groups = "1|2"
    end

    def queue_topic(as:)
      create_topic(as: as, discourse_maps_location: location)
      expect(response.status).to eq(200)
      ReviewableQueuedPost.where(target_created_by: as).last
    end

    it "doesn't geolocate a queued topic from an unauthorized user on approval" do
      reviewable = queue_topic(as: user)
      expect(reviewable).to be_present
      reviewable.perform(admin, :approve_post)
      topic = reviewable.reload.target.topic
      expect(topic.custom_fields[DiscourseMaps::LOCATION_FIELD]).to be_nil
      expect(topic.tags).not_to include(map_tag)
    end

    it "geolocates a queued topic from an allowed user on approval" do
      reviewable = queue_topic(as: allowed_user)
      expect(reviewable).to be_present
      reviewable.perform(admin, :approve_post)
      topic = reviewable.reload.target.topic
      expect(topic.custom_fields[DiscourseMaps::LOCATION_FIELD]).to be_present
      expect(topic.tags).to include(map_tag)
    end
  end

  describe "editing" do
    fab!(:map_topic) { Fabricate(:topic, user: allowed_user, category:) }
    fab!(:first_post) { Fabricate(:post, topic: map_topic, user: allowed_user) }

    before { geolocate(map_topic) }

    it "doesn't let another user change the location of a post they can't edit" do
      sign_in(user)
      put "/posts/#{first_post.id}.json",
          params: {
            post: {
              raw: "Hijacked body of the event topic.",
              discourse_maps_location: location.merge(lat: 10)
            }
          }
      expect(response.status).to eq(403)
      expect(
        map_topic.reload.custom_fields[DiscourseMaps::LOCATION_FIELD]["lat"]
      ).to eq(41.89)
    end

    it "doesn't let another user remove the location" do
      sign_in(user)
      put "/posts/#{first_post.id}.json",
          params: {
            post: {
              raw: "Hijacked body of the event topic.",
              discourse_maps_location: ""
            }
          }
      expect(response.status).to eq(403)
      expect(map_topic.reload.tags).to include(map_tag)
    end
  end

  describe "editing the author's own geolocated topic" do
    fab!(:own_topic) { Fabricate(:topic, user: allowed_user, category:) }
    fab!(:own_post) { Fabricate(:post, topic: own_topic, user: allowed_user) }

    before do
      geolocate(own_topic)
      sign_in(allowed_user)
    end

    def edit(**post_params)
      put "/posts/#{own_post.id}.json",
          params: {
            post: {
              raw: "Edited body #{SecureRandom.hex(4)} of the event."
            }.merge(post_params)
          }
    end

    def stored_location
      own_topic.reload.custom_fields[DiscourseMaps::LOCATION_FIELD]
    end

    it "keeps the location when the edit doesn't carry one" do
      edit
      expect(response.status).to eq(200)
      expect(stored_location).to be_present
      expect(own_topic.tags).to include(map_tag)
    end

    it "keeps the location on an explicit null" do
      put "/posts/#{own_post.id}.json",
          params: {
            post: {
              raw: "Edited body #{SecureRandom.hex(4)} of the event.",
              discourse_maps_location: nil
            }
          }.to_json,
          headers: {
            "CONTENT_TYPE" => "application/json"
          }
      expect(response.status).to eq(200)
      expect(stored_location).to be_present
    end

    ["not a hash", %w[a b], "42"].each do |value|
      it "ignores #{value.inspect} without failing" do
        edit(discourse_maps_location: value)
        expect(response.status).to eq(200)
        expect(stored_location["lat"]).to eq(41.89)
      end
    end

    it "removes the location on the explicit remove value" do
      edit(discourse_maps_location: "")
      expect(response.status).to eq(200)
      expect(stored_location).to be_blank
      expect(own_topic.tags).not_to include(map_tag)
    end
  end

  describe "/mappa.json input handling" do
    fab!(:topic) { Fabricate(:topic, category:) }

    before { geolocate(topic) }

    [
      { tags: "x' OR '1'='1" },
      { countries: "IT') OR 1=1--" },
      { category_id: "1 OR 1=1" },
      { year: "2026; DROP TABLE topics" },
      { year: "99999999999999999999" },
      { year: "2026", month: "2", day: "31" },
      { tags: (["t"] * 5000).join(",") },
      { upcoming: { nested: "hash" } }
    ].each do |params|
      it "handles #{params.inspect.truncate(60)} without errors" do
        body = map_json(params)
        expect(body).to have_key("topics")
      end
    end

    it "returns titles with HTML escaped" do
      topic.update!(title: "Evil <img src=x onerror=alert(1)> event title")
      body = map_json
      expect(body["topics"].first["fancy_title"]).not_to include("<img")
    end
  end

  describe "site and plugin configuration" do
    it "returns 404 when the plugin is disabled" do
      SiteSetting.discourse_maps_enabled = false
      get "/mappa.json"
      expect(response.status).to eq(404)
    end

    it "requires login when the site does" do
      SiteSetting.login_required = true
      get "/mappa.json"
      expect(response.status).to eq(403)
    end
  end
end
