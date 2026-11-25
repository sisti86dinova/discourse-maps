// ============================================================================
//  Discourse Maps - Formatting of a geolocated topic's date range
//  (location.start_date / location.end_date).
// ============================================================================

// Dates are stored as "YYYY-MM-DD" strings: we build the Date by
// explicitly setting year/month/day instead of parsing the string, to
// avoid the timezone off-by-one that `new Date("YYYY-MM-DD")` would
// introduce (interpreted as UTC midnight, it can roll back to the
// previous day in the local timezone).
// Returns null for anything that isn't a valid "YYYY-MM-DD" date:
// Intl.DateTimeFormat#format throws on an invalid Date, and one malformed
// topic (e.g. saved before the server validated dates) would otherwise
// break the rendering of the whole /mappa page.
function toDate(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value ?? ""));
  if (!match) {
    return null;
  }
  const [year, month, day] = match.slice(1).map(Number);
  const date = new Date(year, month - 1, day);
  // Date rolls impossible values over (2026-13-45 becomes 2027-02-14)
  // instead of rejecting them.
  const valid =
    date.getFullYear() === year &&
    date.getMonth() === month - 1 &&
    date.getDate() === day;
  return valid ? date : null;
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
  const startDate = toDate(location?.start_date);
  const endDate = toDate(location?.end_date);
  if (!startDate || !endDate) {
    return null;
  }

  const formatter = dateFormatter(options);
  const start = formatter.format(startDate);
  if (location.start_date === location.end_date) {
    return start;
  }
  return `${start} – ${formatter.format(endDate)}`;
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
  const startDate = toDate(location?.start_date);
  const endDate = toDate(location?.end_date);
  if (!startDate || !endDate) {
    return null;
  }

  const formatter = dateFormatter(options);
  const sameDay = location.start_date === location.end_date;

  return {
    start: formatter.format(startDate),
    end: sameDay ? null : formatter.format(endDate),
    sameDay,
  };
}
