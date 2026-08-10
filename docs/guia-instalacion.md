# Guía de instalación — Aura para iPod Classic 6G

Esta guía es para instalar Aura en tu iPod Classic 6G (modelo MB562LL, 120GB, 2008) usando **Aura Studio**, sin tocar la terminal.

> ⚠️ Instalar un firmware alternativo modifica el arranque de tu iPod. Aura instala un **dual-boot**: podés volver al firmware original de Apple en cualquier momento (ver [guía de flasheo y restauración](guia-flasheo-restauracion.md)), pero como con cualquier modificación de bajo nivel, hacelo con margen y sin apuro.

## 1. Requisitos

- Un Mac con Apple Silicon (M1 o más nuevo) y Xcode instalado (con todos sus componentes — abrilo una vez desde Finder si nunca lo usaste en esa máquina, así macOS termina de instalar lo que falte).
- Tu iPod Classic 6G, con el firmware original de Apple instalado y funcionando (versión 1.1.2, 2.0.1, 2.0.4 o 2.0.5 según el modelo — es lo normal si nunca lo tocaste).
- Tu iPod formateado en **FAT32** (si nunca lo usaste con una Mac vieja/Windows, probablemente ya lo esté — Aura Studio te avisa si no).
- Cable USB.

## 2. Compilar Aura Studio

Por ahora Aura Studio se compila desde el código fuente (no hay todavía una versión descargable empaquetada). Abrí Terminal:

```bash
cd Aura-Proyect/studio/AuraStudio
xcodegen generate
open AuraStudio.xcodeproj
```

En Xcode: `Product` → `Run` (▶️), o `⌘R`.

## 3. Permisos de macOS

La primera vez que Aura Studio intenta ver tu iPod, macOS te va a pedir permiso — la propia app te explica por qué en la pantalla de **Permisos** del asistente:

- **Acceso a volúmenes removibles**: para detectar el iPod y poder desmontarlo en el momento justo (si no, Finder lo deja montado y el instalador no puede escribir en él).
- **Acceso total al disco** (opcional): solo hace falta si el permiso anterior no alcanza en tu versión de macOS. Aura Studio tiene un botón directo a Ajustes del Sistema para activarlo.

## 4. Instalar Aura

1. Abrí Aura Studio → pestaña **Instalador** → **Instalar Aura**.
2. Conectá tu iPod por USB. Si iTunes/Music se abre solo, podés cerrarlo.
3. Aura Studio lo detecta automáticamente y pasa al siguiente paso solo (no hace falta que confirmes nada a mano).
4. **Entrá a modo DFU**: mantené presionados **SELECT + MENU** al mismo tiempo durante unos 12 segundos, hasta después de que la pantalla se ponga negra, y soltalos. La app te muestra estos pasos en pantalla y detecta el modo DFU automáticamente apenas ocurre.
5. Aura Studio instala el bootloader y el firmware, verificando la integridad de cada archivo antes de escribirlo (checksums SHA-256).
6. Cuando termina, tu iPod reinicia solo con Aura.

## 5. Sincronizar tu música, fotos y videos

Pestaña **Biblioteca**: arrastrá tus archivos (música, fotos, videos) a la zona de "soltá acá". Aura Studio:

- Completa automáticamente título/artista/álbum/tapa/letra sincronizada de tu música (buscando en MusicBrainz, Cover Art Archive y LRCLIB — no hace falta ninguna cuenta ni API key para esto).
- Convierte tus videos al formato que el iPod puede reproducir.
- Redimensiona tus fotos al tamaño óptimo de la pantalla.

Cuando esté todo listo (columna de estado con un ✓ verde), escribí la ruta del volumen montado de tu iPod (por ejemplo `/Volumes/IPOD_AURA`) y apretá **Sincronizar al iPod**. Solo se copia lo nuevo o lo que cambió — sincronizaciones siguientes son mucho más rápidas.

## 6. Usar Aura

El iPod arranca directo en Aura — no vas a ver ningún menú, logo ni carpeta de Rockbox. Navegación con el clickwheel:

- **Música / Videos / Fotos / Ahora suena / Ajustes** — el menú raíz.
- Música se navega por Artistas / Álbumes / Canciones / Playlists / Géneros (base de datos indexada, no carpetas).
- En Ahora Suena, el botón central abre la letra sincronizada si el tema la tiene.
- En Ajustes podés elegir tema (claro/oscuro), modo gráfico (Ultra minimalista / Minimalista / Completo), preset de EQ, brillo e idioma (ES/EN).

## Referencia visual

Todas las pantallas de Aura, en los dos temas y los tres modos gráficos, están capturadas en [`docs/screenshots/matrix/`](screenshots/matrix/) — útil si algo en tu pantalla se ve distinto a lo esperado.
