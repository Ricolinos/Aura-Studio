# Contrato del nombre del dispositivo (v1)

**Versión 1 — 2026-08-17.** Copia idéntica en `Aura-Firmware` (fuente canónica) y Aura Studio, mismo criterio que `CONTRATO-formato-tema.md`. Cualquier cambio a este contrato sube `contract_version` (§D) y se hace en ambos repos en la misma unidad de trabajo.

Este documento define `.rockbox/aura/device.cfg` — dónde vive el nombre editable de un iPod con Aura (PLAN-general-sync.md §1.5/§9), para que sobreviva si el dispositivo se conecta a otra Mac con Aura Studio instalado.

**Por qué no `aura.cfg`**: el firmware regenera `aura.cfg` **entero** en cada `aura_settings_save()` (`creat()` + una línea `fdprintf` por cada clave que el firmware conoce) — cualquier clave que Studio agregara ahí sin que el firmware la conozca se perdería en el primer guardado de un ajuste cualquiera. `device.cfg` es un archivo propio, exclusivo de este contrato, que el firmware nunca reescribe.

---

## A — Ubicación y formato

```
/.rockbox/aura/device.cfg
```

UTF-8, sin BOM, saltos de línea `\n`. Formato `clave: valor`, una por línea — mismo parser que `aura.cfg`/`sync_summary.cfg` (`settings_parseline()` + `read_line()` de Rockbox, ver `CONTRATO-firmware-studio.md` §D). **Líneas ≤ 63 bytes** (el buffer real de `read_line()` en todos los lectores `.cfg` del firmware) — la clave más larga (`device_name_updated_at: `, 24 bytes) más el límite de `device_name` (§C) deja margen de sobra.

```
contract_version: 1
device_id: 6F2C1B4A-3D5E-4F1A-9C2B-1A2B3C4D5E6F
device_name: iPod de Ricardo
device_name_updated_at: 2026-08-17T20:14:00Z
```

Todo lo ausente no tiene default (a diferencia de `theme.cfg`): sin `device_name`, Aura Studio no muestra ningún nombre editado — usa la etiqueta de volumen, igual que antes de este contrato.

## B — Claves

| Clave | Formato | Escribe | Notas |
|---|---|---|---|
| `contract_version` | entero | Studio | `1` en esta versión. Ausente = tratar como `1` (no había versión antes de este contrato) |
| `device_id` | UUID v4 | Studio | Generado una sola vez, la primera vez que Studio ve este dispositivo con Aura instalada. Estable mientras exista el archivo — no cambia al renombrar |
| `device_name` | texto | Studio (default automático, o el usuario al editarlo) | Ver §C para límites y validación |
| `device_name_updated_at` | ISO 8601 (UTC) | Studio | Informativa — ningún lado la usa para decidir nada, solo diagnóstico |

Claves desconocidas se ignoran, tanto al leer como al reescribir (Studio reescribe el archivo entero con las 4 claves de arriba en cada guardado — a diferencia de `aura.cfg`, esto no es un problema porque **Studio es el único que escribe este archivo**).

## C — `device_name`: validación

- **Longitud máxima: 32 caracteres, y además ≤ 48 bytes UTF-8** (un acento o "ñ" pesa 2 bytes) — deriva de dos cosas: el precedente ya existente en el firmware para nombres cortos (`style_id[33]` de temas, D-289; `playername.txt` de IAP, 31 bytes útiles) y el techo real de 63 bytes de línea completa (`read_line`, §A).
- Se recortan espacios en los extremos; los espacios internos se colapsan (nunca más de uno seguido).
- Se descartan caracteres de control y saltos de línea (categoría Unicode `Cc`) — un `device_name` es siempre una sola línea.
- Unicode permitido **solo dentro del BMP** (U+0000–U+FFFF): es lo que cubren las `.fnt` de Aura (AUDITORIA-01 A-02). Cualquier carácter fuera del BMP —en la práctica, emoji— se descarta al guardar; el iPod no tiene glifo para eso y mostraría cajas vacías.
- Nombre vacío tras aplicar todo lo anterior → no se guarda, se conserva el nombre previo (o, si nunca hubo uno, la etiqueta de volumen).

## D — Quién lee, quién escribe

| | Escribe | Lee |
|---|---|---|
| Aura Studio | Sí — genera el default la primera vez que ve el dispositivo, y en cada edición del usuario | Sí — para mostrar el nombre en la barra lateral y en General |
| Firmware | **Nunca** | Opcional, sin fecha — ver §E |

Studio es la única fuente de verdad de este archivo, igual que `sync_summary.cfg`. Un `device.cfg` ausente no es un error: Studio lo crea la próxima vez que vea el dispositivo.

## E — Consumo esperado del firmware (no implementado, sin bloquear nada)

Hoy la pantalla "Acerca de" muestra el literal fijo `"Mi iPod"` (`AURA_STR_ABOUT_MY_IPOD`) en el slot superior del panel derecho (Bold 18pt, 152 px útiles, con marquee si no cabe — nunca elipsis, ver `docs/aura-design-system/componentes/about.md`). Si el firmware algún día lee `device_name` de este archivo, ese es el slot natural: sustituye el literal, con el mismo marquee que ya existe para textos largos. Esto es **documentación de intención**, no un compromiso — Aura Studio funciona completo sin que el firmware lea nunca este archivo.

## F — Versionado

Cualquier cambio de clave o de semántica sube `contract_version` y se registra en el diario de ambos repos (`D-NNN` en el firmware, `ST-NNN` en Studio), citándose cruzado — mismo criterio que `CONTRATO-formato-tema.md` §F y `CONTRATO-firmware-studio.md` §E.
