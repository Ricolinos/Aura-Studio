# Contrato del formato de tema (v1)

**Versión 1 — 2026-08-17.** Copia idéntica en `Aura-Firmware` (fuente canónica) y Aura Studio, mismo criterio que `CONTRATO-firmware-studio.md`. Cualquier cambio a este contrato es también un cambio a `theme_format` (§F) y se hace en ambos repos en la misma unidad de trabajo.

Este documento define el **formato de paquete de tema** — la interfaz entre el firmware (que lo carga y lo dibuja) y Aura Studio (que lo construye e instala). Diseño y justificación en `docs/aura-design-system/sistema/05-temas.md` (repo del firmware); esto es solo el contrato exacto: rutas, claves, tamaños.

**Principio rector**: Aura Studio es un CONSTRUCTOR de temas, no un DISTRIBUIDOR. Ningún tema con assets de licencia restringida (SF Pro, SF Symbols) se commitea, se sube a un release ni se comparte — se construye localmente desde lo que ya está en la Mac del usuario.

---

## A — Ubicación en el disco del iPod

```
/.rockbox/aura/themes/<id>/
  theme.cfg                          obligatorio
  fonts/<rol>.fnt                    14 obligatorios
  icons/masks/<icon_key>-<px>.bmp    801 obligatorios (89 × 9)
  icons/light/<icon_key>-<px>[-suf].bmp   opcional (BMP horneado, fallback)
  icons/dark/<icon_key>-<px>[-suf].bmp    opcional
  backgrounds/<preset>.bmp           opcional
  tile-icons/aura_badge-{light,dark}.bmp  opcional
```

`<id>`: `[a-z0-9-]{1,32}`, nunca `default` (reservado para el tema compilado, que **no** vive bajo `themes/` — sigue en las rutas legadas `/.rockbox/fonts/` y `/.rockbox/icons/aura/`). Aura Studio y el firmware validan `<id>` con el mismo alfabeto antes de tocar cualquier ruta que lo contenga.

## B — `theme.cfg`

Formato `clave: valor`, una por línea, mismo parser que `aura.cfg` (`settings_parseline()` + `read_line()` de Rockbox — sin comillas, sin escapes). Líneas ≤ 127 caracteres. Todo lo ausente **hereda del tema por defecto compilado** — nunca queda indefinido.

```
theme_format: 1
theme_id: apple-personal
theme_name: Apple (uso personal)
theme_author: (opcional, libre)
theme_license: personal | open | (texto libre)
theme_redistributable: yes | no
requires_firmware_min: 0.9.0        # informativa; el firmware no la lee

palette_light_shell_bg: #FFFFFF
palette_light_text_primary: #000000
palette_light_text_secondary: #6E6E73
palette_light_text_tertiary: #3C3C43
palette_light_shell_rail: #C6C6C8
palette_light_progress_fill: #3C3C43
palette_light_progress_track: #E5E5EA
palette_light_selection_fill: #E5E5EA
palette_dark_shell_bg: #1C1C1E
palette_dark_text_primary: #FFFFFF
palette_dark_text_secondary: #98989D
palette_dark_text_tertiary: #C7C7CC
palette_dark_shell_rail: #3A3A3C
palette_dark_progress_fill: #E5E5EA
palette_dark_progress_track: #48484A
palette_dark_selection_fill: #2C2C2E

category_settings_gray: #8E8E93
category_video: #1E3A5F
category_photos: #FF9500
category_extras_yellow: #FFCC00

accent_default: #FF2D55                              # ver §H -- no cableado en v1
accent_presets: #FF2D55,#FF3B30,#FF9500,#34C759,#007AFF,#AF52DE   # ver §H
```

Valores hex con o sin `#` inicial, ambos válidos. `accent`/`white_constant` **no** son claves de este contrato — el acento es un ajuste del usuario, nunca del tema (ver §H); el blanco constante del Selector es estructura, no cambia por tema.

## C — Roles de fuente (14, obligatorios)

Nombre de archivo = rol, extensión `.fnt` (formato nativo de Rockbox, el que produce `convttf`). Tamaño en px fijo por rol — el tema sustituye la **cara**, nunca el tamaño (son métricas del sistema de diseño):

| Rol | px | Rol | px |
|---|---|---|---|
| `title` | 20 | `ds_bold_10` | 10 |
| `body` | 13 | `ds_reg_12` | 12 |
| `caption` | 13 | `ds_bold_12` | 12 |
| `header` | 13 | `ds_bold_14` | 14 |
| `micro` | 7 | `ds_bold_18` | 18 |
| `ds_reg_8` | 8 | `ds_medium_16` | 16 |
| `ds_semibold_15` | 15 | `ds_reg_10` | 10 |

## D — Íconos

- **`icon_key`**: 89 nombres lógicos estables (lista completa en el asset `theme-format-v1.json` del Release, campo `icon_keys` — Studio la lee de ahí, nunca la mantiene a mano).
- **Tamaños**: 9 px — `12, 16, 20, 24, 28, 36, 48, 60, 64`.
- **Máscaras** (`icons/masks/<icon_key>-<px>.bmp`, **801 obligatorias** = 89 × 9): BMP 24-bit, R=G=B=cobertura del glifo (0–255), sin transparencia. Es el camino **primario** de dibujo — el firmware las compone en tiempo real contra el framebuffer con la tinta del token vivo (paleta + variante). Una máscara *es* la cobertura antialiasada; no hay paso de composición ni clave de transparencia que pueda introducir halos o dientes de sierra.
- **Horneados** (`icons/{light,dark}/<icon_key>-<px>[-suf].bmp`, **opcionales**): BMP con clave magenta `#FF00FF` para transparencia, uno por variante (`-on`, `-tertiary`, `-rail`, `-selector`, y sin sufijo). Solo se usan como **fallback** si falta la máscara correspondiente — un tema puede omitirlos por completo.
- **Casos especiales de lienzo** (heredados del pipeline, no específicos del formato de tema): `battery_icon` usa un lienzo no cuadrado (21×12 por unidad de tamaño); `dynamic_speaker` cubre 5 estados con un punto fijo distinto al resto.

## E — Fondos y tiles (opcionales)

- `backgrounds/<preset>.bmp`: 160×240, BMP 24-bit, sin transparencia. `<preset>` = uno de los nombres en `theme-format-v1.json` → `background_presets` (hoy: `pink`).
- `tile-icons/aura_badge-{light,dark}.bmp`: 90×90, BMP con clave magenta donde el alfa original es 0.

## F — Versionado del formato (`theme_format`)

El firmware declara el máximo que entiende (`AURA_STYLE_FORMAT_SUPPORTED`, hoy `1`) y lo publica en `aura.cfg` como `theme_format_supported` (ver `CONTRATO-firmware-studio.md` §D) para que Studio lo lea del dispositivo montado sin adivinar la versión del firmware.

| `theme_format` del tema vs. soportado por el firmware | Resultado |
|---|---|
| Igual | Carga normalmente |
| Menor | Carga lo que entienda, hereda el resto del default (sin caso real todavía — v1 es el primer formato) |
| Mayor | **No carga** — fallback al tema activo anterior o al default; fila inerte en el submenú "Estilo" |

Añadir un rol de fuente, un `icon_key` nuevo, o un tamaño nuevo = subir `theme_format`.

## G — Validación (ambos lados, ninguno confía en el otro)

**Aura Studio**, antes de instalar: manifiesto completo y parseable; los 14 `fonts/<rol>.fnt` presentes con cabecera de `.fnt` válida; las 801 máscaras presentes con las dimensiones `<px>×<px>` correctas; `theme_format` ≤ el `theme_format_supported` que reportó el firmware del iPod conectado. Rechaza el paquete antes de copiar si algo falta.

**El firmware**, al cargar: `theme.cfg` existe y parsea; `theme_format` presente y ≤ el soportado; las 14 fuentes existen (chequeo de archivo) antes de intentar activarlas de verdad con `font_load()` — si **cualquiera** falla al cargar de verdad (archivo corrupto pasado el chequeo de existencia), revierte al estilo que estaba activo antes, o al default si ese también falla. Íconos/fondos/tiles se resuelven por archivo individual: si falta uno, cae al del default sin invalidar el resto del tema.

## H — Acento del usuario (`accent_default`/`accent_presets`)

El acento (`aura_settings.accent_rgb24`) es y sigue siendo **100% un ajuste del usuario**, independiente del tema activo. El formato acepta que un tema declare `accent_default`/`accent_presets` (para que Aura Studio pueda, por ejemplo, sugerir una paleta de acentos a juego con el tema al construirlo), pero **el firmware v1 no los lee ni los aplica en ningún lado** — el selector de acento (Ajustes → Color de acento) sigue usando siempre los 6 presets compilados. Esto es una reserva deliberada del formato para una versión futura, no una implementación a medias: documentado también en `docs/aura-design-system/sistema/05-temas.md`.

## I — Licencia (`theme_license`/`theme_redistributable`)

Declaraciones del constructor, **el firmware las ignora por completo** — son para Aura Studio, que las respeta al ofrecer exportar/compartir un tema (`theme_redistributable: no` deshabilita esa opción en la UI, con explicación, nunca oculta). El tema por defecto (Inter OFL + Lucide ISC + Phosphor MIT) es `open`/`yes`; cualquier tema construido desde fuentes/símbolos de licencia restringida (SF Pro/SF Compact, SF Symbols, o lo que el usuario marque como tal) es `personal`/`no`.

## J — Asset `theme-format-v1.json` (Release de `Aura-Firmware`)

Generado por `design-system/generate.py` (`generate_theme_format_json()`), copiado a `firmware/dist/` por `package_dist.sh`. Es la fuente de verdad que Aura Studio consume para construir/validar sin leer `tokens.json` ni el árbol del firmware — contiene: los 14 `font_roles` (rol + px), los 9 `icon_sizes`, los 89 `icon_keys`, las 5 `icon_variants`, los `palette_roles` (los 8 de §B), los 4 `category_keys`, los `background_presets`, `tile_icons`, y los valores `default_palette`/`default_category`/`default_accent` del tema compilado (para poder editar partiendo del default en vez de una paleta vacía).

## K — Asset `aura-theme-default.zip` (Release de `Aura-Firmware`)

El tema por defecto ("Aura": Inter + Lucide/Phosphor, licencia libre) reempaquetado en este formato, con `theme_id: aura` (no `default` — ese id sigue reservado al compilado). Generado por `package_dist.sh`. Sirve como (a) ejemplo canónico y completo del formato, y (b) un tema libre real para instalar/probar sin tocar ningún material de licencia restringida.
