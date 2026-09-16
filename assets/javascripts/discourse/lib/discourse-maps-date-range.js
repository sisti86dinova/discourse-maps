// ============================================================================
//  Discourse Maps - Formattazione dell'intervallo di date di un topic
//  geolocalizzato (location.start_date / location.end_date).
// ============================================================================

// Le date sono salvate come stringhe "YYYY-MM-DD": costruiamo il Date
// esplicitando anno/mese/giorno invece di parsare la stringa, per evitare
// l'off-by-one dovuto al fuso orario che `new Date("YYYY-MM-DD")`
// applicherebbe (interpretata come UTC mezzanotte, può scadere al giorno
// prima nel fuso locale).
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

// Formatta il periodo (inizio/fine) di un topic in un'unica etichetta
// leggibile, localizzata: solo la data di inizio se coincide con quella di
// fine (evento di un giorno), altrimenti "inizio – fine".
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

// Come sopra, ma restituisce inizio/fine come valori separati (invece di
// un'unica stringa già unita), per chi deve disporli diversamente via CSS
// (es. una sotto l'altra su mobile). `end` è null quando l'evento dura un
// solo giorno: in quel caso va mostrata solo la data di inizio.
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
