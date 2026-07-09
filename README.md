# Discourse Maps

Plugin per Discourse che permette di inserire informazioni geografiche nei
topic e di visualizzarle su una mappa interattiva, con una pagina dedicata
`/map` che raccoglie tutti i topic geolocalizzati.

## Stato di avanzamento

Lo sviluppo procede per gradi. Stato attuale:

- [x] **Step 1 — Struttura del plugin** (scheletro, impostazioni, traduzioni)
- [x] **Step 2 — Inserimento dati geografici nel composer** + tag automatico (id 295)
- [x] **Step 3 — Pagina `/map` con mappa interattiva**
- [x] **Step 4 — Filtri per categorie e tag**

## Configurazione

Dopo l'installazione, in **Admin > Impostazioni > Plugin**:

| Impostazione | Descrizione |
|---|---|
| `discourse_maps_enabled` | Abilita/disabilita il plugin. |
| `discourse_maps_map_tag_id` | ID del tag "mappa" (default: `295`). |
| `discourse_maps_provider` | Provider mappa/geocoding: `locationiq` o `google`. |
| `discourse_maps_locationiq_api_key` | Chiave API LocationIQ. |
| `discourse_maps_google_api_key` | Chiave API Google Maps. |

## Provider supportati

Il plugin è progettato per funzionare con due provider intercambiabili:

- **LocationIQ** — tiles OpenStreetMap + geocoding (5.000 richieste/giorno gratuite).
- **Google Maps** — Maps JavaScript API + Google Geocoding.

## Struttura del progetto

```
discourse-maps/
├── plugin.rb                     # Entry point lato server (metadati, settings)
├── about.json                    # Metadati del plugin
├── config/
│   ├── settings.yml              # Impostazioni configurabili da admin
│   └── locales/
│       ├── server.en.yml         # Traduzioni impostazioni (EN)
│       ├── server.it.yml         # Traduzioni impostazioni (IT)
│       ├── client.en.yml         # Traduzioni lato client (EN)
│       └── client.it.yml         # Traduzioni lato client (IT)
└── assets/
    ├── javascripts/discourse/
    │   ├── discourse-maps-route-map.js     # Registrazione rotta client /map
    │   ├── initializers/
    │   │   └── discourse-maps.js          # Pulsante composer + serializzazione + link sidebar
    │   ├── routes/
    │   │   └── map.js                      # Rotta /map (carica i topic dal server)
    │   ├── controllers/
    │   │   └── map.js                      # Query param dei filtri (categoria/tag)
    │   ├── templates/
    │   │   └── map.hbs                     # Template della pagina /map
    │   ├── components/
    │   │   ├── discourse-maps-map.gjs      # Mappa riutilizzabile (Leaflet/Google)
    │   │   ├── discourse-maps-location-modal.gjs  # Modal inserimento indirizzo
    │   │   └── map-page.gjs                # Pagina /map: mappa + lista topic
    │   ├── connectors/topic-above-post-stream/
    │   │   └── discourse-maps-topic-map.gjs  # Mappa nella pagina del topic
    │   └── lib/
    │       └── discourse-maps-provider.js  # Astrazione provider + geocoding
    └── stylesheets/common/
        └── discourse-maps.scss             # Stili comuni + media query responsive
```



