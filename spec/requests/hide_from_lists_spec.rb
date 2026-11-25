# frozen_string_literal: true

RSpec.describe "Hiding map topics from topic lists" do
  fab!(:user) { Fabricate(:user, refresh_auto_groups: true) }
  fab!(:map_tag) { Fabricate(:tag, name: "map") }
  fab!(:category)
  fab!(:map_topic) { Fabricate(:topic, category:, tags: [map_tag]) }
  fab!(:regular_topic) { Fabricate(:topic, category:) }

  before do
    SiteSetting.tagging_enabled = true
    SiteSetting.discourse_maps_enabled = true
    SiteSetting.discourse_maps_map_tag_id = map_tag.id
    Fabricate(:post, topic: map_topic)
    Fabricate(:post, topic: regular_topic)
  end

  def topic_ids(path)
    get path
    expect(response.status).to eq(200)
    response.parsed_body["topic_list"]["topics"].map { |t| t["id"] }
  end

  let(:category_latest) { "/c/#{category.slug}/#{category.id}/l/latest.json" }
  let(:tag_latest) { "/tag/#{map_tag.name}/l/latest.json" }

  context "when no list is selected" do
    it "shows map topics everywhere" do
      expect(topic_ids("/latest.json")).to include(
        map_topic.id,
        regular_topic.id
      )
    end
  end

  context "when latest is selected" do
    before { SiteSetting.discourse_maps_hide_from_lists = "latest" }

    it "hides map topics from /latest" do
      ids = topic_ids("/latest.json")
      expect(ids).to include(regular_topic.id)
      expect(ids).not_to include(map_topic.id)
    end

    it "keeps map topics in lists that aren't selected" do
      sign_in(user)
      expect(topic_ids("/new.json")).to include(map_topic.id)
    end

    it "keeps map topics on category and tag pages by default" do
      expect(topic_ids(category_latest)).to include(map_topic.id)
      expect(topic_ids(tag_latest)).to include(map_topic.id)
    end

    it "hides map topics on category pages when enabled" do
      SiteSetting.discourse_maps_hide_on_category_pages = true
      expect(topic_ids(category_latest)).not_to include(map_topic.id)
      expect(topic_ids(tag_latest)).to include(map_topic.id)
    end

    it "hides map topics on tag pages when enabled" do
      SiteSetting.discourse_maps_hide_on_tag_pages = true
      expect(topic_ids(tag_latest)).not_to include(map_topic.id)
      expect(topic_ids(category_latest)).to include(map_topic.id)
    end
  end

  context "when new is selected" do
    before { SiteSetting.discourse_maps_hide_from_lists = "new" }

    it "hides map topics from /new" do
      sign_in(user)
      ids = topic_ids("/new.json")
      expect(ids).to include(regular_topic.id)
      expect(ids).not_to include(map_topic.id)
    end
  end

  describe "suggested topics" do
    fab!(:current_topic) { Fabricate(:post, topic: Fabricate(:topic)).topic }

    def suggested_ids
      get "/t/#{current_topic.id}.json"
      expect(response.status).to eq(200)
      response.parsed_body["suggested_topics"].map { |t| t["id"] }
    end

    it "hides map topics when suggested is selected" do
      SiteSetting.discourse_maps_hide_from_lists = "suggested"
      ids = suggested_ids
      expect(ids).to include(regular_topic.id)
      expect(ids).not_to include(map_topic.id)
    end

    it "keeps map topics when suggested isn't selected" do
      expect(suggested_ids).to include(map_topic.id)
    end
  end
end
