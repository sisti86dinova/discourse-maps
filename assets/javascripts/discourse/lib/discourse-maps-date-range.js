// ============================================================================
//  Discourse Maps - Formattazione dell'intervallo di date di un topic
//  geolocalizzato (location.start_date / location.end_date).
// ============================================================================

// Formatta il periodo (inizio/fine) di un topic in un'unica etichetta
// leggibile, localizzata: solo la data di inizio se coincide con quella di
// fine (evento di un giorno), altrimenti "inizio – fine". Le date sono
// salvate come stringhe "YYYY-MM-DD": costruiamo il Date esplicitando
// anno/mese/giorno invece di parsare la stringa, per evitare l'off-by-one
// dovuto al fuso orario che `new Date("YYYY-MM-DD")` applicherebbe
// (interpretata come UTC mezzanotte, può scadere al giorno prima nel fuso
// locale).
export default function formatDateRange(location) {
  if (!location?.start_date || !location?.end_date) {
    return null;
  }

  const formatter = new Intl.DateTimeFormat(
    document.documentElement.lang || undefined,
    { year: "numeric", month: "short", day: "numeric" }
  );
  const toDate = (value) => {
    const [year, month, day] = value.split("-").map(Number);
    return new Date(year, month - 1, day);
  };

  const start = formatter.format(toDate(location.start_date));
  if (location.start_date === location.end_date) {
    return start;
  }
  const end = formatter.format(toDate(location.end_date));
  return `${start} – ${end}`;
}
