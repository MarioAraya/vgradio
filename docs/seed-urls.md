# Seed URLs — catálogo inicial

Origen: **khinsider** (`downloads.khinsider.com`). Álbumes para poblar/probar el scraper.

## Álbumes
- https://downloads.khinsider.com/game-soundtracks/album/kirby-planet-robobot-gamerip
- https://downloads.khinsider.com/game-soundtracks/album/kirby-and-the-rainbow-curse
- https://downloads.khinsider.com/game-soundtracks/album/captain-toad-treasure-tracker-original-sound-version
- https://downloads.khinsider.com/game-soundtracks/album/persona-5

## Nota de scraping (importante)
El `.mp3` directo **no** está en la página de álbum. Cada track linkea a una **página de
canción**; el botón *play* del sitio ejecuta JS que hace fetch de esa página y extrae el
URL `.mp3` directo, que setea como `src` del tag `<audio>`.

→ Scraping en **dos pasos**:
1. **Página de álbum** → metadata + carátulas + lista de tracks (nombre, duración, tamaño,
   y **link a la página de canción**).
2. **Página de canción** → URL `.mp3` directo (resolución diferida / on-demand).
