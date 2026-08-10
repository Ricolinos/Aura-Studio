# Guía de instalación — Aura para iPod Classic 6G

Esta guía es para instalar Aura en tu iPod Classic 6G (modelo MB562LL, 120GB, 2008) usando **Aura Studio**. Todo el proceso de flasheo (pausar servicios que interfieren, instalar el bootloader, preparar el disco, copiar el firmware) pasa **dentro de la app** — nunca necesitás abrir Terminal ni escribir ningún comando para instalar o restaurar tu iPod. La única excepción es un paso único, aparte, para obtener la app en sí (sección 2) — Aura Studio todavía no tiene una versión descargable empaquetada.

> ⚠️ Instalar un firmware alternativo modifica el arranque de tu iPod. Aura instala un **dual-boot**: podés volver al firmware original de Apple en cualquier momento (ver [guía de flasheo y restauración](guia-flasheo-restauracion.md)), pero como con cualquier modificación de bajo nivel, hacelo con margen y sin apuro.

## 1. Requisitos

- Un Mac con Apple Silicon (M1 o más nuevo) y Xcode instalado (con todos sus componentes — abrilo una vez desde Finder si nunca lo usaste en esa máquina, así macOS termina de instalar lo que falte).
- Tu iPod Classic 6G, con el firmware original de Apple instalado y funcionando (versión 1.1.2, 2.0.1, 2.0.4 o 2.0.5 según el modelo — es lo normal si nunca lo tocaste).
- Tu iPod formateado en **FAT32** (si nunca lo usaste con una Mac vieja/Windows, probablemente ya lo esté — Aura Studio te avisa si no, y lo ofrece reformatear ella misma si hace falta).
- Cable USB.
- Tu contraseña de administrador de macOS a mano (algunos pasos del instalador la piden con el diálogo nativo del sistema — ver sección 3).

## 2. Obtener Aura Studio

Por ahora Aura Studio se compila desde el código fuente (no hay todavía una versión descargable empaquetada) — este es el único paso de todo el proceso que usa Terminal, y es aparte de instalar/restaurar tu iPod:

```bash
cd Aura-Proyect/studio/AuraStudio
xcodegen generate
open AuraStudio.xcodeproj
```

En Xcode: `Product` → `Run` (▶️), o `⌘R`. De acá en más, todo pasa dentro de la app.

## 3. Permisos de macOS

Aura Studio te explica cada permiso antes de pedírtelo, en su propia pantalla, con lenguaje simple — nunca vas a ver un diálogo de macOS sin que la app te haya dicho antes qué es y por qué hace falta. Dos tipos distintos:

- **Acceso a volúmenes removibles / disco completo**: para detectar el iPod y desmontarlo en el momento justo. macOS lo pide una vez, la primera vez que la app accede a un disco removible.
- **Contraseña de administrador**: en pasos puntuales (pausar temporalmente dos servicios de macOS que a veces interfieren con la detección del iPod, o preparar el disco antes de instalar). Cada vez que Aura Studio vaya a pedirte esto, primero te muestra una pantalla propia explicando exactamente qué va a hacer — recién después aparece el diálogo nativo de macOS.

## 4. Instalar Aura

1. Abrí Aura Studio → pestaña **Instalador** → **Instalar Aura**.
2. Conectá tu iPod por USB. Si iTunes/Music se abre solo, podés cerrarlo.
3. Aura Studio lo detecta automáticamente y pasa al siguiente paso solo (no hace falta que confirmes nada a mano).
4. **Entrá a modo DFU**: mantené presionados **SELECT + MENU** al mismo tiempo durante unos 12 segundos, hasta después de que la pantalla se ponga negra, y soltalos. La app te muestra estos pasos en pantalla y detecta el modo DFU automáticamente apenas ocurre.
5. Aura Studio instala el bootloader, verificando la integridad de cada archivo antes de escribirlo (checksums SHA-256).
6. **Reconectá el iPod en modo Bootloader USB**: desconectá el cable, y con el iPod apagado, mantené **SELECT + RIGHT** mientras lo volvés a conectar. La app lo detecta sola.
7. Si el disco necesita prepararse (poco común — solo si nunca tuvo Rockbox/Aura antes), Aura Studio te explica el paso y te pide tu contraseña de administrador antes de formatearlo.
8. Aura Studio copia el firmware al iPod y verifica que haya quedado bien.
9. Cuando termina, desconectá el cable y tu iPod arranca solo con Aura.

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
