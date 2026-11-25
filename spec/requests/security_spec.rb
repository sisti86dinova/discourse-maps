# frozen_string_literal: true

RSpec.describe "Discourse Maps security" do
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

  def create_topic_with_location(as:)
    sign_in(as)
    post "/posts.json",
         params: {
           title: "A geolocated event for the map page",
           raw: "This is the body of a geolocated event topic.",
           category: category.id,
           discourse_maps_location: location
         }
    expect(response.status).to eq(200)
    Topic.find(response.parsed_body["topic_id"])
  end

  def on_map?(topic)
    topic.reload
    topic.custom_fields[DiscourseMaps::LOCATION_FIELD].present? ||
      topic.tags.include?(map_tag)
  end

  describe "adding a location on topic creation" do
    it "is ignored for users outside the allowed groups" do
      expect(on_map?(create_topic_with_location(as: user))).to eq(false)
    end

    it "is applied for users in the allowed groups" do
      expect(on_map?(create_topic_with_location(as: allowed_user))).to eq(true)
    end

    it "is applied for admins" do
      expect(on_map?(create_topic_with_location(as: admin))).to eq(true)
    end
  end

  describe "adding a location by editing the first post" do
    fab!(:own_topic) { Fabricate(:topic, user:, category:) }
    fab!(:first_post) { Fabricate(:post, topic: own_topic, user:) }

    it "is ignored when the topic isn't on the map and the author isn't allowed" do
      sign_in(user)
      put "/posts/#{first_post.id}.json",
          params: {
            post: {
              raw: "#{first_post.raw} edited",
              discourse_maps_location: location
            }
          }
      expect(response.status).to eq(200)
      expect(on_map?(own_topic)).to eq(false)
    end

    it "updates the location of a topic that is already on the map" do
      own_topic.custom_fields[DiscourseMaps::LOCATION_FIELD] = location.merge(
        lat: 45.0
      )
      own_topic.save_custom_fields(true)
      own_topic.tags << map_tag

      sign_in(user)
      put "/posts/#{first_post.id}.json",
          params: {
            post: {
              raw: "#{first_post.raw} edited",
              discourse_maps_location: location
            }
          }
      expect(response.status).to eq(200)
      expect(
        own_topic.reload.custom_fields[DiscourseMaps::LOCATION_FIELD]["lat"]
      ).to eq(41.89)
    end
  end

  describe "/map.json" do
    fab!(:listed) { Fabricate(:topic, category:, tags: [map_tag]) }
    fab!(:unlisted) do
      Fabricate(:topic, category:, tags: [map_tag], visible: false)
    end

    before do
      [listed, unlisted].each do |t|
        t.custom_fields[DiscourseMaps::LOCATION_FIELD] = location
        t.save_custom_fields(true)
      end
    end

    def map_topic_ids
      get "/map.json"
      expect(response.status).to eq(200)
      response.parsed_body["topics"].map { |t| t["id"] }
    end

    it "doesn't expose unlisted topics to regular users" do
      sign_in(user)
      expect(map_topic_ids).to include(listed.id)
      expect(map_topic_ids).not_to include(unlisted.id)
    end

    it "doesn't expose unlisted topics to anonymous users" do
      expect(map_topic_ids).not_to include(unlisted.id)
    end

    it "shows unlisted topics to staff, like core topic lists" do
      sign_in(admin)
      expect(map_topic_ids).to include(listed.id, unlisted.id)
    end

    it "doesn't fail on array query params" do
      get "/map.json", params: { tags: ["a"], countries: { x: "IT" } }
      expect(response.status).to eq(200)
    end

    it "doesn't fail on an out of range month" do
      get "/map.json", params: { year: 2026, month: 13 }
      expect(response.status).to eq(200)
    end
  end
end
