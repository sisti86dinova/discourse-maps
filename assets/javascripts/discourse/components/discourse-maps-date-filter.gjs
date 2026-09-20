// ============================================================================
//  Discourse Maps - Date filter for the /map page (year / month / day).
//
//  Replaces 3 separate comboboxes with a single "pill" control that opens
//  a panel (bottom sheet on mobile, anchored popover on desktop) with
//  progressive selection: year -> month -> day, each optional (you can
//  stop at any level, like in "Skyscanner-style" pickers).
//
//  Arguments:
//    @year/@month/@day       - currently selected values (Number or null).
//    @isToday                - true if @year/@month/@day match today's
//                              date, computed by the caller on the "raw"
//                              parameters (not sanitized based on
//                              @availableDays' availability): used to
//                              show "Today" instead of the date.
//    @availableYears         - [{id, name}] years with geolocated topics.
//    @availableMonths        - [{id, name}] months available for @year
//                              (name already localized, see map-page.gjs).
//    @availableDays          - [{id, name}] days available for @year+@month.
//    @onSelectYear/@onSelectMonth/@onSelectDay - callback(value|null).
// ============================================================================

import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { i18n } from "discourse-i18n";
import icon from "discourse/helpers/d-icon";

export default class DiscourseMapsDateFilter extends Component {
  @tracked isOpen = false;
  // null = no step forced: the "natural" step is used (the first level
  // still to be chosen, or the day if everything is already set). Set
  // explicitly when the user clicks a tab or selects a value.
  @tracked activeStep = null;

  get effectiveStep() {
    if (this.activeStep) {
      return this.activeStep;
    }
    if (!this.args.year) {
      return "year";
    }
    if (!this.args.month) {
      return "month";
    }
    return "day";
  }

  get isYearStep() {
    return this.effectiveStep === "year";
  }

  get isMonthStep() {
    return this.effectiveStep === "month";
  }

  get isDayStep() {
    return this.effectiveStep === "day";
  }

  get monthTabDisabled() {
    return !this.args.year;
  }

  get dayTabDisabled() {
    return !this.args.month;
  }

  // Label of the button that opens the panel: only the parts actually
  // selected (year / year+month / year+month+day), localized.
  get triggerLabel() {
    const { year, month, day } = this.args;
    if (!year) {
      return i18n("discourse_maps.filters.date_placeholder");
    }

    if (this.args.isToday) {
      return i18n("discourse_maps.filters.date_today");
    }

    const options = { year: "numeric" };
    if (month) {
      options.month = "long";
    }
    if (month && day) {
      options.day = "numeric";
    }

    const formatter = new Intl.DateTimeFormat(
      document.documentElement.lang || undefined,
      options
    );
    return formatter.format(new Date(year, (month || 1) - 1, day || 1));
  }

  // Weekday labels (Mon...Sun), localized: January 1, 2024 was a Monday,
  // used only as a reference to compute the names.
  get weekdayLabels() {
    const formatter = new Intl.DateTimeFormat(
      document.documentElement.lang || undefined,
      { weekday: "short" }
    );
    const labels = [];
    for (let i = 0; i < 7; i++) {
      labels.push(formatter.format(new Date(2024, 0, 1 + i)));
    }
    return labels;
  }

  // Calendar grid for @year/@month: weeks from Monday to Sunday, empty
  // cells (null) for leading/trailing padding. A day is selectable only
  // if present in @availableDays (has geolocated topics).
  get calendarWeeks() {
    const year = this.args.year;
    const month = this.args.month;
    if (!year || !month) {
      return [];
    }

    const availableSet = new Set((this.args.availableDays || []).map((d) => d.id));
    const daysInMonth = new Date(year, month, 0).getDate();
    const firstWeekday = new Date(year, month - 1, 1).getDay();
    const leadingBlanks = (firstWeekday + 6) % 7;

    const cells = new Array(leadingBlanks).fill(null);
    for (let day = 1; day <= daysInMonth; day++) {
      cells.push({
        day,
        available: availableSet.has(day),
        selected: this.args.day === day,
        isToday: this.isToday(year, month, day),
      });
    }
    while (cells.length % 7 !== 0) {
      cells.push(null);
    }

    const weeks = [];
    for (let i = 0; i < cells.length; i += 7) {
      weeks.push(cells.slice(i, i + 7));
    }
    return weeks;
  }

  isToday(year, month, day) {
    const today = new Date();
    return (
      today.getFullYear() === year &&
      today.getMonth() + 1 === month &&
      today.getDate() === day
    );
  }

  isSelected = (candidateId, currentValue) => candidateId === currentValue;

  toggle = () => {
    if (this.isOpen) {
      this.close();
    } else {
      this.open();
    }
  };

  open = () => {
    this.activeStep = null;
    this.isOpen = true;
  };

  close = () => {
    this.isOpen = false;
  };

  handleKeydown = (event) => {
    if (event.key === "Escape") {
      this.close();
    }
  };

  goToYearStep = () => {
    this.activeStep = "year";
  };

  goToMonthStep = () => {
    if (!this.monthTabDisabled) {
      this.activeStep = "month";
    }
  };

  goToDayStep = () => {
    if (!this.dayTabDisabled) {
      this.activeStep = "day";
    }
  };

  selectYear = (yearId) => {
    this.args.onSelectYear(yearId);
    this.activeStep = "month";
  };

  clearYear = () => {
    this.args.onSelectYear(null);
    this.activeStep = "year";
  };

  selectMonth = (monthId) => {
    this.args.onSelectMonth(monthId);
    this.activeStep = "day";
  };

  // Selecting a day is the most specific action possible: we close the
  // panel, there's no other level to move on to.
  selectDay = (day) => {
    this.args.onSelectDay(day);
    this.close();
  };

  <template>
    <div class="discourse-maps-date-filter" ...attributes>
      <button
        type="button"
        class="btn btn-default discourse-maps-date-filter__trigger"
        aria-expanded={{if this.isOpen "true" "false"}}
        {{on "click" this.toggle}}
      >
        <span class="discourse-maps-date-filter__trigger-label">{{this.triggerLabel}}</span>
        {{icon (if this.isOpen "angle-up" "angle-down")}}
      </button>

      {{#if this.isOpen}}
        <div
          class="discourse-maps-date-filter__backdrop"
          {{on "click" this.close}}
        ></div>

        <div
          class="discourse-maps-date-filter__panel"
          role="dialog"
          aria-label={{i18n "discourse_maps.filters.date_placeholder"}}
          {{on "keydown" this.handleKeydown}}
        >
          <div class="discourse-maps-date-filter__panel-header">
            <div class="discourse-maps-date-filter__tabs">
              <button
                type="button"
                class="discourse-maps-date-filter__tab {{if this.isYearStep 'active'}}"
                {{on "click" this.goToYearStep}}
              >
                {{i18n "discourse_maps.filters.all_years"}}
              </button>
              <button
                type="button"
                class="discourse-maps-date-filter__tab {{if this.isMonthStep 'active'}}"
                disabled={{this.monthTabDisabled}}
                {{on "click" this.goToMonthStep}}
              >
                {{i18n "discourse_maps.filters.all_months"}}
              </button>
              <button
                type="button"
                class="discourse-maps-date-filter__tab {{if this.isDayStep 'active'}}"
                disabled={{this.dayTabDisabled}}
                {{on "click" this.goToDayStep}}
              >
                {{i18n "discourse_maps.filters.all_days"}}
              </button>
            </div>

            <button
              type="button"
              class="discourse-maps-date-filter__close"
              aria-label={{i18n "discourse_maps.filters.date_close"}}
              {{on "click" this.close}}
            >
              {{icon "xmark"}}
            </button>
          </div>

          <div class="discourse-maps-date-filter__body">
            {{#if this.isYearStep}}
              <div class="discourse-maps-date-filter__grid">
                <button
                  type="button"
                  class="discourse-maps-date-filter__chip discourse-maps-date-filter__chip--any
                    {{unless @year 'active'}}"
                  {{on "click" this.clearYear}}
                >
                  {{i18n "discourse_maps.filters.date_any_year"}}
                </button>
                {{#each @availableYears as |year|}}
                  <button
                    type="button"
                    class="discourse-maps-date-filter__chip
                      {{if (this.isSelected year.id @year) 'active'}}"
                    {{on "click" (fn this.selectYear year.id)}}
                  >
                    {{year.name}}
                  </button>
                {{/each}}
              </div>
            {{else if this.isMonthStep}}
              <div class="discourse-maps-date-filter__grid">
                {{#each @availableMonths as |month|}}
                  <button
                    type="button"
                    class="discourse-maps-date-filter__chip
                      {{if (this.isSelected month.id @month) 'active'}}"
                    {{on "click" (fn this.selectMonth month.id)}}
                  >
                    {{month.name}}
                  </button>
                {{/each}}
              </div>
            {{else}}
              <div class="discourse-maps-date-filter__day-step">
                <div class="discourse-maps-date-filter__calendar">
                  <div class="discourse-maps-date-filter__weekdays">
                    {{#each this.weekdayLabels as |label|}}
                      <span>{{label}}</span>
                    {{/each}}
                  </div>
                  {{#each this.calendarWeeks as |week|}}
                    <div class="discourse-maps-date-filter__week">
                      {{#each week as |cell|}}
                        {{#if cell}}
                          <button
                            type="button"
                            class="discourse-maps-date-filter__day
                              {{if cell.selected 'active'}}
                              {{if cell.isToday 'today'}}"
                            disabled={{unless cell.available true false}}
                            {{on "click" (fn this.selectDay cell.day)}}
                          >
                            {{cell.day}}
                          </button>
                        {{else}}
                          <span class="discourse-maps-date-filter__day discourse-maps-date-filter__day--empty"></span>
                        {{/if}}
                      {{/each}}
                    </div>
                  {{/each}}
                </div>
              </div>
            {{/if}}
          </div>
        </div>
      {{/if}}
    </div>
  </template>
}
