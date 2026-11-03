// ============================================================================
//  Discourse Maps - Formatting of a geolocated topic's date range
//  (location.start_date / location.end_date).
// ============================================================================

// Dates are stored as "YYYY-MM-DD" strings: we build the Date by
// explicitly setting year/month/day instead of parsing the string, to
// avoid the timezone off-by-one that `new Date("YYYY-MM-DD")` would
// introduce (interpreted as UTC midnight, it can roll back to the
// previous day in the local timezone).
function toDate(value) {
  const [year, month, day] = value.split("-").map(Number);
  return new Date(year, month - 1, day);
}

function dateFormatter(options) {
  return new Intl.DateTimeFormat(
    document.documentElement.lang || undefined,
    options
  );
}

// Formats a topic's period (start/end) into a single, readable, localized
// label: only the start date if it matches the end date (single-day
// event), otherwise "start – end".
export default function formatDateRange(
  location,
  options = { year: "numeric", month: "short", day: "numeric" }
) {
  if (!location?.start_date || !location?.end_date) {
    return null;
  }

  const formatter = dateFormatter(options);
  const start = formatter.format(toDate(location.start_date));
  if (location.start_date === location.end_date) {
    return start;
  }
  const end = formatter.format(toDate(location.end_date));
  return `${start} – ${end}`;
}

// Same as above, but returns start/end as separate values (instead of a
// single already-joined string), for callers who need to lay them out
// differently via CSS (e.g. one below the other on mobile). `end` is
// null when the event lasts a single day: in that case only the start
// date should be shown.
export function formatDateParts(
  location,
  options = { year: "numeric", month: "long", day: "numeric" }
) {
  if (!location?.start_date || !location?.end_date) {
    return null;
  }

  const formatter = dateFormatter(options);
  const sameDay = location.start_date === location.end_date;

  return {
    start: formatter.format(toDate(location.start_date)),
    end: sameDay ? null : formatter.format(toDate(location.end_date)),
    sameDay,
  };
}
