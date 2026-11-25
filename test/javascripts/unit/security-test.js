import { setupTest } from "ember-qunit";
import { module, test } from "qunit";
import MapPage from "discourse/plugins/discourse-maps/discourse/components/map-page";
import formatDateRange, {
  formatDateParts,
} from "discourse/plugins/discourse-maps/discourse/lib/discourse-maps-date-range";
import { popupContent } from "discourse/plugins/discourse-maps/discourse/lib/discourse-maps-provider";

const PAYLOAD = `<img src=x onerror="window.__mapsXss = true">`;

function assertNoMarkup(assert, html) {
  const container = document.createElement("div");
  container.innerHTML = html;
  assert.strictEqual(
    container.querySelector("img, script, iframe, [onerror], [onclick]"),
    null,
    "no injected element or event handler"
  );
}

module("Discourse Maps | Unit | security", function (hooks) {
  setupTest(hooks);

  test("geocoder addresses are escaped before reaching a popup", function (assert) {
    const content = popupContent({ display_name: PAYLOAD });

    assertNoMarkup(assert, content);
    assert.true(content.includes("&lt;img"), "rendered as text");
  });

  test("popup HTML built by the caller is used as is", function (assert) {
    assert.strictEqual(
      popupContent({ popupHtml: "<strong>ok</strong>", display_name: PAYLOAD }),
      "<strong>ok</strong>"
    );
    assert.strictEqual(popupContent({}), null);
  });

  test("/map popups escape titles, categories, tags and urls", function (assert) {
    // Glimmer only lets the renderer instantiate components: run the real
    // getter on an object inheriting from MapPage, with controlled inputs.
    const page = Object.create(MapPage.prototype);
    Object.defineProperty(page, "site", {
      value: {
        categories: [
          {
            id: 7,
            name: PAYLOAD,
            url: `"><img src=x onerror="window.__mapsXss = true">`,
            color: "0088CC",
          },
        ],
      },
    });
    Object.defineProperty(page, "args", {
      value: {
        topics: [
          {
            id: 1,
            title: PAYLOAD,
            url: `"><img src=x onerror="window.__mapsXss = true">`,
            category_id: 7,
            tags: [PAYLOAD],
            location: {
              lat: 41.9,
              lng: 12.5,
              display_name: PAYLOAD,
              start_date: "2026-12-01",
              end_date: "2026-12-02",
            },
          },
        ],
      },
    });

    const [marker] = page.markers;
    assertNoMarkup(assert, marker.popupHtml);
  });

  test("malformed dates don't throw", function (assert) {
    for (const value of [
      "not-a-date",
      "2026-13-45",
      "<script>",
      12345,
      null,
      { year: 2026 },
    ]) {
      const location = { start_date: value, end_date: "2026-12-02" };
      assert.strictEqual(formatDateRange(location), null, String(value));
      assert.strictEqual(formatDateParts(location), null, String(value));
    }
  });

  test("valid dates are still formatted", function (assert) {
    const location = { start_date: "2026-12-01", end_date: "2026-12-01" };

    assert.strictEqual(typeof formatDateRange(location), "string");
    assert.true(formatDateParts(location).sameDay);
  });
});
