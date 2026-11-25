# frozen_string_literal: true

RSpec.describe "Discourse Maps routes" do
  before { SiteSetting.discourse_maps_enabled = true }

  it "serves the page and its data at MAP_PATH" do
    get DiscourseMaps::MAP_PATH
    expect(response.status).to eq(200)

    get "#{DiscourseMaps::MAP_PATH}.json"
    expect(response.status).to eq(200)
    expect(response.parsed_body).to include("topics", "filters")
  end

  it "leaves /map free for other plugins" do
    expect(DiscourseMaps::MAP_PATH).not_to eq("/map")

    get "/map.json"
    expect(response.status).to eq(404)
  end
end
