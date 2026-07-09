# Discourse Maps

## Project description

- Plugin per Discourse
- Versione Discourse: 2026.6.0-latest (f8e4a6a002) su Docker

## Project structure

- Il plugin deve:
  - permettere agli utenti di inserire nei topics, informazioni geografiche (indirizzo, cap, città, nazione) ottenendo una mappa all'interno del topic
  - quando utilizzo il plugin sui topics, questi saranno automaticamente associati al tag mappa (id: 295)
  - avere una pagina (/map) in cui vengono raccolti tutti i topic di discourse che hanno utilizzato la funzionalità del plugin (quindi che hanno il tag id 295)
  - nella pagina /map sarà presente a top pagina una mappa con tutti i pin presenti nei topic con tag mappa interattiva (es. leaflet.js), e a seguire la lista dei topic
  - devo avere la possibilità di filtrare i topic per: categorie e tags (ovviamente il filtro deve sempre prevedere il tag mappa con id 295)
  - la mappa della pagina /map, deve essere interattiva, con la possibilità di zoomare e spostarsi, e cliccando su un pin si deve aprire un popup con il titolo del topic, categoria e tags, e un link al topic stesso
  - la mappa deve essere responsive e funzionare su tutti i dispositivi (non devi fare niente di chè, solamente prevedere media query per la mappa)

## Richieste
  - mi piacerebbe che andassi per gradi, quindi prima di tutto creiamo la struttura del plugin, poi implementiamo la funzionalità di inserimento delle informazioni geografiche nei topics, poi la pagina /map con la mappa interattiva e infine i filtri per categorie e tags.
  - ti chiedo la cortesia di scrivere il codice in maniera chiara e commentata, in modo che sia facilmente comprensibile e modificabile in futuro
  - una volta che verrà confermata una funzionalità, cerca di non modificare ulteriormente il codice già scritto, a meno che non sia strettamente necessario per l'implementazione di nuove funzionalità