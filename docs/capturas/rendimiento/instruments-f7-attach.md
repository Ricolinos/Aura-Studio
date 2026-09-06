# Trazas de Instruments (F7, ST-187) -- por `--attach`, 2026-09-06

Dos trazas de CPU/Tiempo (`xcrun xctrace record --attach <pid> --template
'Time Profiler'`, 10 s cada una), lanzando el ejecutable directo por
shell (nunca `open`/LaunchServices -- ver la corrección de ST-187 en
`DECISIONS.md` sobre el colgado en `_dyld_start`) y adjuntando después.
Ninguna tocó la biblioteca real del dueño.

Los `.trace` en sí **no se commitean** (bundles de ~13 MB cada uno, y
el `.trace` incluye en su tabla de contenidos el entorno completo del
proceso que lo generó -- variables de esta sesión de Claude Code que no
deben viajar al repo). Quedan en el scratch de la sesión; se ofrecen al
dueño aparte si los quiere ver en Instruments.app.

## Después (HEAD)

- Build: el ya compilado en el árbol compartido (`main`, con los fixes
  de ST-193 de "experto en código opus" encima -- no exactamente
  `origin/main` a este commit, pero sí F1-F7 completas).
- Biblioteca: fixture sintético de 200 álbumes, JPEG real por carátula
  (`AURA_UITEST_LIBRARY` -- el seam de ST-188), vía
  `gen_instruments_fixture.swift` (script de una sola vez, no vive en
  el repo).
- PID 85482, huella ~74-102 MB durante la captura.

## Antes (5b81c3a)

- Build: mismo commit que la línea base de §A, compilado aparte con
  `-derivedDataPath` propio (no comparte el árbol ni el candado
  compartido).
- **Sin biblioteca real de prueba**: `UITestEnvironment`/
  `AURA_UITEST_LIBRARY` no existían todavía en este commit (los trajo
  ST-188, de esta misma ronda) -- lanzar con esa variable no hace nada
  en este build. Para no arriesgar leer la biblioteca real del dueño
  (`UserDefaults` de `com.ricolinos.aurastudio` se comparte por bundle
  ID entre cualquier build, sin importar el `DerivedData`), se lanzó
  con `$HOME` apuntando a un directorio vacío de scratch -- arranque en
  frío, sin biblioteca configurada, nunca el estado real.
- PID 88533, huella ~125 MB al arrancar.

**Se descartó mejorar la traza "antes" para que cargara la misma
biblioteca sintética que "después".** El intento (`defaults write` con
un `$HOME` alterno, para que la preferencia cayera en un dominio de
scratch) causó un incidente real -- ver "Incidente: preferencia real
sobrescrita" en `DECISIONS.md` (ST-187). El build 5b81c3a no tiene
ningún seam de prueba (`UITestEnvironment` es de esta misma ronda), así
que no hay forma segura de darle una biblioteca sin tocar
`UserDefaults` del dominio real (`com.ricolinos.aurastudio`, compartido
con la app 0.2.3 instalada del dueño sin importar el `DerivedData` o el
`$HOME` del proceso que lanza el build). El "antes" se queda como
arranque en frío sin biblioteca, con esa limitación anotada arriba.

## Lectura

Las dos trazas capturan arranque/inicialización, no un recorrido
guionizado igual en ambas (la de "antes" no tiene biblioteca cargada,
por la limitación de arriba) -- sirven para comparar el costo base del
proceso (framework, `NSApplication`, primera ventana), no una sesión
completa idéntica en los dos lados. La tabla final de §A (`DECISIONS.md`,
ST-187) ya cubre la comparación real con líneas base de tiempo (no
Instruments) para cada operación medida con pruebas automatizadas.
