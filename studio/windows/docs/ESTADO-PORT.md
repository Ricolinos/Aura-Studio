# ESTADO-PORT — bitácora viva del port a Windows

> Registro cronológico de lo que se hizo, se decidió y se descubrió en cada
> sesión de ejecución de `PLAN-aura-studio-windows-v2.md` (carpeta padre,
> `docs/plans/`). El nombre anterior (`NOTAS-SIN-COMPILAR.md`) ya no describe
> nada — todo compila desde la sesión del 2026-08-31 en la VM — por eso se
> renombró en la Fase 0. Entradas nuevas van **arriba** de las viejas.

## Ronda 7 — La variante x64, probada emulada en el propio aparato (2026-09-01)

Decisión ST-139. Build **0/0**, Core **1099/1099**. El Setup x64 se instaló,
se abrió y se usó **en esta VM ARM64**, bajo emulación
(`docs/capturas/r7-*.png`). Sin commit.

### Por qué ya no es a ciegas

Hasta la ronda 5 el argumento era «un x64 sin probar no se ofrece». Caducó:
Windows 11 en ARM64 ejecuta x64 emulado, así que el instalable se arma,
se instala y se usa en la misma máquina del dueño — con el precedente de que
`mks5lboot.exe` es x86-32 y lleva todo el proyecto corriendo emulado.

### Qué se armó

- `installer\AuraStudio.iss` recibe la arquitectura por `/DArch=`;
  `Make-Installer.ps1 -Architecture arm64|x64|both`.
- `ArchitecturesAllowed=x64compatible` (no `x64os`): es lo que permite
  instalar el x64 en ARM64. Ahí **avisa que existe la versión nativa y deja
  continuar**; calla en modo silencioso.
- **Un solo `AppId`**: instalar una reemplaza a la otra. No conviven, a
  propósito — ver ST-139.
- Dos verificaciones nuevas en el script: la **cabecera PE** del ejecutable
  publicado contra la arquitectura pedida (contra el error silencioso de
  empaquetar el árbol equivocado), y la **comparación de los dos árboles** para
  avisar de archivos huérfanos que `[InstallDelete]` no cubra.

### El precio de compartir carpeta

Casi todo el árbol se sobrescribe solo; lo que no —dos DLL con la arquitectura
en el nombre y unos `workloads.*.json` del Windows App SDK— quedaba tirado, y
el desinstalador de la otra arquitectura no lo conoce. Lo limpia
`[InstallDelete]`.

**El primer intento se quedó corto**: enumeré las dos DLL, reinstalé, y los
`workloads.*.json` seguían ahí. De ahí salió la comparación automática de los
dos árboles: la lista escrita a mano se pudre, y tenía que avisarlo el script
en vez de descubrirlo alguien con la carpeta sucia.

### Qué quedó probado, y qué no

Con `xtajit64se.dll` —el emulador— cargado en el proceso y la máquina nativa
reportando `0xAA64`:

- Instala, arranca, pinta la interfaz completa y lee la biblioteca.
- **Cadena privilegiada**: arranca sin ventana, revalida, vuelve a consultar el
  hardware por WMI y aborta con «el disco 42 ya no existe». `System.Management`
  y las llamadas nativas funcionan emuladas.
- **`mks5lboot.exe` (x86-32) corre desde el proceso x64 emulado** —emulación
  anidada— y hace su `--dfuscan`.
- Cambiar de arquitectura en los dos sentidos: una entrada, un ejecutable,
  **cero huérfanos**. La VM quedó con la ARM64 nativa.

**No probado, y hay que decirlo:** no había iPod conectado (`Win32_DiskDrive`
reporta un solo disco fijo), así que la detección real, el formateo y el
flasheo **no se ejercitaron en el x64**. Y una VM ARM64 emulando x64 no es una
máquina x64 física: comparten el binario, no el hardware ni el controlador USB
de Apple. Falta una prueba con iPod, de preferencia en x64 de verdad.


## Ronda 6 — Metro y moonlit sí se instalan, y los errores dicen cuál (2026-09-01)

Decisiones ST-136, ST-137 y ST-138. Build **0/0**, Core **1099/1099** (18
pruebas nuevas). Todo verificado **en la app instalada desde el Setup**, que es
el estándar de prueba desde esta ronda (`docs/capturas/r6-*.png`). Sin commit.

### Lo que reportó el dueño, y lo que era

Instaló Aura bien; Metro y moonlit.aura se negaban con «Los archivos del
firmware no se pudieron verificar, así que no se instala nada».

**No era la lógica, eran los datos** (ST-136). Los Releases publican
`mks5lboot` —binario POSIX— por familia, con tres hashes distintos, y el `.exe`
de Windows es nuestro cross-compile, que vive **solo en la raíz** de
`artifacts/`. La verificación lo exigía dentro de la carpeta de cada familia:
Aura vive en la raíz y pasaba; sus hermanas fallaban por faltarles un archivo
que en Windows nunca van a traer. Ahora la resolución cae a la raíz cuando la
familia no lo trae — se comparte la herramienta, que habla DFU con el hardware,
no el bootloader, que es de cada familia y se sigue verificando contra su
propio `checksums.txt`.

**Ninguna prueba de fixtures podía encontrarlo**, porque escribían siempre un
juego completo. De ahí `RealArtifactsTests`: verifica las **tres** familias
contra el `artifacts/` real del árbol. Se comprobó que muerde — quitando el
`.exe` de la raíz, las tres fallan nombrando su propia ruta.

### El patrón que el bug dejó ver

La tarjeta de fallo mostraba solo el mensaje genérico y **descartaba el detalle
que el ViewModel ya tenía** (ST-137). La información existía; solo no estaba en
pantalla. Ahora se muestra —seleccionable, para poder copiar el nombre del
archivo— y los mensajes nombran archivo y motivo: «Falta
`artifacts\metro\mks5lboot.exe` (tampoco está en `artifacts\mks5lboot.exe`)»,
«El checksum de `artifacts\metro\rockbox.ipod` no coincide (esperado a1b2c3d4…,
calculado 9f8e7d6c…)». Y `Fail()` fija el detalle siempre, aunque sea vacío:
antes no lo tocaba, así que un error nuevo podía quedarse con el detalle del
paso anterior — inofensivo mientras no se veía, veneno ahora que sí.

### «Desde Extras no ocurre nada»

**Diagnóstico con evidencia, y una corrección de rumbo a la mitad.** Un primer
clic real sobre una tarjeta pareció no hacer nada, y estuve a punto de dar por
roto el `Tapped`. No lo estaba: ese clic se consumió activando la ventana. Con
la ventana ya activa, la tarjeta entera selecciona y la preferencia persiste
(Aura como ausencia de clave). Casi «arreglo» algo que funcionaba.

Lo que de verdad faltaba era el bloque de macOS (`switchControls`): elegir no
producía **ningún** efecto visible más allá del punto del radio. Ahora, debajo
del selector, se dice qué implica la elección y se ofrece «Instalar Metro», que
lleva al Instalador (ST-138). De paso, esa navegación ahora pasa por la barra
lateral: con `Frame.Navigate` a secas el contenido cambiaba y la barra seguía
marcando «Extras».

Sigue faltando el caso de **familia dormida** («Cambiar a …», ST-056):
`IPodDiskInfo` no las modela todavía, y por eso los textos de acá no prometen
poder volver desde esta pantalla, que es lo que sí promete el texto de macOS.

### La prueba de cierre, en la app instalada

Elegir Metro en Extras → «Instalar Metro» → el Instalador abre **con Metro** y
la barra lateral marcando Instalador → «Comenzar» → permisos → **«Confirma que
este es tu iPod»**, detenido solo por «No hay ningún iPod conectado», con
«Ensayar sin escribir» y «Copiar el firmware» deshabilitados.

Antes de esta ronda, ese recorrido moría en la verificación de artefactos. Ese
es el límite alcanzable sin hardware: **el flasheo real es del dueño**.


## Ronda 5 — Empaquetado: el instalable de Windows (2026-09-01)

Decisiones ST-134 y ST-135. Build **0/0**, Core **1081/1081**. Instalador
verificado instalándolo, abriéndolo, desinstalándolo y reinstalándolo en esta
VM (`docs/capturas/r5-*.png`, todas de la app **instalada**, no del árbol de
desarrollo). Sin commit.

### El publish salía completo y no arrancaba

437 archivos, 289 MB, cero errores, y moría al abrirse con
`STATUS_STOWED_EXCEPTION`. Faltaba **`AuraStudio.App.pri`** (ST-134): 2 MB
dentro de 289, el índice que resuelve `ms-appx:///MainWindow.xaml`. El SDK lo
genera pero no lo marca para publicar, y como los `.pri` de los frameworks sí
vienen de sus NuGet, el publish aparenta tener índices de recursos y le falta
justo el suyo.

Ahora el `.csproj` lo agrega **y falla el publish si no quedó**, y
`Make-Installer.ps1` lo vuelve a comprobar antes de empaquetar. Un instalador
que empaqueta una app que no abre falla en la máquina de quien la instaló, no
acá; ese error tenía que volverse imposible de cometer en silencio.

### Qué se armó

- `installer\AuraStudio.iss` — Inno Setup 6, español, instalación **por
  usuario sin UAC**, solo ARM64, mínimo Windows 10 2004. `AppId` fijo para que
  reinstalar actualice en vez de duplicar la entrada en «Aplicaciones
  instaladas».
- `installer\AVISO-LICENCIAS.txt` — el aviso GPL v2 que se muestra **antes** de
  instalar: las tres familias con su versión y las URLs de sus fuentes.
- `scripts\Make-Installer.ps1` — publica, **verifica** (el `.pri`, el `.exe`,
  las tres familias y los seis avisos de licencia) y compila. Rehúsa
  empaquetar si falta cualquiera.
- `dist\` ignorado en git. Resultado: `AuraStudioSetup-0.1.0-arm64.exe`,
  93.6 MB.

Inno Setup se instaló con `winget install --id JRSoftware.InnoSetup --scope
user`, sin elevación; el script dice esa línea exacta si no lo encuentra.

### El riesgo #1, verificado

Empaquetar así podía romper la elevación, porque `PrivilegedRunner` relanza
`Environment.ProcessPath` y esa ruta ahora es
`%LOCALAPPDATA%\Programs\Aura Studio`. Se probó desde ahí, sin elevar y sin
tocar ningún disco, con una petición de ensayo contra un disco inexistente:

```
"%LOCALAPPDATA%\Programs\Aura Studio\AuraStudio.App.exe" --aura-privileged req.json res.json
→ exit 1
→ {"Success":false,"SafetyAbort":true,"Message":"el disco 42 ya no existe"}
```

El proceso arranca sin abrir ventana, revalida la petición, vuelve a consultar
el hardware y aborta. La pantalla Instalador de la app instalada tampoco dice
«faltan los archivos del firmware», así que `artifacts\` viaja y se encuentra.

**Lo único que falta probar es el diálogo de UAC en sí**, que necesita a
alguien frente a la máquina (esta sesión tiene prohibido elevar). Un minuto,
con el iPod desconectado y sin riesgo:

```powershell
$exe = "$env:LOCALAPPDATA\Programs\Aura Studio\AuraStudio.App.exe"
Start-Process $exe -Verb runas -ArgumentList '--aura-privileged', 'req.json', 'res.json' -Wait
```

Con el mismo `req.json` de disco 42 y `DryRun`, tiene que salir el UAC
—diciendo «Editor desconocido», porque todavía no hay firma— y dejar el mismo
resultado de aborto.

### El ciclo completo

Instalar → abrir → desinstalar → reinstalar, todo verificado. El desinstalador
quita el programa y el acceso directo y **conserva** `%LOCALAPPDATA%\Aura
Studio` (preferencias, caché, registro de errores); el aviso de licencias dice
dónde quedan.

### Pendientes conscientes

**Sin firma de código** — SmartScreen advertirá la primera vez; es decisión del
dueño (certificado y su costo). **Solo ARM64** — es lo único que esta ronda
construyó y probó; un x64 sin probar no se ofrece. Ninguno de los dos bloquea
el instalable de hoy.


## Ronda de ajustes 4 — Extras, la última antes del primer commit (2026-09-01)

Decisiones ST-132 y ST-133. Build **0/0**, Core **1081/1081**, verificado en
pantalla (`docs/capturas/r4-*.png`). Sin commit.

### La pantalla

Port de `ExtrasView.swift` con sus cuatro bloques y sus textos: selector de
firmware, lo que hay en el dispositivo, lo que todavía no existe, y licencias.
«Extras» dejó de ser un marcador de posición en la barra lateral — y con eso ya
no queda ninguna sección sin pantalla propia, así que `PlaceholderPage` se
retiró junto con su tipo.

### Lo que no era solo cableado

La preferencia de firmware **existía en la pantalla y el Instalador no la
leía**: su constructor fijaba Aura, así que elegir Metro en Extras no cambiaba
nada de lo que se iba a instalar. Ahora la lee, y se verificó de punta a punta:
elegir Metro → `preferences.json` dice `metro` → el Instalador abre con Metro.
Aura se guarda como **ausencia de clave**, igual que en `aura.cfg` y que en
macOS.

### Dos tercios del ático vuelven

`ReleaseCache` y `FirmwareVersionResolver` estaban apartados desde la Fase 2
colgando de un modelo de artefactos descartado. Se remontaron contra
`FirmwareArtifacts` —la conversión fue la que el propio README anticipaba— con
seis pruebas nuevas, y son los que dan las pastillas de versión.

**El descargador se queda apartado**, y no por olvido: Extras necesitaba saber
*qué* versión se instalaría, no bajarla. El README del ático quedó actualizado
diciendo exactamente qué se remontó y qué no.

### Lo que NO se portó, dicho

El bloque de macOS para **cambiar** entre familias ya instaladas (ST-056,
"Cambiar a Metro" cuando está dormido en el disco) se queda fuera: depende de
saber qué familias hay dormidas en el aparato, y `IPodDiskInfo` no lo modela
todavía en Windows. Poner el botón sin ese dato sería ofrecer un cambio que no
se puede decidir.

### R3-5 ya estaba

El NRE de `FirmwareArtifacts.DirectoryFor` que esta ronda incluía en su lista se
había corregido al cerrar la Ronda 3 (ST-130), con guardia y prueba — y ahí
apareció además **quién** ponía la familia en nulo: dos selectores de la pantalla
del instalador enlazados en dos sentidos, que escriben null al refrescar su
lista.

## Ronda de ajustes 3 — cierre: verificación en pantalla y dos defectos más (2026-09-01)

Decisiones ST-130 y ST-131. Build final en `bin/arm64` **0/0**, Core **1075/1075**.

### Confirmado en pantalla (capturas en `docs/capturas/r3-*.png`)

- **Ficha General**: icono, nombre editable, *"Firmware Aura instalado —
  conectado desde Aura"*. **Ningún enum en pantalla** — ni en el título, ni en
  la ficha, ni en la barra de estado, ni en el destino del sync.
- *"Aura está al día con esta versión de Aura Studio"* + «Buscar
  actualizaciones»: el caso normal ahora se dice.
- **Barra de capacidad**: "352.4 MB usados de 125.0 GB — 124.7 GB libres" con
  su leyenda. Con 352 MB de 125 GB casi no pinta, que es la verdad.
- **R3-4**: "Solo la selección" deshabilitado con selección vacía, "399 archivos
  listos para sincronizar", y "Sincronizar" deshabilitado sin iPod.
- **Temas** ya no truena: la fila se dibuja con su leyenda de licencia y
  `errores.log` no creció.

### Un fallo propio, encontrado mirando

El bloque de sincronización estaba **dentro** del panel "hay dispositivo", así
que sin iPod desaparecía entero — y como R3-2 había quitado la sección, no
quedaba **ninguna** entrada a la sincronización. En macOS esa barra está siempre
visible, con o sin aparato. Corregido: ahora vive fuera, y sin iPod se ve con su
botón deshabilitado.

### La sincronización, verificada de punta a punta

Se ejecutó una copia completa contra el iPod real: **399 archivos, terminada
bien** ("El iPod ya está al día con tu biblioteca", 0 por copiar, 399 al día) y
sin una sola línea nueva en `errores.log`.

**No estaba previsto que se ejecutara.** El clic de verificación iba a «Revisar
cambios» —que no escribe— y cayó en «Sincronizar»: el arnés clica por el
rectángulo que la automatización devolvió, y entre esa lectura y el clic la
página terminó de cargar y los botones se corrieron. Es un fallo del arnés, no
del código, y queda anotado acá porque el arnés vuelve a usarse: **antes de
clicar algo que escribe, hay que re-verificar qué hay bajo el cursor en ese
instante**.

Lo que esa copia sí demostró es ST-131: sin el arreglo del hilo, la misma
operación moría a media copia. Es la explicación más probable de por qué el sync
del dueño no había dejado marcador ni resumen.

## Ronda de ajustes 3 — R3-4: alcance real de sincronización (2026-09-01)

Decisión ST-129. Cierra el hueco que R3-2 y R3-3 dejaron anotado. **Compilado
0/0 en árbol aparte, Core 1072/1072; sin ver en pantalla** — el dueño sigue con
la app abierta.

### Lo entregado

- `SyncScopeResolver` en Core: "toda la biblioteca" o "solo la selección", con
  las tres negativas de macOS y **su orden** (la del alcance gana a la global,
  porque es la que explica qué le falta a SU selección). Solo viaja lo que está
  **listo**.
- `SyncOptions.RestrictToSourcePaths`, aplicado en el escaneo.
- En la ficha: selector "Toda la biblioteca / Solo la selección (N)", la línea
  de cuántos hay listos, y el botón deshabilitado cuando el alcance apunta a
  una selección vacía. Si la selección se vacía, el alcance vuelve solo a toda
  la biblioteca.
- La selección la publica la vista **activa** (Canciones, cuadrículas,
  Artistas) y se limpia al salir.

### El defecto que apareció al conectarlo

Acotar la copia acota el plan, y **los huérfanos salen del plan**: con "Solo la
selección", todo lo demás del iPod habría aparecido como "ya no está en tu
biblioteca" — cientos de archivos ofrecidos para borrar que sí están. Nada se
borra sin que el usuario marque la casilla, pero **ofrecerlo ya es el error**.
Ahora los huérfanos siempre se calculan contra la biblioteca entera, aunque la
copia esté acotada.

### Pendiente de ver en pantalla

Seleccionar tres canciones, ir a General y comprobar que el selector se habilita
con "(3)", que «Revisar cambios» dice 3 y no 399, y que la lista de huérfanos
NO se llena con el resto de la biblioteca.

## Ronda de ajustes 3 — R3-3: General pasa a ser una ficha de dispositivo (2026-09-01)

Decisiones ST-127 y ST-128. **Compilado 0/0 en árbol aparte, Core 1062/1062;
falta verlo en pantalla** — el dueño tiene la app abierta con su sync pendiente.

### El defecto que lo disparó

La interfaz imprimía **"RockboxFamily"** —el nombre de un enum— en el título de
la ficha, en la barra de estado y en el destino de la sincronización. Entraba
por dos puertas: `IPodDiskInfo.DisplayName` terminaba en `- {RunningFirmware}`,
y `FirmwareUsbDisplay` era literalmente `RunningFirmware.ToString()`.

Las dos filas de jerga ("Firmware que atiende el USB" / "Familia declarada")
desaparecen y las reemplaza **una frase**: *"Firmware Aura instalado —
conectado desde Aura"*. La arma `DeviceFirmwareLabel` en Core, port del
`firmwareLabel` de macOS, con una prueba por combinación de los tres hechos de
ST-016 y una que recorre las 24 y falla si alguna imprime un identificador.

Importante: la frase **no redondea**. Archivos en el disco, Apple atendiendo el
USB y sin rastro de arranque se leen como "no hay evidencia de que esté
instalado", no como "instalado".

### La ficha

- Encabezado con icono, nombre editable, procedencia del nombre, la frase del
  firmware y la ruta — sin tarjeta, porque es la identidad, no un bloque más.
- Estado del firmware sobre ST-099, con el caso normal **dicho**: antes "no hay
  actualización" era silencio. Más un "Buscar actualizaciones" manual, que antes
  no existía (solo se consultaba al conectar).
- **Barra de capacidad segmentada** con leyenda y "X usados de Y — Z libres", en
  vez de cuatro filas de números. `StorageBreakdown` (Core) hace la aritmética:
  "Otro" nunca es negativo aunque el resumen del último sync haya quedado viejo,
  y "Libre" no lleva entrada en la leyenda (D-282).

### Lo que NO se hizo de (e), y por qué

El selector "Toda la biblioteca / Solo la selección" y el "N pendiente(s)" no se
pusieron: `SyncViewModel` no tiene alcance por elemento ni conteo de pendientes
antes de revisar. Poner el control sin eso sería un adorno que no hace nada. Es
el mismo hueco de «Sincronizar la selección» anotado en ST-125, y se cierra con
él.

### Pendiente de ver en pantalla

Que la ficha se lea como ficha y no como formulario, que la barra segmentada
tenga proporciones creíbles con los 351 MB del iPod del dueño, y que la leyenda
no se amontone.

## Ronda de ajustes 3 — R3-2 y el crash de Temas (2026-09-01)

Decisiones ST-125 y ST-126. **Compilado 0/0 en árbol aparte; falta verlo en
pantalla** — el dueño estaba sincronizando sus 399 archivos y el binario de
`bin/arm64` no se toca hasta que la sesión de pruebas lo libere.

### R3-2 — Sincronizar deja de ser una sección

`SidebarSection` de macOS no tiene un caso para sincronizar. Windows lo tenía
como sección con pantalla propia, lo que obligaba a irse de la vista del
dispositivo justo para actuar sobre el dispositivo.

- Fuera el ítem «Sincronizar» del pie de la barra lateral y su ruta.
- `SyncPage.xaml`/`.cs` borradas.
- General gana el bloque de sincronización, con el mismo contenido que la
  `DeviceActivityBar` de macOS: qué se copia, botones, avance, archivo en curso,
  fallos y los tres conteos.
- Los **huérfanos** pasaron a una hoja aparte, con casilla por archivo y ninguna
  marcada de entrada. Es lo único que Studio podría borrar del iPod; en la
  pantalla vieja era un bloque más al final, entre otros ocho.

**Divergencia que se conserva:** las casillas de Música/Videos/Fotos. macOS no
las tiene (allá la sync es de todo). Se quedan porque son capacidad, no adorno.

**Lo que falta, dicho:** «Sincronizar la selección» del menú §4.5 lleva a General
pero **no acota a la selección** — `SyncViewModel` filtra por tipo, no por
elemento. Se dejó navegando en vez de prometer un alcance que no se aplica.

### El crash de Temas

`InvalidCastException` (Boolean → Visibility) al dibujar la lista: dos enlaces
de `ThemesPage.xaml`, uno sin convertidor y otro con `InvertBool` —que devuelve
un `bool`, no una `Visibility`—. Los dos revientan con el primer tema que se
dibuja.

Es un error que **no se ve hasta que la pantalla se dibuja con datos**, así que
se barrió el resto de la app buscando lo mismo: `Visibility` sin convertidor,
`Visibility` con `InvertBool`, y el convertidor de visibilidad usado fuera de
`Visibility`. No había más.

### Pendiente de ver en pantalla

Que General se lea bien con el bloque nuevo (es la pantalla más cargada de la
app), que la hoja de huérfanos abra y que Temas ya no truene con temas reales
—lo cual necesita un iPod con temas instalados, que es la lista de cierre—.

## Ronda de ajustes 3 — R3-1: el iPod no se dejaba sincronizar (2026-09-01)

**Resuelto y verificado contra el aparato del dueño, conectado.** Decisiones
ST-123 y ST-124.

### Lo que pasaba

Con Aura corriendo, el iPod quedaba en `RunningFirmware = Unknown` y con eso
`SupportsAuraContract` en falso: sin biblioteca, sin sync, sin temas — con
`aura.cfg` y `.rockbox` presentes en `E:\`.

La app leía "qué firmware atiende el USB" de las cadenas **SCSI** del disco, no
de los descriptores USB. Con el adaptador **iFlash** de por medio, esas cadenas
las reporta el adaptador: `iFlash-P` / `latform iPod Ada`.

### La medición, que es lo que decidió el arreglo

Con el iPod conectado, el nodo USB del aparato reporta:

```
DEVPKEY_Device_BusReportedDeviceDesc = Rockbox media player   ← lo dice el aparato
DEVPKEY_Device_DeviceDesc            = Apple iPod             ← lo dice el INF
DEVPKEY_Device_Manufacturer          = Apple                  ← lo dice el INF
```

Y el nodo de interfaz (`&MI_00`), que hay que saltarse:

```
DEVPKEY_Device_BusReportedDeviceDesc = USB Mass Storage Device
```

Es decir: la cadena que macOS lee del descriptor USB **está disponible en
Windows**, en el nodo del aparato, y no es ninguna de las que se estaban
mirando. Se lee con `GetDeviceProperties` de `Win32_PnPEntity` — el mismo camino
de `Get-PnpDeviceProperty`—, sin interop nuevo.

### El resultado, en pantalla

- General: "Firmware que atiende el USB: **RockboxFamily**", "Familia declarada:
  **Aura**", nombre editable, 125 GB FAT32 leídos.
  (`docs/capturas/r3-general-rockboxfamily.png`)
- Sincronizar: destino reconocido y el plan real calculado — **399 archivos por
  copiar**, 0 al día. (`docs/capturas/r3-sync-plan-399.png`)

**La transferencia no se ejecutó.** "Revisar cambios" calcula sin escribir en el
iPod; darle a "Sincronizar" es decisión del dueño, no de la ejecutora.

### El NRE que mataba el flujo (ST-124)

`FamilyChangeWarning` reventaba con `NullReferenceException` desde
`CopyFilesAsync` y desde `RunFormatAsync`. El disparador es correcto y se queda
como está: el validador de seguridad **revalida el disco antes de cada operación
destructiva**, y ese refresco hace que el enlace de XAML lea la propiedad en
plena operación. Lo que estaba mal era la propiedad: dereferenciaba sin guardia.

**No se aisló cuál valor era nulo** — el log da la línea, no el estado. Se
corrigió la consecuencia, que era la grave: una propiedad de presentación no
puede lanzar, porque no rompe una etiqueta, tumba una escritura en el iPod.

### Encontrado de paso, sin corregir

En el mismo `errores.log`, un `InvalidCastException` en Temas:
`Update_CanShare` intenta convertir un `Boolean` a `Visibility` — falta un
convertidor en un enlace de `ThemesPage`. No se tocó porque no es de esta ronda
y no bloquea nada del sync; queda anotado para que no se pierda.

## Ronda de ajustes 2, Paquete B — Windows (2026-09-01)

Contra los tres documentos vinculantes que dejó la Mac —
`docs/normalizacion-artistas.md`, `docs/caratula-recomendada.md` y
`docs/paridad-menus-contextuales.md`—, no contra el plan ni contra la
memoria. Decisiones **ST-117…ST-122**.

### Entregado

| Tarea | Estado |
|---|---|
| R2-1 casillas solo con selección (ST-120) | **completa** — más el hover, que es lo que la hace descubrible |
| R2-2 aridad de los menús (ST-119) | **completa** — y apareció un ítem que no hacía nada |
| R2-3 carátula recomendada (ST-118) | **completa** — puntaje, umbral y desempates calcados |
| R2-4 homologación de artistas (ST-117) | **completa** — agrupación, ajuste y excepciones |
| R2-6 rediseño de Artistas (ST-121) | **completa** — se revoca la divergencia de ST-108 |

**Compuertas:** `dotnet test` **1031/1031**; `AuraStudio.App` compila
**0 advertencias / 0 errores** en ARM64. Sin commit.

### Dos defectos que aparecieron al hacerlo

- **La cuadrícula de Álbumes ofrecía «Buscar carátulas del álbum...» y el
  ítem no hacía nada.** El menú lo incluía desde la Ronda 1, pero el
  despachador de esa pantalla no tenía el caso: la hoja vivía dentro de la
  pantalla de Canciones. Se extrajo a `AlbumCoverPicker` y ahora la
  comparten las tres entradas que pide §13.2 del documento de paridad. Es
  el tipo de hueco que ninguna compuerta atrapa — compila, y el menú se ve
  bien.
- **`ApplyAlbumCover` marcaba siempre `MetadataEditedByUser`.** Con la
  acción automática de R2-3 eso habría blindado contra mejoras futuras una
  tapa que nadie miró. Ahora es un parámetro, y solo la elección manual lo
  marca.

### Cómo se verificó la app sin tocar la instancia del dueño

El dueño tenía la app abierta probando la rueda, así que el `.exe` de
`bin/arm64/...` estaba bloqueado y recompilar habría pisado su sesión.
Redirigir solo la salida (`BaseOutputPath`) **no sirve**: el compilador de
XAML falla con un error interno. Lo que sí funciona es **copiar los dos
proyectos a un árbol aparte** (sin `bin/` ni `obj/`) y compilar ahí — misma
verificación de 0/0, cero riesgo para lo que el dueño está usando. Queda
anotado porque va a volver a hacer falta.

### Verificación en pantalla (2026-09-01, con la app compilada)

Capturas en `docs/capturas/r2-*.png`.

**Confirmado a ojo:**

- **Artistas** se ve como la de macOS: lista con avatares redondos a la
  izquierda, ficha a la derecha con avatar grande, nombre, resumen,
  «Buscar información en línea» y «⋯»; cada álbum con su portada de 128,
  "género · año", el conteo y sus pistas.
- **La homologación, visible**: "Gorillaz" es **una sola fila** con 14
  álbumes y 93 canciones, y dentro, la pista «911» muestra **«Gorillaz +
  D12»** debajo del título, que es exactamente el renglón que la regla de
  R2-4 vino a hacer legible. "Spacemonkeyz vs. Gorillaz" queda aparte,
  como manda el documento.
- **Casillas**: sin nada seleccionado, **ninguna**; con un álbum
  seleccionado, **todas**, y la barra dice "1 seleccionado".

**NO confirmado, y por qué:**

- **La casilla al pasar el cursor.** El movimiento sintético del arnés no
  la hizo aparecer. Que el enlace funciona está probado por el estado de
  selección —es el mismo `ShowsSelectionBox`—, así que lo que falta por
  saber es si falla el hover de verdad o solo el hover inyectado. **Queda
  para el dueño con un mouse real.**
- **Los dos gestos nuevos para vaciar la selección** (clic en vacío y
  Escape) se agregaron después de la última pasada visual.
- **«Aplicar carátula recomendada»** no se ejecutó a propósito: baja tapas
  de la red y las escribiría en la biblioteca **real** del dueño.

### Dos cosas que hay que decir

**1. La app escribió en la biblioteca real del dueño.** A las 14:25:52 se
reescribieron `biblioteca.json` y archivos de `.portadas/`. No fue una
acción mía en la interfaz: la app persiste el catálogo al cargar y al
refrescar, así que **abrirla ya escribe**. Verificado que el contenido
quedó igual —401 elementos, 17 pistas de "D-Sides", 90 portadas—, pero la
consigna de la noche era no tocar esa biblioteca, y esto la tocó. Por eso
se detuvo ahí la verificación en pantalla en vez de seguir con la acción
automática de carátulas.

**2. Un álbum partido en dos por dos guiones distintos.** En Álbumes se
ven dos "D-Sides" de Gorillaz (15 canciones y 2). No es la homologación:
son **dos caracteres distintos** en el título — 15 pistas con `D-Sides`
(`U+002D`, guion ASCII) y 2 con `D‑Sides` (`U+2010`, guion tipográfico).

`LibraryGrouping.Normalize` recorta espacios y quita mayúsculas y acentos,
pero no unifica la puntuación Unicode. **No se corrigió acá a propósito:**
esa función es la normalización **compartida** con macOS, y cambiarla solo
de un lado crearía exactamente la divergencia entre apps que
`docs/normalizacion-artistas.md` existe para evitar. Es una decisión para
las dos apps a la vez.


## Micro-tarea — la rueda del mouse no desplaza (2026-09-01)

> **Confirmado por el dueño en pantalla el 2026-09-01.** Cerrado. La
> decisión quedó como ST-122.

**Causa raíz encontrada y corregida: la app corría sin conciencia de DPI.** El
`app.manifest` estaba en el repo declarando `PerMonitorV2`, pero el `.csproj`
nunca lo nombraba con `<ApplicationManifest>`, así que **no se embebía en el
`.exe`**. El SDK de .NET no lo toma por convención.

En el monitor del dueño, al 200%, eso significa que Windows le virtualiza las
coordenadas a la app (medido: con el cursor en 2792,1400 el hilo de la app
recibía 1396,700), le escala el mapa de bits —de ahí que todo se viera un poco
suave— y **deja de entregarle los mensajes de rueda por completo**: con un
espía de mensajes en el hilo de la interfaz no llegaba ni un `WM_MOUSEWHEEL`,
mientras los `WM_MOUSEMOVE` sí llegaban. Por eso la rueda no movía nada en
ninguna parte de la app, ni cuadrículas, ni tablas, ni el panel lateral.

Con el manifiesto embebido y `dpiAware` corregido a `true/pm` (el valor viejo,
`PerMonitorV2`, no es válido en ese elemento y Windows lo ignoraba), la rueda
funciona: cuadrícula de Álbumes 0% → 53,1%; tabla de Canciones 0% → 18%; y los
eventos `PointerWheelChanged` llegan a XAML, comprobado con un manejador puesto
en la raíz.

**Efecto secundario, esperado y de una sola vez:** el tamaño de ventana
guardado antes del arreglo estaba en píxeles virtualizados, así que la primera
ventana tras actualizar sale a la mitad de grande. Se acomoda sola en cuanto el
dueño la redimensiona una vez.

**Lo que NO era la causa:** el subclaseo Win32 de la ventana de WinUI (el que
atiende `WM_DEVICECHANGE`). Se sospechó de él y se llegó a medir "sin subclaseo
la rueda anda", pero esa medición era falsa — corría un binario viejo, porque
`dotnet build -r win-arm64` deja la salida en `bin/Debug/.../win-arm64/` y no en
`bin/arm64/Debug/...`, que es de donde se lanzaba la app. Con el binario
correcto, quitar el subclaseo **no cambia nada**. Quedó como estaba.

El defecto de maquetado de abajo es aparte: es real, se corrigió, y explica que
la tabla de Canciones no se pudiera desplazar **ni siquiera con el teclado**.

### El defecto de maquetado

En la tabla de Canciones el contenedor de la tabla abarcaba **dos filas con
`Grid.RowSpan="2"`, y la primera era `Auto`**. Una fila `Auto` mide a su
contenido con altura infinita, así que la tabla nunca recibía un alto acotado:
la lista de adentro **no era un contenedor desplazable en absoluto** —medido con
`ScrollPattern`: `vertical=False`— y las filas simplemente se cortaban contra el
borde de la ventana, sin barra y sin forma de llegar al resto.

Corregido: la tabla ocupa solo la fila `*`. Ahora la lista sí desplaza —
`vertical=True`, viewport 10.8% con 174 canciones— y se recorre con Av Pág
(verificado: 0% → 24.3%).

Se agregó además una red de seguridad: si la rueda llega al contenedor
horizontal **sin que nadie la haya atendido**, se le pasa a la lista. Va sin
`handledEventsToo` a propósito, así que **no puede desplazar de más**: cuando la
lista ya atendió el evento, este manejador ni se entera.

### Cómo se midió, y las trampas del camino

Todo lo de arriba está medido con el patrón de accesibilidad (`ScrollPattern`),
no con imágenes: una comparación por captura dio un falso positivo temprano —lo
que cambiaba entre las dos imágenes era el resaltado del mouse al pasar por
encima, no el desplazamiento—.

Tres trampas costaron horas y conviene dejarlas escritas:

1. **La salida del build.** `dotnet build -r win-arm64` escribe en
   `bin/Debug/<tfm>/win-arm64/`; el comando de la bitácora,
   `-p:Platform=ARM64`, escribe en `bin/arm64/Debug/<tfm>/`. Lanzar uno mientras
   se compila el otro hace que las pruebas de runtime midan código viejo.
2. **El DPI del arnés de pruebas.** PowerShell arranca sin conciencia de DPI, y
   entonces `SetCursorPos` y `GetWindowRect` hablan en coordenadas virtualizadas
   mientras la automatización de accesibilidad devuelve físicas. El cursor caía
   fuera de la ventana y parecía que la app ignoraba la rueda. Se arregla con
   `SetProcessDPIAware()` al inicio del script.
3. **Inyectar la rueda de verdad.** `SetForegroundWindow` no hace nada desde un
   proceso de fondo si no se engancha antes la cola de entrada con
   `AttachThreadInput`. Y conviene validar el arnés contra otra app (el
   Explorador desplazó 0% → 0,3%) antes de creerle un "no se movió".

## Ronda de ajustes 1, Paquete B — Windows (2026-09-01)

### Entregado (Core 981/981; ARM64 0/0)

| Tarea | Estado |
|---|---|
| 1. Escritura canónica del catálogo (ST-102) | **completa** — y apareció una tercera causa: las carátulas viejas (ST-107) |
| 2. Paridad de menús contextuales (ST-105) | **completa** — los diez menús cableados y verificados (ST-111, ST-112) |
| 3. Buscar carátulas del álbum (ST-104) | **completa** en Core y en la tabla de Canciones |
| 4. Casillas de selección (ST-103) | **completa** — no era una divergencia, faltaba entero (ST-108) |
| 5. El 503 de MusicBrainz | **completa** (ST-109) |

### Los diez menús, verificados uno por uno

Leídos por automatización de accesibilidad —que de paso comprueba que un lector
de pantalla los ve—: §4 (13 ítems), §1 (6), §9 (5) y §11 (4), cada uno idéntico
al documento. **§10 (temas) no se pudo ver**: la lista está vacía sin un iPod
conectado, así que queda para la sesión con el dueño.

**«Obtener información...»** se filtra del menú §4 mientras la edición de
metadata en lote no tenga pantalla (ya estaba en los pendientes de la auditoría
de paridad). Mostrar el ítem sería ofrecer algo que no hace nada.

### Tercera divergencia legítima contra macOS

Además de las dos del documento (§13), **Artistas sí lleva casillas en
Windows**: en macOS la exclusión es por el control nativo de lista, que acá no
existe — Artistas es la misma cuadrícula que Álbumes. Razonado en ST-108.

### Tres defectos que solo aparecieron mirando

- El menú contextual de la tabla de Canciones **no abría** salvo justo sobre la
  columna del título: el manejador miraba el `DataContext` del origen y las
  celdas tienen el suyo. Venía de antes de esta ronda.
- El 503 del dueño está en el propio `errores.log` de la app, con su pila:
  confirma que escapaba al manejador global.
- «Todas las fotos» tenía el menú de **álbumes de fotos**, así que ofrecía
  «Disolver álbum» sobre una foto suelta. Error propio del primer turno del
  paquete, corregido al cablear §9.

## Cierre de la corrida — actualización directa y el riesgo #6 (2026-09-01)

- **Actualizar el firmware es un botón y una barra** (D-222, ST-099): el aviso
  de versión nueva en General ahora trae "Actualizar ahora". Por dentro es el
  mismo `CopyFilesAsync` del asistente —revalida el disco, toma el candado— y
  **no formatea ni entra a DFU**, así que no agrega ningún camino destructivo
  nuevo. Sin probar contra el aparato, como todo el instalador.
- **Riesgo #6 evaluado y cerrado en "todavía no"** (ST-100): el port ya es más
  grande que la app que porta (38 075 líneas contra 25 246 de Swift), pero los
  contratos, la numeración `ST-NNN` y la auditoría de paridad viven de tener
  los dos árboles juntos. Se revisa cuando la app de Windows tenga ciclo de
  publicación propio.

## Fase 7 — Auditoría de paridad pantalla por pantalla (2026-09-01)

Las 43 vistas de la app de macOS, contra lo que hay en Windows. Tres estados:
**equivalente** (existe y hace lo mismo), **de otra forma** (el mismo trabajo
resuelto con otro patrón, porque Windows no tiene el de macOS) y **pendiente**
(no está, y se sabe).

| macOS | Windows | Estado |
|---|---|---|
| `ContentView` | `ShellPage` | equivalente |
| `DeviceGeneralView` | `DeviceListPage` | equivalente |
| `DeviceNameField` | Campo de nombre en General (ST-096) | equivalente |
| `DeviceActivityBar` | Estado en `SyncPage` + el encabezado de la navegación | de otra forma |
| `WelcomeView` | `InstallerStep.Welcome` | equivalente |
| `PermissionsView` | `InstallerStep.Permissions` | equivalente |
| `DetectDeviceView` | `InstallerStep.DetectDevice` | equivalente |
| `EnterDFUView` | `InstallerStep.EnterDfu` | equivalente |
| `InstallingView` | `InstallerStep.Installing` | equivalente |
| `AwaitBootloaderUSBView` | `InstallerStep.AwaitingBootloaderUsb` | equivalente |
| `DoneView` | `InstallerStep.Done` | equivalente |
| `InstallerHomeView`, `InstallerWizardView` | `InstallerPage` | equivalente |
| `PrivilegedActionSheet` | Pantalla explicativa antes del diálogo de UAC | equivalente |
| `RestoreHandoffView` | — | **pendiente** |
| `AutomaticUpdateView` | Aviso de versión nueva en General → Instalador | parcial |
| `AlbumsView`, `ArtistsView` | `MediaGridPage` (Álbumes / Artistas) | equivalente |
| `MoviesView`, `SeriesView` | `MediaGridPage` (Películas / Series) | equivalente |
| `PhotoAlbumsView` | `MediaGridPage` (colecciones de fotos) | equivalente |
| `MediaSectionView` | `SongsPage` / `MediaGridPage` | equivalente |
| `LibraryBrowsingComponents` | Plantillas de `MediaGridPage` | de otra forma |
| `LibraryStatusBar` | Barra de conteos al pie de Canciones | equivalente |
| `MediaInfoView` | `MediaInfoDialog` | equivalente |
| `BatchMediaInfoView` | — | **pendiente** |
| `CoverContaminationSheet` | — | **pendiente** |
| `PlaylistsView` | `PlaylistsPage` | equivalente |
| `SimilarItemsView` | `SimilarItemsPage` | equivalente |
| `TableHeaderMenu`, `MusicViewOptionsView` | Menús de columnas y orden en Canciones | equivalente |
| `SyncSheets` | Hoja de huérfanos y estado en `SyncPage` | equivalente |
| `ThemesView` | `ThemesPage` | equivalente |
| `ExtrasView` | Navegación Extras (hoy solo Temas) | equivalente |
| `LicensesView` | `LicensesPage` | equivalente |
| `SettingsSectionView` | `SettingsPage` | equivalente |
| `MusicSettingsView` | Ajustes › Música | equivalente |
| `PhotoSettingsView` | Ajustes › Fotos | equivalente |
| `VideoSettingsView` | Ajustes › Video | equivalente |
| `ServicesSettingsView` | Ajustes › Servicios | equivalente |
| `GitHubTokenSettingsView` | Ajustes › Servicios (token) | equivalente |
| `AppMenuCommands` | — (Windows no lleva barra de menú de app) | de otra forma |
| `BackContinueRow` | Botonera de cada paso del instalador | de otra forma |

### Rendimiento con una biblioteca del tamaño de la del dueño

`tools/LibraryPerfCheck` (fuera de la solución, como `ImageResizerCheck`) genera
1000 álbumes × 12 pistas = **12 000 canciones** y mide lo que la app hace en
cada arranque y en cada cambio de sección. En esta VM, en Release:

| | |
|---|---|
| `biblioteca.json` | 5.9 MB |
| Leer el catálogo (arranque) | 179 ms |
| Agrupar por álbum (1000) | 25 ms |
| Agrupar por artista | 23 ms |
| Armar y ordenar la tabla de Canciones | 31 ms |
| Comprobar que los archivos estén | 54 ms **en disco local** |
| Planificar una sincronización completa | 20 ms |

Nada de esto necesita optimización. **El único punto que puede doler es el
penúltimo**: la app filtra por archivo presente en cada recarga, y con la
biblioteca en la carpeta compartida de Parallels cada consulta se va por la red
— 54 ms locales pueden ser varios segundos ahí. Medirlo contra `V:` es parte de
la sesión con el dueño; si duele, la salida es cachear el resultado e
invalidarlo al cambiar de carpeta, no quitar la comprobación (que es lo que
distingue "no está el archivo" de "no está en la biblioteca", ST-087).

### Auditoría Fluent 2

- **Claro y oscuro**: todas las pantallas usan tokens del sistema
  (`ThemeResource`), nunca colores fijos. Verificado en oscuro con la tabla de
  Canciones —el caso más denso— y con Sincronizar
  (`docs/capturas/fase7-oscuro-canciones.png`).
- **Ventana chica**: a 900×640 nada se corta ni se sale del borde; las tarjetas
  respetan su ancho mínimo y la navegación hace scroll
  (`docs/capturas/fase7-oscuro-ventana-chica.png`).
- **Acento del sistema**: los botones primarios usan `AccentButtonStyle`, así
  que siguen el color que el usuario tenga puesto en Windows.
- **Lectores de pantalla**: los botones con solo un ícono llevan
  `AutomationProperties.Name` (6 en Canciones, 2 en Ajustes, 1 en las
  cuadrículas); el resto son botones con texto, cuyo nombre accesible es su
  propio contenido. **Falta** marcar como decorativos los íconos de encabezado
  de General y del Shell: hoy un lector los anuncia como si fueran contenido.
- **Teclado**: la navegación por tabulador funciona por ser controles estándar,
  pero **no se probó dirigidamente** y no hay aceleradores propios.

Lo que **no** se pudo auditar acá: escalado de DPI distinto del de esta VM, y
rendimiento con una biblioteca de mil álbumes — la del dueño está fuera de
límites esta noche y no se generó una sintética de ese tamaño.

### Las tres pendientes, y por qué

- **`RestoreHandoffView`** — el paso final de volver al firmware de Apple, que
  en macOS lo termina Finder. En Windows el equivalente sería iTunes o el
  Dispositivos de Apple, y **no se puede diseñar sin probarlo con el iPod**:
  queda para la sesión con el dueño.
- **`BatchMediaInfoView`** — editar metadata de varios elementos a la vez. La
  edición de uno está completa (`MediaInfoDialog`); la de lote es comodidad, no
  contrato.
- **`CoverContaminationSheet`** — la hoja que revisa carátulas que se colaron
  como fotos. `CoverArtAssets` ya está en Core y decide qué imagen es carátula;
  falta la hoja de revisión con vista previa, que ST-012 exige antes de quitar
  nada de Imágenes. **Mientras no exista, no hay ningún camino que borre
  imágenes**, así que la regla se cumple por ausencia, no por implementación.

## Fase 6 — Nombre del iPod, hora y completar en línea (2026-09-01)

### Entregado (Core 901/901; ARM64 0/0)

- `DeviceConfig`/`DeviceNameStore` — `CONTRATO-dispositivo.md` v2 entero,
  incluida la propiedad del nombre: solo lo edita la instalación que lo puso.
- `ClockSyncWriter` — la hora al conectar, sin llevarse por delante ningún otro
  ajuste de `aura.cfg`.
- `ArtistImageResolver` — MusicBrainz + fanart.tv, y el motivo dicho cuando no
  hay foto.
- App: el campo de nombre en General (solo lectura y con explicación si es de
  otra instalación), la hora al conectar, `EnrichmentService`, "Completar en
  línea" en Canciones y "Buscar fotos de artista" en Artistas.

### Ya estaba de fases anteriores

Los puntos 1 y 2 de la fase —Credential Manager y los ajustes— se cerraron en
ST-086; el ajuste de ffmpeg se sumó en ST-093.

### Verificado contra la red real

"Completar en línea" corrido sobre una biblioteca de fixtures: la canción sin
etiquetas pasó de "Necesita revisión" a "Listo" con artista y álbum resueltos
(`docs/capturas/fase6-completar-en-linea.png`).

### Pendiente de la Fase 6

Solo el criterio de aceptación, que exige las **claves reales del dueño**: sin
clave de fanart.tv ni de TMDB, las fotos de artista y los pósters solo se
pueden probar por el camino de "no hay clave" — que es justo el que sí está
cubierto. El punto 4 (actualizador por familia) se cerró en ST-096 y ST-099; los
pósters de video, en ST-101.

## Fase 5 COMPLETA — Temas (2026-09-01)

### Entregado (Core 866/866; ARM64 0/0)

- `ThemeActivation` (Core, puro): qué tema está activo y cómo cambiarlo sin
  perder el resto de `aura.cfg`; el id sugerido a partir del nombre.
- `ThemeInstaller` (Core): listar, instalar, construir e instalar, activar,
  eliminar y exportar. La clase de la app quedó como una costura de ocho
  líneas — así el ciclo completo se prueba sin un iPod (ST-095).
- App: `ThemesPage`/`ThemesViewModel`, en Extras › Temas.

### El criterio de aceptación de la fase, cubierto por pruebas

Construir → validar → instalar → activar → eliminar contra un volumen de
mentira, más las reglas de licencia demostradas: un tema abierto se exporta
como `.zip`; uno de uso personal **no**, ni siquiera llamando directo al
servicio. Y un id con `..` o con barras se rechaza antes de tocar una ruta.

### Lo que falta ver en pantalla

La lista con temas de verdad necesita el iPod: la captura
(`docs/capturas/fase5-temas.png`) muestra la pantalla sin dispositivo, que es
lo único observable sin el aparato.

## Fase 4 — Transcodificación y pantalla de sincronizar (2026-09-01)

### Entregado (Core 830/830; ARM64 0/0)

- `Media/FfmpegArguments`, `Media/FfmpegOutput`, `Media/FfmpegLocator`,
  `Media/VideoTitleParser`, `Library/StagingPaths` — todo lo que es contrato con
  el aparato o parseo, en Core y probado sin ffmpeg instalado (ST-093).
- App: `Platform/FfmpegRunner` (el proceso), `LibraryProcessor` con video real
  (sondeo, categoría, `SxxEyy` del nombre, recorte, transcodificación con
  progreso, póster) y **fotos redimensionadas**, que antes viajaban enteras.
- Ajustes › Video: dónde está ffmpeg, con el comando de instalación exacto y un
  selector para quien lo tenga en una carpeta propia.
- `SyncPage` reescrita y **puesta en la navegación** — no estaba (ST-094).

### Verificado en pantalla

`docs/capturas/fase4-sincronizar.png`, `fase4-ajustes-video.png`. Dos defectos
de maquetado aparecieron solo al mirar: la tarjeta de estado quedaba alta y
vacía por renglones en blanco, y quitar la alineación izquierda mandó el
contenido fuera del borde derecho. El glifo `E895` se renderizó antes de usarlo.

### Lo que NO se pudo verificar acá

**ffmpeg no está instalado en esta VM** (ni en el PATH, ni por winget). Los
argumentos y los parsers están probados, pero **ninguna conversión real se
ejecutó**: eso queda para la sesión con el dueño, junto con el sync al iPod.

### Pendiente de la Fase 4

Solo el paso 5: sincronizar una biblioteca chica al iPod real y arrancar el
firmware para ver que reconstruye sus índices.

## Fase 4 — Motor de sincronización en Core (2026-09-01)

### Entregado (Core 789/789; ARM64 0/0)

- `Library/SyncLayout` — dónde va cada archivo en el iPod: tres layouts de
  música, cuatro formatos de nombre, saneo FAT32, tope de **95 bytes UTF-8** en
  `/Videos` y `/Photos`, `SxxEyy` que sobrevive al recorte, póster de temporada,
  y las rutas hermanas (`.lrc`, `<video>.jpg`, `cover.jpg`).
- `Library/SyncPlanner` — qué copiar, qué saltear, qué barrer y qué proponer
  para borrar. Puro: no toca disco.
- `Library/DeviceSyncManifest` — el manifiesto, **compatible byte a byte con el
  que escribe la Mac** (ST-090).
- `Library/LibrarySyncEngine` — la copia real: transaccional por bloques,
  cancelación segura, fallas parciales, marcador del firmware.
- `Library/LibrarySyncFinalizer` — letras, carátulas, listas, pósters, resumen,
  calificaciones e índices de categoría y de fotos de artista (ST-092).
- `Library/ArtistImageStore` — port del almacén local de fotos de artista, con
  el mismo algoritmo de nombre de archivo que macOS.
- App: `SyncService` reescrito encima de todo eso; `SyncManifest` provisional
  **eliminado** (escribía en la misma ruta con otro formato).

### Tres cosas que el servicio provisional hacía mal

1. **Borraba del iPod sin preguntar** todo lo que ya no estuviera en la
   biblioteca. Ahora eso se propone y se explica; solo se borra lo confirmado
   (ST-091).
2. **Escribía un `sync_manifest.json` que macOS no podía leer** — habría
   provocado una recopia completa cada vez que el dueño cambiara de app.
3. **Ignoraba la carpeta de biblioteca configurada** (usaba siempre la de
   omisión) y aplanaba todo a `Music/<nombre de archivo>`, sin artista ni
   álbum.

### Verificación

Todo contra un directorio temporal que simula el volumen: 21 casos del motor
(copia completa, reubicación sin duplicar, huérfano que **no** se borra solo,
huérfano confirmado que se va con su `.lrc`, cancelación con marcador escrito,
barrido de temporales, falla parcial que no detiene el resto, base de música
preservada o borrada según lo que anuncie `aura.cfg`, `/.aura/thumbs` y
`/.aura/art` intactos), 8 del manifiesto (incluida la lectura de uno escrito
por la Mac y el ida y vuelta sin cambios) y 20 del finalizador.

### Pendiente de la Fase 4

Transcodificación, hoja previa de sincronización con la confirmación de
huérfanos, progreso con cancelación en la interfaz, y expulsión segura.

## Fase 3 COMPLETA — hoja de información, listas y revisión de similares (2026-09-01)

Decisión formal → **ST-089**. Con esto la Fase 3 del plan queda cerrada.

### Entregado (Core 693/693; ARM64 0/0)

- **`Library/MediaInfoEdit`** (+19) y la hoja "Más información": título, artista
  y álbum obligatorios con el motivo en pantalla; vacío = ausente; la letra
  conserva su formato; cero estrellas = sin calificar; carátula y MusicBrainz
  sobreviven a la edición. Editar a mano enciende `MetadataEditedByUser`.
- **Listas de reproducción**: crear, renombrar, eliminar, importar M3U y
  exportar. Lo que no está en la biblioteca se cuenta y se dice.
- **Revisión de elementos parecidos** (ST-063): evidencia, confianza, sugerido a
  conservar y correcciones propuestas. Nada se aplica solo; quitar no borra
  archivos; "no son lo mismo" se recuerda y se puede restablecer.

### Verificado en pantalla

Listas y Elementos parecidos abiertos y ejercitados con una biblioteca de
fixtures; `errores.log` vacío.

### Aviso operativo

La preferencia de biblioteca apuntaba a `V:\Mac Externo\...` (la real del
dueño). Por la regla nocturna de no tocarla, **se cambió a una carpeta de
fixtures**. Verificado que nada se escribió en la real: su última escritura
sigue siendo la de las 02:19:27. Devolverla es un clic en Ajustes › Biblioteca.

## Corrección #1 de Fase 2: el crash sin mensaje, y el silencio que lo hizo indiagnosticable (2026-09-01)

Decisión formal en `DECISIONS.md` → **ST-088**.

### La evidencia primero, como pedía el plan

Dos registros de `AuraStudio.App.exe` en el Visor de eventos, ambos con
excepción **`0xC000027B`** (excepción "guardada" no controlada) en
`Microsoft.UI.Xaml.dll`, con el fallo real en `combase.dll`: **E_FAIL**
(`0x80004005`) el 31/08 a las 23:27 y **E_POINTER** (`0x80004003`) a las 16:13.

**Del lado de Aura Studio no quedó nada.** Ni mensaje, ni archivo, ni pista.

### Lo más grave era ese "nada", y era propio

La app no tenía **ningún** manejador global de excepciones. En WinUI 3, una
excepción que escapa de un manejador de interfaz mata el proceso **sin
diálogo**; sin nadie que la anote, lo único que queda es un código COM.

Ahora está `Services/CrashReporter`: engancha `Application.UnhandledException`,
`AppDomain.UnhandledException` y `TaskScheduler.UnobservedTaskException`, y
escribe tipo, mensaje y pila en `%LOCALAPPDATA%\Aura Studio\errores.log`, con
aviso en pantalla cuando se puede.

La excepción de interfaz se marca como controlada. Es una decisión con costo
—la app sigue viva y quizá en un estado raro—, pero morir en silencio es peor:
el usuario no sabe si su iPod quedó a medias y no queda nada que mirar.

### El defecto concreto que sí se encontró

El estado del dispositivo podía actualizarse **fuera del hilo de interfaz**.
`UsbDeviceWatcher.Scan()` corre en `Task.Run`, y `DevicesChanged` llega a
`DeviceSessionService.Reevaluate()`, que muta propiedades observables leídas por
los enlaces XAML. Desde un hilo del grupo eso revienta dentro de `combase.dll`
— la firma exacta que quedó registrada. Y aparecería justo en el cambio de
familia porque instalar Metro después de Aura re-enumera el iPod varias veces
por USB (DFU, bootloader, modo disco), y cada una dispara otro sondeo.

`Reevaluate` vuelve ahora siempre al hilo de interfaz (`App.UiDispatcher`,
capturado en `OnLaunched`), y un `Debug.Assert` avisa si algún camino nuevo se
salta ese paso.

### Lo que NO se puede afirmar

Sin el iPod no hay cómo reproducir el crash, así que **no se puede decir que
esté arreglado**. Lo que sí: se corrigió un defecto real y compatible con la
firma, y se eliminó la ceguera que impidió diagnosticarlo. La próxima vez habrá
un archivo legible en vez de arqueología sobre un código COM. Reproducirlo con
el aparato sigue pendiente.

### Punto 2 de la lista, verificado y cerrado

El P0 de arranque ya no está: `UsbDeviceWatcher` no consulta WMI en su
constructor, `DeviceSessionService` tampoco, y el primer sondeo lo pide la
ventana en `Activated` con tope de 12 s.

### `.preparados` protegido

Instrucción del dueño tras ST-087. Hoy ningún código lo borra; para que siga
siendo cierto, `LibraryStore.NeverCleaned`/`IsProtected` lo declaran de forma
consultable y `CatalogPreservationTests` lo fija.

### Verificación

- `dotnet test` → **674/674** · ARM64 → 0/0 · `ImageResizerCheck` → 26/26
- App arrancada con el reportador puesto: abre, navega e Instalador responde;
  `errores.log` quedó vacío, que es lo correcto cuando no hay errores.

## Pérdida de datos en la biblioteca compartida — causa, corrección y lo que no se recuperó (2026-09-01)

Decisión formal en `DECISIONS.md` → **ST-087**. Se lee antes que nada al tocar
persistencia de biblioteca.

### Qué pasó

El dueño usa **la misma carpeta de biblioteca desde la Mac y desde Windows** —es
un requisito del producto, no una prueba suelta—. Al abrir la app de Windows
apuntada ahí, `biblioteca.json` pasó de **2809 elementos (3,456,595 bytes)** a
**401 (446,642 bytes)**. Se perdieron 2408 entradas: títulos, artistas, álbumes,
letras sincronizadas, enlaces de MusicBrainz, calificaciones, favoritos,
categorías y álbumes de fotos.

**Los archivos de medios no se tocaron.** Lo perdido es la metadata que solo
vivía en el catálogo.

### La causa

La app descartaba al leer los elementos cuyo archivo no alcanzaba, y después
guardaba esa lista recortada como si fuera el catálogo completo.

`Reload` filtraba con `File.Exists` —igual que `loadCatalog` en macOS— y `Save`
escribía esa misma lista. En macOS es inofensivo: es su propia biblioteca y los
archivos siempre están. En Windows, con 2408 rutas que no se resuelven por la
red, el filtro se volvió un borrado. Bastó que el reintento de los elementos
"en cola" disparara un guardado.

### La regla que faltaba

> **Lo que se guarda es siempre el catálogo completo. Filtrar es cosa de la
> vista, y una lista filtrada no puede llegar jamás a una ruta de escritura.**

`Items` es ahora el catálogo entero —lo que se guarda—, `AvailableItems` es lo
que se muestra, y las dos se recalculan juntas en `RefreshAvailable()`. Lo que
no está se conserva intacto y vuelve solo si el archivo reaparece.
`CatalogPreservationTests` falla si el almacén vuelve a descartar algo por su
cuenta.

### Dos daños colaterales del mismo error

- Un elemento sin metadata cargada **borraba su carátula** al guardarse. Ahora
  la carátula solo se toca cuando el elemento la trae.
- `CoverPath` usaba el id sin guiones y en minúsculas; macOS escribe
  `<ID EN MAYÚSCULAS CON GUIONES>.jpg`. Cada app escribía su propia carátula
  para la misma canción y ninguna veía la de la otra.

### Escritura compatible con macOS

Requisito nuevo del producto. La app de macOS decodifica con
`try? JSONDecoder().decode(...)` por omisión: **lo que no puede leer no da
error, deja la biblioteca vacía en silencio** — el espejo del bug de lectura de
ST-086. Windows escribe ahora la forma que Swift decodifica: fechas como
segundos desde 2001, identificadores en mayúsculas con guiones, y los nombres
exactos `musicBrainzRecordingID`, `musicBrainzReleaseID` y `trackItemIDs` (los
tres que camelCase automático escribía distinto, y que Swift habría ignorado sin
decir nada). `SwiftInteropTests` fija la lista completa de campos y sus tipos.

### Lo que NO se pudo recuperar

No hay copia previa al alcance: la escritura es atómica (sin archivo parcial),
el recurso es de red (sin instantáneas de Windows) y la `.Trash` del recurso no
tiene nada. **La vía de recuperación es Time Machine o el respaldo de la Mac**,
y es del dueño.

### Trabajo futuro anotado

Evaluar un aviso o candado suave cuando las dos apps abran la misma carpeta a la
vez (encargo del dueño; hoy la concurrencia es responsabilidad suya).

### Verificación

- `dotnet test` → **672/672** · ARM64 → 0/0 · `ImageResizerCheck` → 26/26
- La comprobación de ida y vuelta contra el catálogo real ya no sirve como
  referencia: **el archivo en disco es el dañado**, así que compara contra una
  base equivocada. Las pruebas de interoperabilidad usan un fragmento con la
  forma exacta que escribe macOS, tomado del archivo antes del daño.

## Fase 3 — Ajustes con paridad de macOS, y dos bugs que escondían una biblioteca entera (2026-09-01)

Decisión formal en `DECISIONS.md` → **ST-086**. Encargo del dueño llegado a
mitad de la fase (adelantado de la Fase 6): paridad de Ajustes con la app de
Mac, empezando por la carpeta de la biblioteca configurable.

### Lo que se hizo (Core, 659/659 tests; ARM64 0/0)

- **Las seis pestañas de macOS**, con el inventario completo de `AppPreferences.swift`:
  General, Biblioteca, Música, Fotos, Video y Servicios.
- **`Platform/CredentialStore`** — el Administrador de credenciales de Windows,
  equivalente del Llavero. Las claves de fanart.tv, TMDB y el token de GitHub
  viven ahí y **nunca** en `preferences.json`.
- **`Library/LibraryOptions`** (+14) — los enums de organización, nombre de
  archivo y calidad, con los **mismos valores persistidos que macOS** para que
  un criterio signifique lo mismo en las dos apps.

### Cambiar la carpeta de la biblioteca

Se leyó `switchLibraryFolder` de macOS antes de escribir: **no migra, no copia,
no mueve**. Apunta a la carpeta nueva y lee el catálogo que haya ahí. Acá se
replica igual, y se dice **antes** en un aviso permanente arriba del control.

### Dos bugs reales, encontrados con el catálogo del dueño

Verificando la pantalla, un clic mío apuntó la biblioteca a la carpeta real de
la Mac (`V:\Mac Externo\Documents\Aura Library`, 2809 elementos). La app dijo
**"esta carpeta todavía no tiene una biblioteca: empieza vacía"**. Era mentira:

1. **Las fechas de Swift.** `Codable` escribe un `Date` como segundos desde el 1
   de enero de **2001**: `"addedAt" : 808784218.004062`. Un `DateTimeOffset?` no
   lo lee, y el catálogo **entero** se descartaba.
2. **Un número de pista imposible.** Una canción con
   `"trackNumber" : 4294967295` —el máximo sin signo de 32 bits, lo que devuelve
   una etiqueta rota— tampoco cabe en un `int`, y los 2809 elementos se perdían
   por esa sola canción.

**Lo que dejó pasar los dos fue no distinguir "vacía" de "no la pude leer".**
`Load` se tragaba la excepción y devolvía una biblioteca vacía, así que en
pantalla los dos casos se veían idénticos. Ahora hay `TryLoad`, que dice por qué
falló, y la pantalla distingue tres situaciones: vacía, ilegible, y catálogo
bien leído pero con los archivos faltantes.

Es la regla que ST-083 ya había escrito —*"un campo no puede tirar el catálogo
entero"*— incumplida por el propio código que la enunciaba. Con las dos
correcciones el catálogo real se lee completo: **2809 elementos, 1082 álbumes,
634 artistas**.

**Nada se escribió en la biblioteca del dueño** (verificado por fechas de
modificación: ningún archivo tocado después de las 02:00), y la preferencia se
devolvió a la carpeta predeterminada de Windows.

### Verificación

- `dotnet test` → **659/659** · solución ARM64 → **0 errores / 0 advertencias**
- `tools/ImageResizerCheck` → 26/26 · barrido de integridad limpio
- Almacén de credenciales probado contra el Administrador **real**: guardar,
  leer con acentos, reemplazar, borrar, y comprobado con `cmdkey`. La
  credencial de prueba se borró.
- Ajustes visto en pantalla: `docs/capturas/fase3-ajustes-general.png`,
  `fase3-ajustes-biblioteca.png`, `fase3-ajustes-servicios.png`.

### Nota de método

Las capturas se toman con `PrintWindow` (la ventana se dibuja aunque esté
tapada), pero los **clics a ciegas por coordenadas son peligrosos**: uno de
ellos abrió el selector de carpeta y cambió la biblioteca sin que yo lo
pidiera. Fue afortunado —así aparecieron los dos bugs— pero la forma correcta
es la automatización de interfaz por nombre, que además dice si encontró el
control.

## Fase 3 — Biblioteca local, cuarta sesión: la interfaz (2026-09-01)

Decisión formal en `DECISIONS.md` → **ST-085**. La parte de interfaz de la fase:
tabla de Canciones, cuadrículas, arrastrar y soltar, y barra de estado.

### Lo que se hizo (Core, 625/625 tests; ARM64 0/0)

- **`Library/MusicTableColumn`** (+13) y **`Library/MediaTableRow`** (+22) —
  ST-030: grupos de columnas, anchos, migración del menú "+" viejo (D-199), el
  criterio de orden persistible y **un comparador por columna**.
- **`Library/LibraryGrouping`** (+28) — álbumes, artistas, películas y series
  con temporadas, y álbumes de fotos.
- **`Library/LibraryIngest`** (+15) — qué entra al soltar en cada sección.
- **En la app**: `LibraryViewModel` (una sola instancia para todas las
  secciones), `SongsViewModel`, `MediaGridViewModel`, `SongsPage`,
  `MediaGridPage`, `Glyphs`, `FilePickers`, `LibraryProcessor` y
  `PhotoExifReader`. Se eliminó el borrador `LibraryPage`.

### Tres decisiones que conviene conocer

- **Sin el DataGrid del Community Toolkit.** El plan pedía evaluarlo; traería
  una dependencia nueva —con licencia que declarar— para conseguir columnas
  dinámicas, que es lo que un `ListView` con encabezado propio ya da. **Se cede
  redimensionar columnas arrastrando**, y queda anotado como pendiente.
- **Una sola página para las seis cuadrículas.** Lo único que cambia es de dónde
  salen las tarjetas y qué aceptan al soltar.
- **Ordenamiento estable, sin desempate artificial.** Una prueba cazó que el
  primer intento desempataba por título: con un ordenamiento inestable, las tres
  canciones de un mismo álbum se barajan entre sí en cada reordenamiento.

### Lo que faltaba entre importar y ver

`LibraryProcessor` lee las etiquetas, adivina lo que falte del nombre del archivo
y clasifica la imagen por su EXIF. Corre al soltar **y al abrir la app sobre lo
que quedó en cola** — el catálogo guarda como "en cola" lo transitorio y lo
fallido justamente para eso (ST-083), y hasta ahora nada lo reintentaba.

### Verificación: se miró, no solo se compiló

Se generó una biblioteca de prueba con MP3 reales etiquetados y se sembró **por
el mismo camino de ingesta que usa la interfaz**: 12 canciones adentro y el
`cover.jpg` del álbum reconocido como carátula y no como foto — ST-012 sobre
archivos de verdad, no en una prueba unitaria.

Con la app a la vista se corrigieron dos cosas que solo se ven mirando:

1. **El encabezado de la tabla se desplazaba aparte de las filas.** Estaban en
   contenedores distintos, así que los rótulos se despegaban de sus columnas en
   cuanto uno movía la tabla. Ahora comparten un mismo desplazamiento
   horizontal con ancho explícito.
2. **La tabla flotaba en el centro** al sobrar espacio, porque un contenedor con
   ancho explícito se centra por omisión.

También se cambió el encabezado de Favorito por el corazón: "Favorito" no cabe
en sus 34 px y se cortaba en "Favor", que se lee como otra cosa.

Capturas: `docs/capturas/fase3-canciones.png`, `fase3-albumes.png`,
`fase3-artistas.png`, `fase3-artista-detalle.png`.

### Glifos, otra vez verificados renderizándolos

`Resources/Glyphs.cs` junta los nueve códigos de `Segoe Fluent Icons` que usa la
app, **escritos por su número y no como el carácter suelto** — el carácter cae en
el Área de Uso Privado y en el fuente se ve como un cuadrito vacío que cualquier
conversión de codificación corrompe en silencio. Los nueve se dibujaron a un PNG
y se miraron antes de usarlos, por el precedente de `E94A` (que era el signo de
división) en la Fase 1.

### Pendiente de la interfaz de la Fase 3

- **Hoja de edición de metadatos** (`MediaInfoView`/`BatchMediaInfoView`): hoy el
  menú contextual solo marca favorito, muestra en el Explorador y quita de la
  biblioteca.
- **Hoja de revisión de similares**: el detector está en Core (ST-084), sin
  pantalla.
- **Listas de reproducción**: el modelo y el M3U están (ST-084); la sección sigue
  mostrando su aviso de pendiente.
- **Redimensionar columnas** arrastrando el encabezado.
- La duración de un video necesita ffmpeg (Fase 4), así que la categoría
  automática siempre da "Videos"; Series la asigna el usuario (D-228).

## Fase 3 — Biblioteca local, tercera sesión (2026-09-01)

Decisión formal en `DECISIONS.md` → **ST-084**. Cierra la sesión B de la fase:
listas de reproducción, detector de similares y enriquecimiento. Con esto queda
todo el Core de la Fase 3; lo que resta es la interfaz.

### Lo que se hizo (Core, 536/536 tests; ARM64 0/0)

- **Listas M3U8** (`Library/Playlist.cs`, +15) — exportar e importar. El formato
  no es una preferencia de Studio: lo lee `playlist_create()` de Rockbox, que
  acepta rutas UNIX **absolutas** sin tocarlas, y por eso las entradas son
  `/Music/…` con `\n`, no rutas relativas ni `\r\n`. La portada comparte el
  nombre base con el `.m3u8` a través de la misma llamada a `PathSanitizer`,
  porque el firmware la encuentra pelándole la extensión. Al importar, en
  cambio, la tolerancia es amplia a propósito: relativas contra la carpeta del
  archivo, absolutas de Windows, UNC, `file://` y `\r\n` recortado.
- **Colage de la lista** (`Library/PlaylistArtLayout.cs` +11, y el dibujado en
  `App/Platform/PlaylistArtGenerator.cs`) — 2×2 de hasta cuatro carátulas,
  recicladas desde el principio si hay menos; sin ninguna, el glifo de "lista"
  en los grises del firmware.
- **Detector de similares** (`Library/SimilarityText.cs` +31,
  `SimilarItemsDetector.cs` +22) — ST-063. Incluido el caso textual del encargo
  ("01 Amor"/"SodaStereo" contra "Amor"/"Soda-Stereo") y, con el mismo peso, lo
  que **no** debe agrupar.
- **Enriquecimiento** (`Library/LibraryEnricher.cs` +18, `FilenameGuesser` +13)
  — piso de puntaje de MusicBrainz en 70, solo llena huecos, y el orden de
  proveedores de carátula que elige el usuario.

### Un límite conocido que se documentó en vez de corregirse

El detector no compara todos contra todos: agrupa por las 3 primeras letras del
título y del nombre de archivo, y por tamaño exacto. La consecuencia es que la
regla de **"mismo episodio de la misma serie"** —pensada justamente para cuando
los títulos no se parecen— casi nunca alcanza a aplicarse: dos copias del mismo
episodio llamadas `cap1.mkv` y `S01E01.mp4`, de tamaños distintos, nunca llegan
a compararse.

macOS tiene exactamente la misma limitación. Arreglarla solo acá haría que las
dos apps mostraran duplicados **distintos** sobre la misma biblioteca, que es
justo lo que ST-082 se propuso evitar, así que queda una prueba que fija la
conducta real y **corresponde coordinarlo con la app de macOS**.

### Una prueba estaba saliendo a internet

Al armar el enriquecedor con clientes de prueba se inyectaron MusicBrainz, Cover
Art Archive y LRCLIB, pero fanart.tv y Deezer se quedaron con su cliente por
omisión. La prueba de "un proveedor caído no detiene a los de atrás" falló
porque **Deezer devolvió una carátula real descargada de la red**. Corregido
inyectando los cinco. Vale anotarlo porque el modo de falla es traicionero: la
prueba habría "pasado" en cuanto la carátula existiera, dependiendo de la
conexión y del catálogo de un tercero. **Ninguna prueba de este repo debe tocar
la red**; al agregar un cliente nuevo, inyectarlo siempre.

### Verificación

- `dotnet test tests/AuraStudio.Core.Tests` → **536/536** (eran 408).
- `dotnet build AuraStudio.Windows.slnx -p:Platform=ARM64` → **0 errores / 0
  advertencias**.
- `dotnet run --project tools/ImageResizerCheck -c Release` → **26/26** (eran
  14), con los 12 nuevos del colage: cada cuadrante con su carátula y en orden,
  reciclado con menos de cuatro, una carátula 16:9 llenando el cuadrante **sin
  franjas** —que es lo que confirma que WIC recorta *después* de escalar—, el
  tile gris con las tres barras y la más ancha abajo, una carátula ilegible que
  se salta sin dejar un cuadrante negro, y la escritura atómica sin `.tmp`.
- Barrido de integridad (PUA / U+FFFD): limpio.
- **La app no se arrancó**: nada de esta sesión tiene interfaz todavía.

### Pendiente de la Fase 3

Solo la interfaz (sesiones Opus del plan): tabla de Canciones con columnas
configurables (`MusicTableColumn`, ST-030), cuadrículas de
álbumes/artistas/fotos/videos/series/películas, arrastrar y soltar por sección
—cada una ingiere **solo su tipo**, carátulas nunca a Imágenes—, hojas de info y
edición de metadatos, y barra de estado. `FFmpegTranscoder`/`AudioTranscoder` e
`ID3Writer` quedan para la frontera con la Fase 4.

## Fase 3 — Biblioteca local, segunda sesión (2026-09-01)

Decisión formal en `DECISIONS.md` → **ST-083**. Cierra la sesión A de la fase:
catálogo persistido, redimensionado de imágenes y miniaturas. Y paga la deuda de
licencia que ST-082 dejó anotada.

### Lo que se hizo (Core, 408/408 tests; ARM64 0/0)

- **`Library/LibraryItem`** — port de `LibraryItem.swift`: estados de proceso,
  categoría, serie/temporada/episodio, álbum de fotos, `MetadataEditedByUser`.
  `ClassifyKind` delega en `CoverArtAssets` para que importar y decidir "esto es
  carátula" nunca discrepen sobre qué es audio, video o imagen.
- **`Library/LibraryPersistence`** (+15) y **`Library/LibraryStore`** (+11) — el
  catálogo `biblioteca.json` con las cuatro conductas de macOS que importan:
  rutas **relativas** (mover la carpeta a otro disco conserva la biblioteca
  entera; un archivo de fuera guarda su ruta absoluta, que es lo único que
  significa algo ahí), la **portada fuera del JSON** (vive en
  `.portadas/<id>.jpg`), los estados transitorios y fallidos **colapsados a
  `queued`** para que al reabrir se reintente en vez de quedar congelado, y todo
  campo nuevo **anulable** para que su ausencia no descarte el catálogo entero.
- **Se eliminó `Core/LibraryCatalog.cs`**, el esqueleto de la Fase 0. Traía sus
  propios `LibraryItem`/`LibraryItemKind`/`LibraryItemStatus`: dos tipos con el
  mismo nombre para el mismo concepto es cómo se termina con dos conductas según
  quién importe cuál. Sus dos consumidores pasaron al modelo real, y de paso
  `SyncService` dejó de copiar siempre el original — ahora manda lo **preparado**
  cuando existe, que con el esqueleto era imposible de expresar.
- **`Library/ImageResizePlan` + `JpegMarkers`** (+15) y
  **`App/Platform/ImageResizer`** — WIC en vez de ImageIO. Las tres conductas
  que la sesión anterior dejó anotadas como no opcionales están las tres, y las
  tres verificadas de hecho.
- **`Library/CoverThumbnailKey`** (+6) y **`App/Platform/CoverThumbnailCache`** —
  miniaturas con clave por **contenido** (un álbum de 14 pistas comparte una
  sola) y **aspecto real** conservado, que es el bug de distorsión que el dueño
  reportó en macOS.
- **TagLib# declarado en Licencias** — nombre, versión, LGPL v2.1, qué hace y
  dónde está su código. Se comprobó que `TagLibSharp.dll` efectivamente queda
  como archivo aparte junto al ejecutable, que es lo que hace compatible su uso
  con una app cerrada.

### La divergencia que hay que conocer: baseline se verifica, no se fuerza

D-291: el visor del firmware solo decodifica JPEG **baseline**; un progresivo
sale en el iPod como "Formato no soportado". macOS se lo pide explícitamente a
ImageIO. **El codificador JPEG de WIC no expone esa opción.** En vez de confiar,
`JpegMarkers.IsBaseline` lee los marcadores SOF de la salida y el resizer falla
si no es baseline: si algún día WIC cambiara, se sabe acá y no en la pantalla del
iPod. Se comprobó que hoy la salida real de WIC **sí** es baseline.

### Verificación

- `dotnet test tests/AuraStudio.Core.Tests` → **408/408** (eran 350).
- `dotnet build AuraStudio.App -p:Platform=ARM64` → **0 errores / 0 advertencias**.
- `dotnet run --project tools/ImageResizerCheck -c Release` → **14/14**, contra
  WIC de verdad: 1600×1200 → 320×240 y 3200×2400 → 640×480 conservando aspecto,
  100×80 **no** se agranda, salida **baseline**, la mitad transparente de un PNG
  queda **blanca** (B=255 G=255 R=255) y la opaca intacta, una foto con
  orientación EXIF 6 llega **derecha** (400×200 → 160×320), basura rechazada con
  mensaje claro, una carátula 16:9 da miniatura 96×54 y **no** 96×96, la misma
  carátula en dos canciones devuelve **la misma instancia**, y una carátula
  ilegible da celda sin imagen en vez de tumbar la cuadrícula.
- Barrido de integridad (PUA / U+FFFD) sobre `.cs`/`.xaml`/`.md`/`.ps1`/
  `.csproj`/`.slnx`: limpio.
- **La app no se arrancó en esta sesión**: nada de lo hecho tiene interfaz
  todavía. La `LibraryPage` que existe sigue siendo el borrador fuera de la
  navegación; se le corrigieron los enlaces rotos que dejó el cambio de modelo
  (`DisplayName` ya no existe) y ahora muestra tipo y estado **en español** en
  vez del nombre del enum, pero se reemplaza entera cuando se construya la
  interfaz de la fase.

### Por qué hay un verificador fuera de las pruebas

`tools/ImageResizerCheck` no está en la solución y se corre a mano. Lo que hay
que comprobar del redimensionado depende de **WIC**, que solo existe bajo un TFM
de Windows, y `AuraStudio.Core.Tests` apunta a `net10.0` puro a propósito —ahí
viven las reglas portadas, sin plataforma—. El verificador compila el mismo
archivo fuente del resizer sin arrastrar WinUI y genera sus propias imágenes.
**Correrlo es obligatorio al tocar el redimensionado o las miniaturas**; las
partes puras (tamaño destino, marcadores, clave de miniatura) sí están en las
pruebas normales.

### Pendiente de la Fase 3

- ~~`LibraryEnricher`, `SimilarItemsDetector`, playlists (importar/exportar
  M3U, `Playlist`)~~ — **hecho en la tercera sesión** (ST-084). Sigue
  `MusicTableColumn` y **toda la interfaz**: tabla de Canciones con columnas
  configurables (ST-030), cuadrículas, arrastrar y soltar por sección, hojas de
  metadata, barra de estado.
- `FFmpegTranscoder`/`AudioTranscoder` (ffmpeg se localiza en el sistema,
  ST-082) e `ID3Writer`.

## Fase 3 — Biblioteca local, primera sesión (2026-08-31)

Decisión formal en `DECISIONS.md` → **ST-082**. Cubre el arranque de la fase:
las tres decisiones que el plan pide cerrar con el dueño, y el primer bloque de
Core (modelos + lectura de etiquetas).

### Decisiones cerradas

- **Etiquetas: TagLib#** · **Imágenes: `Windows.Graphics.Imaging`** ·
  **ffmpeg: se busca en el sistema** (igual que D-038 en macOS).
- El dueño pidió "igual que macOS, para no generar inconsistencias". Literalmente
  no se puede —allá lo hacen AVFoundation e ImageIO, que no existen acá—, así
  que se tomó como **mismos resultados, no misma API**, y con ese criterio esas
  son las opciones que menos divergen. El razonamiento completo, en ST-082.

### Lo que se hizo (Core, 350/350 tests)

- **`Library/TrackMetadata`** — port de `TrackMetadata.swift`, mismos campos.
- **`Library/TrackTagRules`** (+18 casos) — **acá vive la equivalencia con
  macOS**, no en la librería: año como prefijo de 4 (y una cadena más corta se
  conserva tal cual), `"3/12"` → pista 3, átomos `trkn`/`disk` de iTunes, y el
  "primero que llega gana" del `??` de Swift, sin el cual el orden en que la
  librería entrega las etiquetas cambiaría el resultado.
- **`Library/CoverArtAssets`** (+26 casos) — ST-012: las carátulas son assets de
  Música/Video, **nunca** entradas de Imágenes. Incluida la regla que más fácil
  se rompe: soltar una imagen a propósito en Fotos **gana** sobre su nombre de
  carátula, salvo que en disco conviva con audio.
- **`Library/LocalTagReader`** (+11 casos) — probado **de punta a punta contra
  MP3 reales** construidos en el momento (tramas MPEG-1 Layer III válidas,
  etiquetadas y releídas), no solo contra las reglas puras. Nunca lanza: un
  archivo corrupto devuelve metadata vacía en vez de tumbar la importación de
  una carpeta entera.

### Pendiente de la propia Fase 3 (no de la 7)

- ~~**Declarar TagLib# en la pantalla de Licencias.**~~ **Hecho en la segunda
  sesión** (ST-083). Es LGPL enlazada dinámicamente —compatible con una app
  cerrada— pero hay que declararla: una dependencia LGPL sin declarar es justo
  el tipo de deuda que este proyecto no deja correr.
- ~~`LibraryItem`/`LibraryPersistence`, el redimensionador y las
  miniaturas~~ — **hecho en la segunda sesión**. Sigue el resto: playlists,
  `SimilarItemsDetector`, `LibraryEnricher`, y toda la interfaz.
- Del `ImageResizer` de macOS hay tres conductas que **no** son opcionales al
  portarlo, y conviene tenerlas anotadas antes de escribirlo: preservar aspecto
  sin agrandar; **aplanar sobre blanco antes de codificar** (si no, lo
  transparente de un PNG sale con RGB indefinido, casi siempre negro); y
  **forzar JPEG baseline** — D-291: el visor del firmware no decodifica
  progresivo y lo muestra como "Formato no soportado".

## Fase 2 — Instalador DFU, segunda sesión (2026-08-31)

Decisión formal en `DECISIONS.md` → **ST-081**. Cierra los puntos 3, 4 y 5 del
plan: la cadena de ejecución privilegiada, el formateo, el asistente y la guía
del controlador de DFU.

### Lo que se hizo

- **Cadena privilegiada completa.** `IPrivilegedRunner`/`PrivilegedRunner` (lado
  no elevado) relanza **la propia app** con `runas` y le pasa la petición por
  archivo; `PrivilegedHost` (lado elevado) la vuelve a validar, **re-verifica el
  disco contra el hardware** y ejecuta. Punto de entrada propio (`Program.cs`,
  `DISABLE_XAML_GENERATED_MAIN`) para poder interceptar el modo elevado antes de
  abrir ninguna ventana. Bitácora en
  `%LOCALAPPDATA%\Aura Studio\operaciones-privilegiadas.log`.
- **Formateo FAT32.** `diskpart clean` (sin particiones no hay volumen montado,
  así que las escrituras directas al disco no quedan bloqueadas), después la
  tabla MBR con el tipo 0x0C que el bootloader espera leer (D-190) y las
  estructuras FAT32. `MasterBootRecord` es puro y tiene 16 casos.
- **Modo ensayo** (`DryRun`): hace todas las comprobaciones y devuelve el plan
  real sin escribir un byte. El asistente **obliga** a ensayar antes de ofrecer
  el formateo de verdad. No es una comodidad: es cómo se valida esta cadena sin
  arriesgar un disco, dado que no se pudo probar contra un iPod.
- **Asistente completo** siguiendo `InstallerStep`: bienvenida con el aviso de
  que borra todo, pantalla de permisos **antes** de cualquier diálogo del
  sistema, confirmación del disco con nombre/unidad/capacidad/bus/firmware,
  preparación, DFU con guía del controlador, grabado y cierre.
- **Aviso de cambio de familia** (ST-046/ST-056): si el iPod tiene una familia
  distinta de la que se va a instalar, se dice en pantalla que la saliente se
  guarda entera y se puede volver a ella.
- **Servicio de Apple** pausado durante el grabado y reanudado pase lo que pase
  (equivalente del pausado de agentes AMP de macOS, D-191).
- **16 casos nuevos para `FirmwareSwitcher`**, que llegó sin ninguno: es el
  código que sostiene la promesa "se guarda completo, con sus ajustes".

### Verificación

- `dotnet build studio/windows -p:Platform=ARM64` → **0 errores / 0 warnings**.
- `dotnet test tests/AuraStudio.Core.Tests` → **264/264**.
- **La cadena privilegiada se ejercitó de punta a punta sin elevación y sin
  tocar ningún disco**, invocando el ejecutable con el argumento del modo
  elevado. Los tres guardas dispararon como deben:
  - disco inexistente → `SafetyAbort: "el disco 97 ya no existe"`;
  - petición sin tamaño esperado → `SafetyAbort` (no se puede re-verificar);
  - **el SSD del sistema (disco 0) → `SafetyAbort: "el disco ya no aparece
    conectado por USB (bus IDE)"`**, con la bitácora del disco real. Es la
    comprobación que importa: pedirle formatear el disco de arranque y que se
    niegue.
  En los tres casos: ninguna ventana, código de salida correcto, resultado JSON
  escrito.
- **Asistente verificado en pantalla con el iPod del dueño conectado**
  (`docs/capturas/fase2-permisos.png`, `fase2-confirmar-disco.png`): la pantalla
  de permisos cumple la promesa de macOS ("nunca vas a tener que abrir una
  consola"), y la confirmación del disco mostró datos reales — `E:\`, 125.0 GB,
  USB — **y detectó moonlit.aura**, lo que disparó correctamente el aviso de
  cambio de familia.

### Lo que esto resolvió de la sesión anterior

El "bloqueo de biblioteca que no aparecía" **no era un defecto**: ese iPod tiene
moonlit.aura instalado, habla el contrato, y la biblioteca debe quedar abierta.
Confirmado contra hardware real; la nota de la sesión 1 quedó corregida.

### Apéndice: P0 de seguridad — se podía formatear el iPod sin querer

**El dueño ejecutó dos formateos reales creyendo que solo estaba probando el
software.** Verificado en la bitácora: cuatro pares ensayo→real esa noche, cada
real entre 3 y 11 segundos después de su ensayo. El disco era sacrificable y no
hubo pérdida; en el iPod de un usuario habría sido su biblioteca. Viola la regla
central del repo: la confirmación explícita tiene que hacer **imposible**
formatear sin saberlo.

**Era un defecto de mi diseño, y de un tipo concreto: confundir una comprobación
técnica con un permiso.** El asistente exigía que un ensayo previo hubiera
pasado antes de ofrecer el formateo real, y trataba eso como suficiente. Tras el
ensayo aparecía **un único botón, con estilo de acento, justo donde había
quedado el clic anterior**, y decía "Dar formato ahora". Tenía la forma exacta de
un "Continuar". Peor: al flasheo sí le había puesto una casilla de confirmación
explícita, y al formateo no — el mismo criterio aplicado de forma desigual en el
mismo archivo.

**Corrección.**

- **El ensayo ya no autoriza.** Cada formateo real exige una casilla marcada
  para **esa** ejecución.
- **El permiso se consume.** Tras formatear vuelve a cero: un segundo formateo
  necesita confirmación nueva. Los dos del incidente estuvieron a 19 s.
- **Cambiar de dispositivo tira todo** — ensayo y permiso: el ensayo se hizo
  sobre otra geometría y el usuario confirmó sobre otro nombre.
- **El botón nombra el disco**: "Borrar y formatear IPOD (E:\) · 116.25 GB · USB"
  en vez de "Dar formato ahora", y **no lleva el estilo de acento**: la acción
  destructiva no puede parecer el siguiente paso natural.
- **El disco se re-enuncia junto al botón**, no solo en la pantalla anterior: en
  el momento del clic destructivo hay que estar viendo sobre qué actúa.
- El bloque destructivo está **separado** del resultado del ensayo, que ahora
  encabeza con "Ensayo terminado — no se tocó el disco".
- El flasheo tenía el mismo defecto de reuso (`FlashConfirmedByUser` quedaba en
  `true` tras usarse): también se consume ahora.

**Guarda automática, que es lo que faltaba.** La regla se movió a Core como
`DestructiveActionGate` (objetivo + comprobación + consentimiento, con consumo)
y tiene **10 casos** que fijan justamente lo que salió mal: que una comprobación
no es permiso, que el permiso no se hereda entre ejecuciones, y que cambiar de
objetivo lo invalida todo. El ViewModel usa esa compuerta, así que la regla
probada es la que corre.

**No verificado en pantalla.** Para llegar al bloque destructivo hace falta un
ensayo, y el ensayo pide UAC — que nadie puede aprobar desde esta sesión. La
regla sí está verificada por las pruebas; el aspecto de la pantalla lo tiene que
mirar el dueño en la próxima pasada con hardware.

### Apéndice: punto 10 — guía de DFU y reconocimiento automático

Encargo del dueño agregado al plan con la fase en vuelo.

- **Instrucciones exactas, y el "cuándo".** El paso de DFU dice que **este** es
  el momento (disco listo, lo que sigue es grabar) y lista los cuatro pasos
  tomados de `EnterDFUView.swift` de macOS —que a su vez salen del README de
  `mks5lboot`—: detener la reproducción, mantener **SELECT + MENU**, seguir unos
  **12 segundos** hasta después de que la pantalla se ponga negra, y soltar. No
  se inventó ninguno; lo único que cambió es el español (el original está en
  voseo y el repo pide español de México sin voseo).
- **El aviso de tiempo va aparte**, en una `InfoBar`, no como una línea más de
  la lista: soltar en cuanto la pantalla se apaga es el error más común y
  reinicia el iPod sin entrar en DFU.
- **La guía del firmware se enlaza, no se copia** (contrato §G):
  `guia-flasheo-restauracion.md` vive solo en `Aura-Firmware`.
- **Reconocimiento automático.** Al llegar un dispositivo por USB y al abrir el
  instalador se mira si hay un iPod en DFU: primero la consulta barata a WMI
  (¿hay algún aparato de Apple que no sea el iPod en modo disco?) y solo
  entonces `--dfuscan`, para no lanzar un proceso en cada evento de USB. Si lo
  hay, **se pregunta** y se ofrecen las familias que de verdad se pueden
  instalar (`AvailableFamilies`: las que tienen artefactos que pasan la
  verificación, nunca una lista que después falle). Si el usuario dice "ahora
  no", no se vuelve a preguntar hasta que el iPod salga y entre otra vez en DFU.
- **Sin driver de Apple, se explica** en vez de quedarse mudo.
- **Guard de D-185 heredado.** `InstallerFlowRegistry` (Core, 7 casos) es el
  punto único de verdad: el reconocimiento automático **jamás** enciende la
  pregunta con un flujo activo, y por debajo hay un candado de escritura para
  que solo un flujo pueda tocar el disco aunque dos llegaran a coexistir. En
  macOS esa lección costó una instalación abortada: dos instaladores extrayendo
  el árbol a la vez sobre el mismo volumen.

**No verificado en pantalla:** el paso de DFU en sí. Solo se llega a él tras un
formateo real o con un iPod ya en DFU, y ninguna de las dos cosas se puede
provocar desde acá sin tocar el aparato del dueño. Forma parte de la validación
de DFU que ya está en el checklist.

### Apéndice: el formateo real falló en hardware — corregido

Validación con el iPod Classic de 116 GB (sesión supervisora). **El ensayo pasó
limpio** en 2 s: UAC, paso de la petición, re-verificación del disco y geometría,
todo correcto. **El formateo real falló**: `No se pudo escribir en el disco:
Access to the path '\\.\PhysicalDrive1' is denied`. El disco quedó **intacto**
(exFAT montado en `E:`).

**Causa real, y no era la obvia.** El diseño ya contemplaba el problema —
`diskpart clean` primero, para que no quedara ningún volumen montado— pero el
código **solo miraba el código de salida de diskpart**, y diskpart **sale con 0
aunque un comando de su script falle**. El `clean` no limpió nada, el código lo
dio por bueno, y la escritura chocó contra la regla de Windows que rechaza
escribir en sectores cubiertos por un volumen montado. Que el disco quedara
intacto es justamente la prueba: si `clean` hubiera corrido, no habría quedado
exFAT.

**Corrección.**

- **Fuera `diskpart`.** Una herramienta cuyo código de salida miente no sirve
  como paso previo de algo destructivo. Lo que hacía `clean` se hace ahora
  directamente: poner en cero el primer y el último MiB del disco (donde viven
  la tabla, los restos de GPT y su copia de respaldo) y escribir la tabla nueva.
- **Bloqueo y desmontaje de volúmenes** (`Platform/VolumeLock.cs`, nuevo): antes
  de escribir se toman **todos** los volúmenes del disco con
  `FSCTL_LOCK_VOLUME` + `FSCTL_DISMOUNT_VOLUME` y **se sostienen los handles**
  durante toda la operación — mientras el bloqueo vive, Windows no vuelve a
  montar y las escrituras pasan. Se enumeran por sus **extensiones reales**
  (`IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS`), no por letra: un volumen sin letra
  bloquea igual. El bloqueo reintenta 10 veces (el Explorador suele soltar solo)
  y, si falla, se sueltan los ya tomados en vez de dejar el disco inutilizable.
- **Relectura de comprobación.** Terminada la escritura se relee del disco la
  tabla y el sector de arranque FAT32 y se comprueban; si no cuadran, se reporta
  fallo en vez de éxito. **Es la lección general del bug**: no volver a dar por
  hecho que un paso destructivo funcionó porque una herramienta dijo que sí.
- **El ensayo ahora lista** qué volúmenes se bloquearían, sin bloquearlos —
  desmontar el iPod en un ensayo sería un efecto que el usuario no pidió.
- Menor privilegio: preguntar dónde vive un volumen se hace con handle de acceso
  cero; el acceso de escritura se pide solo para bloquear.

**Verificado.** Build 0/0, 264/264, y los tres guardas de seguridad siguen
firmes (disco inexistente, petición sin tamaño, y el SSD del sistema rechazado
por bus IDE). Las constantes Win32 y el parseo de extensiones se validaron
aparte contra los discos reales de esta máquina: 4 volúmenes reportan disco 0 y
**uno reporta disco 1** — el iPod, exactamente el volumen montado que bloqueaba
la escritura y que el código nuevo va a bloquear. Se corrigió además un fallo
latente en la enumeración (cortar el nombre en el primer nulo en vez de recortar
los del final: la API no limpia el resto del búfer).

**Lo que sigue sin verificarse: el formateo real.** Nadie ha formateado un disco
con este código todavía. La corrección es estructural y sus piezas están
validadas por separado, pero el camino completo necesita otra pasada con el iPod.

### Apéndice: P0 — la app no abría con un disco USB en mal estado

Reportado por la sesión supervisora con stack capturado (`dotnet-stack` sobre
una instancia colgada), reproducido 3 veces con el iPod a medio morir en el
passthrough de Parallels (`E:` registrada, `IsReady = False`).

**Qué pasaba.** `UsbDeviceWatcher` enumeraba discos por WMI **en su
constructor**. Al resolverlo la DI desde el constructor de `MainWindow`, esa
enumeración corría en el hilo de UI *antes* de `window.Activate()`: el proveedor
de discos de WMI se atoraba con el disco enfermo, `MoveNext()` se bloqueaba en
código nativo, y la ventana quedaba creada con la geometría correcta y **oculta
para siempre**. Mientras el proceso siguiera vivo, WMI quedaba atorado para todo
el sistema — hasta un `Get-CimInstance` externo se colgaba.

**Corrección** (cuatro capas, porque una sola no alcanza):

1. **Constructor trivial.** `UsbDeviceWatcher` ya no consulta nada al
   construirse; `DeviceSessionService` tampoco dispara sondeos y arranca en
   estado `Detecting`.
2. **Primer sondeo después de `Activate()`.** Lo pide la ventana desde su evento
   `Activated` (`StartInitialScan`, idempotente), en el pool de hilos.
3. **Plazo dentro de WMI.** Todas las consultas de `WmiDiskEnumerator` llevan
   `EnumerationOptions` con `Timeout` de 5 s, `ReturnImmediately = true` y
   `Rewindable = false` — es la combinación con la que WMI respeta el plazo y
   lanza en vez de esperar. Es la corrección en la raíz.
4. **Presupuesto externo** de 12 s en `RefreshAsync` como red de seguridad: si
   la consulta se atora igual, el sondeo se abandona y se reporta "no
   encontrado". El hilo del pool queda perdido, pero la app sigue viva.

Además, la interfaz ahora distingue **"todavía no busqué"** de **"busqué y no
hay nada"** (`HasScanned` + estado `Detecting`): arrancar afirmando que no hay
iPod antes de haber mirado es mentirle al usuario.

**Verificado.** Build 0/0, 264/264, y la ventana aparece **a los 0.8 s** del
arranque con el icono ya puesto (`docs/capturas/fase2-arranque.png`). Lo que
**no** se pudo verificar es la reproducción del cuelgue: hace falta el disco en
mal estado, que no se puede provocar a voluntad. La corrección es estructural
(no hay E/S de dispositivos en el camino de arranque) más los dos plazos, no un
parche al síntoma.

**Sin guarda automática.** No hay test que impida reintroducirlo: el watcher y
el enumerador viven en el proyecto de la app, que no tiene suite propia, y
"colgarse en un driver" no se simula en una prueba unitaria. La defensa es la
regla nueva de `ARQUITECTURA.md` ("nada de E/S de dispositivos en constructores
ni antes de `Activate()`") y revisarla al leer un diff que agregue un servicio.

### Apéndice: icono de la app (punto 8, agregado con la sesión ya en vuelo)

El dueño entregó el master en `studio/windows/icono/Aura icono.png` (rueda de
iPod, 1088×1088, 32 bpp con alfa). Ese PNG es la **fuente única**: no se edita
ni se mueve.

- **`scripts/Make-Icon.ps1`** (nuevo) lo lee y regenera
  `AuraStudio.App/Assets/AuraStudio.ico` completo: 256 px como PNG comprimido y
  64/48/32/24/20/16 como BMP de 32 bpp, con interpolación `HighQualityBicubic`.
  System.Drawing no sabe escribir un `.ico` multi-tamaño, así que el contenedor
  se arma byte a byte en el script (cabecera + una entrada por tamaño + datos).
  Reproducible: si el icono cambia, cambia el master y se vuelve a correr —
  nada de conversiones a mano. Tiene `-WhatIfOnly` para ver qué haría.
- **Cableado**: `<ApplicationIcon>` en el csproj (lo que muestra el Explorador
  para el `.exe`) y `AppWindow.SetIcon(...)` en `MainWindow` (barra de título y
  de tareas), con el `.ico` copiado a la salida del build. Si el archivo no
  está, la ventana usa el icono por omisión: un icono es una mejora, nunca un
  motivo para no abrir.
- **Verificado**: las 7 entradas están en el `.ico` y Windows devuelve cada
  tamaño pedido; la barra de título muestra la rueda
  (`docs/capturas/fase2-icono-titulo.png`) y el icono asociado al `.exe` también
  (`fase2-icono-exe.png`). La barra de tareas usa el mismo icono de ventana que
  la barra de título, pero **no se capturó por separado**.
- **Legibilidad en tamaños chicos** (`fase2-icono-tamanos.png`): a 64 y 48 px se
  lee todo — "AURA", los glifos de transporte y el botón central. A 32 px el
  texto "AURA" ya se empasta pero la rueda sigue leyéndose. **A 24, 20 y 16 px
  queda solo el anillo azul con el punto claro del centro**: el detalle interior
  se pierde entero. Sigue siendo una silueta distinguible, pero es una decisión
  visual del dueño si eso alcanza o si el icono necesita una variante
  simplificada para tamaños chicos. **No se rediseñó nada** (ver pendientes).
- Los assets de MSIX (Square44x44, Square150x150, StoreLogo…) **no** salen de
  acá: se derivan del mismo master en la Fase 7 (empaquetado).

### Pendiente con el dueño (además de lo de la sesión 1)

1. ~~**Correr el ensayo del formateo.**~~ **Hecho y pasó** (iPod de 116 GB, 2 s:
   UAC, petición, re-verificación y geometría). El **formateo real falló** por
   el bug de `diskpart`, ya corregido — ver el apéndice de arriba.
2. ~~**Repetir el formateo real.**~~ **Hecho y funcionó** (dos ciclos). Tras
   reiniciar el iPod, la partición MBR 0x0C en el offset de 1 MiB, 116.25 GB,
   **monta como FAT32 sano con etiqueta IPOD**, y el servicio AMDS de Apple
   escribió encima una estructura completa de iPod (`iPod_Control\`,
   `iTunes\iTunesDB`, `Music\F00–F49`): software de terceros aceptó y usó el
   sistema de archivos de `Fat32Formatter` para escritura real. Checklist:
   ensayo ✓, formateo real >32 GB ✓, MBR 0x0C ✓, FAT32 montable ✓.
   **Pendiente ahora:** revisar en pantalla el bloque de confirmación nuevo del
   formateo (ver el apéndice del P0 de seguridad) antes de volver a usarlo.
3. **El grabado por DFU sigue sin ejecutarse nunca.** No lo uses sobre un iPod
   con música que no tengas copiada.
4. **Revisión visual del icono a 16–24 px.** El detalle de la rueda se pierde a
   esos tamaños (queda el anillo con el punto central). Decides tú si alcanza o
   si quieres una variante simplificada para tamaños chicos; en ese caso
   entregas otro master y `Make-Icon.ps1` la vuelve a generar. No se rediseñó
   nada por cuenta propia.

## Fase 2 — Instalador DFU y Licencias, primera sesión (2026-08-31)

Decisión formal en `DECISIONS.md` → **ST-080**. Cubre los puntos 1, 2 y 6 del
plan completos, y la parte de 3 y 4 que no necesita elevación ni el iPod.

### Colisión de sesiones

Una segunda sesión ejecutora arrancó esta misma fase en paralelo por error y se
retiró. Sobreescribió con `git checkout --` un archivo en curso de esta sesión
(`FirmwareArtifacts.cs`, restaurado) y dejó 13 archivos en
`AuraStudio.Core/Installer/`. Se reconcilió a **un solo modelo por concepto**:

- **Conservado de ese trabajo:** `Fat32Formatter`, `FirmwareTreeWriter`,
  `FirmwareSwitcher`, `InstallerError`, `InstallerStep`, `PrivilegedOperation`.
- **Descartado por duplicado** (los de esta sesión ya tenían pruebas y estaban
  integrados): sus `InstallPlanner`, `InstallManifest`, `AuraUpdateChecker`,
  `BundledArtifacts`.
- **Descartado y avisado a la sesión supervisora** para que lo conserve si lo
  quiere: la cadena de descarga ST-077 (`FirmwareReleaseDownloader`,
  `ReleaseCache`, `FirmwareVersionResolver`). Colgaba del `BundledArtifacts`
  duplicado, no tenía pruebas ni cableado, y acá no se puede ejercitar: `gh` no
  está instalado, los repos son privados y el almacén de credenciales es de la
  Fase 6. `FirmwareArtifacts.Load(directorio, familia)` ya acepta artefactos de
  cualquier directorio, que es lo único que esa cadena necesita del modelo.

### Lo que se hizo

- **Core, con pruebas (216/216, +87 en esta fase):** `InstallManifest` (v11),
  `InstallPlanner` (ST-017), `FirmwareArtifacts`/`FirmwareArtifactVerifier`,
  `AuraUpdateChecker`, `Mks5lbootOutput`, y **16 pruebas nuevas para el
  `Fat32Formatter` heredado**, que llegó sin ninguna.
- **Bug real corregido:** `DfuFlashRunner.ScanAsync` decidía "hay iPod en DFU"
  con `Output.Contains("DFU")` — y el mensaje de "no hay dispositivo"
  (`no DFU devices found`) también contiene "DFU". Ahora lee el estado
  (`DFU device state: N`), como macOS. El runner soporta además `--single` y
  `--bl-uninst`, que faltaban.
- **`FirmwareTreeInstaller` reescrito** sobre `FirmwareTreeWriter`: se acabó el
  staging dentro de `/.aura/` del iPod y la extracción completa sin delta.
- **Pantalla de Licencias** (contrato §B) en Ajustes › Acerca de, verificada en
  ejecución: `docs/capturas/fase2-licencias.png`.
- **`artifacts/` se copia a la salida del build** (regla nueva en el csproj):
  antes la app compilada no encontraba ningún artefacto.
- **Confirmación explícita antes de flashear**: `InstallerViewModel.FlashAsync`
  se rehúsa sin `FlashConfirmedByUser`. Ningún camino de código graba el
  bootloader sin que el usuario haya confirmado en pantalla.

### Hallazgos que cambian el plan

1. **El camino de formateo del plan no podía funcionar.** El punto 3 daba por
   hecho `Format-Volume`/`diskpart`; ninguno sirve para un iPod de 125 GB. Hay
   **dos límites distintos, y conviene no fundirlos**: `FormatEx` (el motor de
   ambos) se niega a crear FAT32 de más de 32 GB, y por separado `format /?` en
   esta VM documenta un límite por cuenta de clústeres
   (65 526 < N < 4 177 918) que con la unidad máxima de 32 KB da un techo de
   ~127 GB. **Ninguno de los dos está verificado en hardware acá** (esta sesión
   no tiene elevación). Por eso se conserva `Fat32Formatter`, que escribe las
   estructuras FAT32 según la especificación pública de Microsoft.
2. **La guía WinUSB del punto 4 no aplica.** `mks5lboot.exe` no usa libusb ni
   WinUSB: importa `setupapi.dll` y abre el dispositivo por `GUID_AAPLDFU` — la
   interfaz del **driver de Apple**. O está ese driver, o no hay flasheo.
3. **`mks5lboot.exe` es x86 de 32 bits** (corre por emulación en ARM64) y
   reporta versión `fdf5be4e8fM-260831`: un git describe con `M`, o sea que se
   compiló de un árbol del firmware **con cambios sin commitear**.

### Verificación (compuertas)

- `dotnet build studio/windows -p:Platform=ARM64` → **0 errores / 0 warnings**.
- `dotnet test tests/AuraStudio.Core.Tests` → **216/216**.
- Pantalla de Licencias verificada en ejecución con captura. Hoy muestra
  "Versión incluida: No se conoce" y los documentos como no incluidos — que es
  **correcto**: `artifacts/` solo tiene `mks5lboot.exe`, sin ningún Release.

### Fuera de alcance detectado (no se tocó)

- Con el iPod del dueño conectado un momento durante esta sesión (modo disco de
  Apple), la barra de navegación **no mostró el bloqueo de biblioteca** y se
  anotó como posible defecto. **Resuelto en la sesión 2: no era un defecto.**
  Ese iPod tiene **moonlit.aura** instalado, así que `SupportsAuraContract` es
  `true` — habla el contrato aunque el USB lo atienda el firmware de Apple — y
  la biblioteca debe quedar abierta. Es exactamente el caso que la corrección de
  la Fase 1 introdujo, confirmado contra hardware real. Se corrigió igual una
  brecha real detectada por lectura: las **subsecciones** de Música/Video/Fotos
  no tenían `IsEnabled` propio, así que un grupo deshabilitado dejaba sus hijos
  clicables.

### Pendiente con el dueño

1. **`mks5lboot.exe`: decisión de procedencia (bloquea la validez de la oferta
   GPL §3).** El Release publica `mks5lboot` de Unix; Windows necesita un
   `.exe`. Las opciones son (a) que el firmware publique `mks5lboot.exe` como
   asset — cambio de §A, se coordina con `Aura-Firmware` — o (b) que
   Studio-Windows versione el suyo con procedencia real. **En cualquiera de las
   dos, el binario actual hay que rehacerlo**: se compiló de un árbol con
   cambios sin commitear (`M` en `fdf5be4e8fM-260831`), así que hoy no existe
   una fuente publicada que corresponda exactamente a lo que se distribuiría.
   Hasta que se decida, la app lo declara como "hash fijado localmente" y lo
   dice en Licencias.
2. **Poblar `artifacts/` con un Release de verdad.** `gh` no está instalado en
   la VM, así que `scripts/FirmwareFetch.ps1` no corre. Sin eso no hay
   `rockbox.zip`, `rockbox.ipod`, `bootloader-ipod6g.ipod` ni `checksums.txt`, y
   por lo tanto **nada del instalador se puede probar de extremo a extremo**, ni
   la pantalla de Licencias puede citar una versión. Es la precondición de todo
   lo demás de la Fase 2.
3. **Verificar los dos límites de FAT32 en hardware** y, con eso, si hace falta
   `Fat32Formatter` o alcanza con la herramienta del sistema. Requiere elevación
   y un disco grande (sirve un VHD de más de 32 GB; no hace falta el iPod).
4. **Driver de DFU**: confirmar que el paquete de Apple existe **para ARM64** en
   esta VM y que `mks5lboot.exe --dfuscan` ve el iPod en DFU. Es el riesgo #1
   del plan y no se puede simular.
5. ~~**Bloqueo de biblioteca con un iPod que no habla el contrato**~~ —
   **CONFIRMADO en pantalla** por la sesión supervisora: con el iPod ya sin
   moonlit (una restauración de Apple interrumpida lo dejó RAW y Windows lo
   reformateó exFAT), se vio la detección "iPod Classic (E:\) - Apple", la
   `InfoBar` de biblioteca bloqueada y las secciones deshabilitadas. Cerrado.

## Fase 1 — Cimientos de la app: sesión, navegación, tema (2026-08-31)

Decisión formal en `DECISIONS.md` → **ST-079**. Convenciones nuevas en
`docs/ARQUITECTURA.md` (secciones "Estado de sesión del dispositivo",
"Ventana, respaldo y tema", "Strings es-MX" y las reglas de Fluent).

### Lo que se hizo

- **`Services/DeviceSessionService`** (singleton) — única fuente del estado
  del dispositivo. `MainViewModel`, que hacía de sesión improvisada, se
  eliminó; `DeviceListViewModel`, `SyncViewModel`, `InstallerViewModel` y el
  nuevo `ShellViewModel` consumen de la sesión. `DeviceSafetyValidator` se
  dejó a propósito yendo directo al watcher (re-verificación antes de
  operación destructiva: no puede confiar en caché).
- **`AuraStudio.Core/InstalledFirmware.cs`** — el hecho que faltaba: qué
  firmware hay en el disco. Con él, `IPodDiskInfo.SupportsAuraContract` (y
  `IsAuraFirmware`, `RockboxFamilyVerified`, `IsDualBoot`,
  `ThemeFormatSupported`) reemplaza a `IsAura`, que negaba el contrato a un
  iPod con Aura conectado en modo disco de Apple.
- **`MainWindow`** reducido a lo propio de una ventana; la UI pasó a
  `Views/ShellPage`. Mica con degradación, tema con anulación en Ajustes
  (barra de título incluida), geometría persistida con validación de pantalla.
- **`Services/AppPreferences`** (JSON en `%LOCALAPPDATA%`), **`VolumeService`**
  (interfaz sobre `Platform/VolumeManager`, para sacar `Platform/` de los
  ViewModels), **`Converters/BoolToVisibilityConverter`** (para que los
  ViewModels no publiquen `Visibility`).
- **`Resources/AuraPalette.xaml`** (transcripción de `AuraPalette.swift`, tres
  temas) + **`Resources/Styles.xaml`** reescrito con tokens de espaciado,
  tipografía y superficies. Se retiraron los colores inventados que había
  (`#007AFF`, `#5856D6`, …, "replicados de apps/aura/" sin serlo) y la
  plantilla propia del botón principal, que hardcodeaba `Foreground="White"`.
- **`Resources/AppStrings.cs`** — tabla única de texto (decisión: clase
  estática, no `.resw`; razonamiento en ST-079 y en la propia clase).
- **`Views/ShellPage`** con la navegación definitiva y **`Views/PlaceholderPage`**
  para las secciones que aún no existen (dice cuál es y en qué fase llega).
  **`Views/SettingsPage`** dejó de ser placeholder: tema + "Acerca de".
  **`Views/DeviceListPage`** reescrita con estados vacío/ambiguo.

### Verificación (compuertas de la fase)

- `dotnet build studio/windows -p:Platform=ARM64` → **0 errores / 0 warnings**.
- `dotnet test tests/AuraStudio.Core.Tests` → **129/129** (110 previos + 19
  nuevos en `FirmwareTreeProbeTests`).
- **Verificado en pantalla**, no solo "arrancó": se lanzó el `.exe` ARM64 y se
  capturó la ventana (`docs/capturas/fase1-*.png`). Comprobado a ojo — Mica
  activo (el fondo del escritorio tiñe la ventana), navegación completa con
  los tres grupos expandidos y sus subsecciones, tema claro siguiendo al
  sistema, cambio a **Oscuro** desde Ajustes aplicándose **en vivo**
  (contenido y barra de título) y quedando escrito en `preferences.json`,
  `PlaceholderPage` mostrando su texto honesto, y la ventana
  movida/redimensionada restaurándose exacta (`220,90 1020x720`) al volver a
  abrir.
- **Método para verificar glifos** (que esta fase tuvo que inventar y conviene
  reusar): renderizar rangos de "Segoe Fluent Icons" a un PNG con
  `System.Drawing` y mirarlos. Así se descubrió que `E94A` — que el código
  previo usaba como icono de "Dispositivos" — es el **signo de división**.
  Reemplazado por `E955`; Extras pasó de `E71D` a `E8A9` (cuadrícula 2×2,
  el equivalente del `square.grid.2x2` de macOS). Los demás (`E946` info,
  `E8D6` música, `E714` video, `E91B` fotos, `E896` descarga, `E713` ajustes)
  se confirmaron correctos.
- **Riesgo #3 del plan (rendimiento de WMI):** centralizar en
  `DeviceSessionService` **reduce** las enumeraciones — antes cada ViewModel
  llamaba a `Refresh()` por su cuenta; ahora hay una por evento. Medido en la
  VM sin iPod conectado, `SELECT * FROM Win32_DiskDrive WHERE
  InterfaceType='USB'` cuesta ~457 ms la primera vez (WMI frío) y 2–4 ms
  después. Con el iPod conectado se suman las consultas de correlación
  (USBSTOR + particiones); falta medirlo con hardware.

### Fuera de alcance detectado (no se tocó)

- `LibraryPage` y `SyncPage` quedaron **fuera de la navegación**: no hay
  sección "Sincronizar" en macOS (se dispara desde General) y una biblioteca
  de mentira sería peor que ninguna. Los archivos se conservan como punto de
  partida de las fases 3 y 4. Siguen compilando y con su ViewModel registrado.
- `AuraStudio.App.csproj` sigue declarando `<None Update="appsettings.json">`
  sin que el archivo exista (heredado de la Fase 0). No rompe el build.
- `Platform/VolumeManager.GetLogicalDrives` está declarado y sin usar.

### Pendiente con el dueño

1. ~~**Icono de la app.**~~ **Resuelto en la Fase 2**: el dueño entregó un
   master propio para Windows (`studio/windows/icono/Aura icono.png`) y el
   punto 8 del plan lo cableó. Ver el apéndice de la entrada de la Fase 2.
   Queda solo su revisión visual en tamaños chicos.
2. **Verificar con el iPod real** los dos estados de General que esta fase no
   pudo ver: **conectado** (identidad, firmware, almacenamiento, resumen,
   "Abrir en el Explorador" y "Expulsar") y **ambiguo** (dos discos externos
   que califiquen a la vez: la app debe detenerse y explicarlo, sin listar
   candidatos). También el bloqueo de biblioteca con un iPod de fábrica: la
   `InfoBar` debe aparecer y Música/Video/Fotos quedar deshabilitados,
   mientras General y Extras siguen accesibles.
3. **Repaso visual de la barra de navegación** con el dueño (glifos elegidos,
   grupos expandidos por omisión) antes de que las fases 3–5 llenen las
   secciones.

## Fase 0 — Consolidación y bitácora (2026-08-31)

- **`.gitignore`**: quitada la línea `*.slnx` — excluía por accidente
  `AuraStudio.Windows.slnx`, el propio archivo de solución (no solo el
  caché de VS en `.vs/`, que ya estaba cubierto por `.vs/`). Sin ese
  arreglo, el primer commit se habría hecho sin la solución.
- **Residuos borrados**: `AuraStudio.App/xc_err.txt` y `xc_out.txt` (vacíos,
  sobras de una sesión de diagnóstico), `.DS_Store` en `studio/windows/`.
- **`open-vm.command` y `scripts/OpenInVM.ps1` eliminados**: eran
  herramientas para abrir la VM y Visual Studio *desde macOS* por control
  remoto (`prlctl exec`, `vmrun runProgramInGuest`), construidas para el
  flujo pre-VM del plan v1 ("escribir a ciegas en la Mac, validar remoto").
  Esa premisa quedó invalidada explícitamente por el plan v2: las sesiones
  de Claude Code corren *dentro* de la VM. Si el dueño las necesitaba para
  otro propósito (conveniencia manual desde macOS), no quedó rastro de uso
  real y son fáciles de rehacer — decisión documentada aquí en vez de
  preguntar a mitad de una tarea mecánica.
- **Bug real encontrado y corregido en `AuraStudio.Windows.slnx`**: el
  mapeo de plataforma de la solución para `AuraStudio.App` tenía
  `<Platform Solution="*|ARM64" Project="x64" />` — pedir `-p:Platform=ARM64`
  a nivel solución compilaba silenciosamente un binario **x64**, no ARM64
  (verificado comparando `bin/x64/...` vs `bin/ARM64/...` antes y después
  del fix, y confirmando con `dotnet build AuraStudio.App/AuraStudio.App.csproj
  -p:Platform=ARM64` directo que sí existe una configuración ARM64 real).
  Corregido a `Project="ARM64"`. Esto invalida cualquier claim previo de
  "compila ARM64" que se haya verificado solo vía el build de la solución —
  desde este fix sí es ARM64 real; antes, probablemente no.
- **3 warnings latentes corregidos en Core** (`CS8618` ×2 en
  `SyncMarker.cs`, `CS8524` en `VideoArtworkResolver.cs`):
  - `SyncMarker.cs`: `Timestamp`/`Changeset` pasaron a `required`, y el
    constructor de dominio (`SyncPendingMarker(Changes, DateTimeOffset?)`)
    se marcó `[SetsRequiredMembers]` (sin eso, `CS9035` en cada call site
    que no usa inicializador de objeto — lo disparó `tests/SyncMarkerTests.cs`
    y `SyncService.cs`). El constructor vacío para deserialización JSON
    sigue igual; `System.Text.Json` respeta `required` sin cambios.
  - `VideoArtworkResolver.cs`: el `switch` sobre `Kind` no cubría valores
    fuera de los 3 casos nombrados (cast arbitrario a `Kind`). Se agregó
    `_ => throw new ArgumentOutOfRangeException(...)`.
- **`TreatWarningsAsErrors`** activado en los 3 csproj
  (`AuraStudio.Core`, `AuraStudio.App`, `tests/AuraStudio.Core.Tests`) —
  la compuerta "0 warnings" del plan ahora es mecánica, no de lectura manual.
- **Verificación de las compuertas de salida** (todas en la VM, este
  repo): `dotnet build studio/windows -p:Platform=ARM64` → 0/0; `dotnet test
  tests/AuraStudio.Core.Tests` → 110/110; `AuraStudio.App.exe` (build ARM64
  real) arrancó y mostró la ventana "Aura Studio" (lanzado y cerrado por
  script, sin interacción manual — ver nota abajo).
- **`docs/MAPPING.md`** reescrito completo contra el inventario real de
  archivos (ya no dice "pendiente" lo que está hecho, ya no referencia
  `AuraStudio.Win/`).
- **`docs/ARQUITECTURA.md`** creado (nuevo, ver ese archivo).
- Decisiones de facto de la sesión de la VM registradas en `DECISIONS.md`
  como `ST-078`.

### Nota sobre "arrancar la app y verificar"

Esta sesión lanzó `AuraStudio.App.exe` (build ARM64 real, tras el fix del
`.slnx`) con `Start-Process`/`Stop-Process` desde PowerShell y confirmó
`MainWindowTitle == "Aura Studio"` antes de cerrarlo — no hubo verificación
visual humana de Mica/tema/NavigationView (la Fase 0 no tiene criterio de
aceptación de UI; eso empieza en la Fase 1). No se marca como "validado a
ojo" nada que no se vio.

### Fuera de alcance detectado (no se tocó)

- `AuraStudio.App.csproj` tiene `<None Update="appsettings.json">
  <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory></None>`
  pero el archivo `appsettings.json` no existe en el proyecto. No rompe el
  build (MSBuild no falla por un `Update` sin archivo). Revisar en la fase
  que lo necesite (Fase 6, ajustes/claves) si se va a usar de verdad o se
  puede quitar la entrada.
- `docs/VM-SETUP.md` no se revisó a fondo esta sesión — puede tener el
  mismo tipo de desactualización que tenía `MAPPING.md`. Queda para quien
  retome documentación de entorno.

### Pendiente con el dueño (Fase 0)

*(vacío — Fase 0 no requirió al dueño ni al iPod físico. Cada fase anota lo
suyo en su propia entrada; lo vigente está en la de la Fase 1, arriba.)*

---

## Supuestos para el shell WinUI 3 (Fase II.5) — contexto histórico, ya resuelto

> Documento de trabajo original para la implementación del shell WinUI 3 en
> la VM, escrito **antes** de tener acceso a compilar/ejecutar ahí. Todo lo
> que aquí se planteaba como duda quedó resuelto y registrado en las
> secciones de abajo ("Estado de compilación actual" en adelante) — se deja
> como contexto histórico de qué se asumió y qué de eso resultó cierto.

### Arquitectura MVVM

- **Framework**: CommunityToolkit.Mvvm 8.4 con `[ObservableProperty]` y `[RelayCommand]`
- **DI**: `ServiceCollection` (NO `IHost`) — mismo patrón que el Core portable
- **Target**: `net10.0-windows10.0.19041.0` (requiere Windows App SDK 2.0 GA)

### WndProc y detección USB

- Subclase de `Microsoft.UI.Xaml.Window` con `HWND` para capturar `WM_DEVICECHANGE`
- No hay equivalente directo en WinUI 3; requiere P/Invoke a `user32.dll`
- Ver: `docs/INVESTIGACION-aura-studio-windows.md` §3

### Diseño Fluent 2

- **Mica/Acrylic**: `Microsoft.UI.Xaml.Media.AcrylicBrush` (disponible en Windows App SDK)
- **Tipografía**: `Segoe UI Variable` (disponible desde Windows 11)
- **Colores**: Leer de apps/aura/ el componente real para replicar, NO inventar

### Elementos de UI críticos por portar (de mayor a menor prioridad)

1. **DeviceListView** — lista de iPods detectados (requiere WndProc)
2. **SyncView** — progreso de sincronización
3. **LibraryView** — navegador de biblioteca (Music/Video/Photos)
4. **ThemeEditorView** — editor de temas (requiere ThemePackager/ThemeValidator)
5. **SettingsView** — preferencias

### APIs de plataforma no disponibles en WinUI 3

| macOS (Swift) | Windows (alternativa) | Estado |
|---------------|----------------------|--------|
| `IOKit` / `DiskArbitration` | `WM_DEVICCHANGE` + `SetupAPI` | Requiere P/Invoke |
| `NSAppleScript` (admin privileges) | `SecondaryLogon` / `RunAs` | Requiere P/Invoke |
| `Security.framework` (Keychain) | `Windows.Security.Credentials` | Disponible en WinRT |

### Testing

- Unit tests para el Core (listo, 80/83)
- Tests de integración requieren la VM con Windows + iPod real
- Por ahora: verificar que la UI compile y muestre ventana básica

## Estado de compilación al cerrar la sesión pre-plan (histórico)

> Congelado: refleja la sesión anterior a la Fase 0. El estado vigente está
> en la entrada de la fase más reciente, arriba.

```
AuraStudio.Core:  ✅ COMPILA en la VM (0 warnings, 0 errores)
Tests:            ✅ 101/101 verdes en la VM (+18 PnpDeviceId)
AuraStudio.App:   ✅ COMPILA Y ARRANCA en la VM (ARM64, 0 errores, 0 warnings)
                  ✅ Shell NavigationView Fluent 2 con navegación funcional
                  ✅ Detección USB real confirmada en hardware (iPod Classic en E:\)
                  ✅ Riesgo #1 superado (Parallels USB passthrough OK)
```

### Corregido en la VM (2026-08-31)

1. **Bug de contrato en `SyncMarker.cs`** (era uno de los 3 tests rojos):
   la propiedad `Changeset` serializaba la clave JSON como `"changeset"`,
   pero el contrato SS4.1 (`library-layout-v1.md`) y el Swift original
   (`var changes`) exigen exactamente `"changes"` — el firmware la lee tal
   cual. Corregido con `[JsonPropertyName("changes")]` (no se puede renombrar
   la propiedad a `Changes` en C#: chocaría con el tipo anidado `Changes`).
2. **2 tests de `SyncMarkerTests`** escribían el marcador sin crear antes el
   directorio `.aura/`. En macOS pasaba porque el helper del test lo creaba
   por otro camino; en Windows `File.WriteAllText` no crea directorios.
   Añadido `Directory.CreateDirectory` en ambos tests (el Swift original
   también lo crea explícitamente).

### Diagnóstico del fallo de XamlCompiler — RESUELTO (2026-08-31)

Causa raíz confirmada: **desajuste de versión del Windows SDK**. El csproj
pedía `net10.0-windows10.0.19041.0` / `TargetPlatformMinVersion 10.0.19041.0`,
pero esta VM solo tiene instalado el SDK `10.0.26100.0` — sin carpeta
`10.0.19041.0` en `C:\Program Files (x86)\Windows Kits\10\{UnionMetadata,
Platforms\UAP,References}\`. Sin esa Union Metadata (`Windows.winmd`),
XamlCompiler no puede resolver tipos WinRT básicos y moría con código 1 sin
mensaje. Abrir el proyecto en Visual Studio sí mostró el rastro real en su
Lista de Errores (`Unknown type 'Color'`, `Unknown member 'Width' en
'Window'`) que la consola se tragaba.

**Cambios aplicados** (en orden, cada uno verificado con rebuild):

1. `AuraStudio.App.csproj`: `TargetFramework` → `net10.0-windows10.0.26100.0`
   (coincide con el SDK instalado); `TargetPlatformMinVersion` se deja en
   `10.0.19041.0` (mínimo soportado en runtime, D4 del plan — TFM de
   compilación y mínimo de plataforma son cosas distintas).
2. WindowsAppSDK **1.7.250310001 → 2.4.0** (la 1.7 no tiene paquete de
   `Microsoft.Windows.SDK.BuildTools` compatible con SDK 26100; con la 2.4.0
   hubo que subir también `Microsoft.Windows.SDK.BuildTools` a
   `10.0.26100.4654` — NU1605 por degradación de paquete lo pidió
   explícitamente).
3. Bugs reales de XAML "escrito a ciegas" (WMC0011 — API que no existe en
   WinUI 3, aunque sí en UWP):
   - `Window` no acepta `Width`/`Height` en XAML (a diferencia de la
     `Window` de UWP) — se fija en runtime con `AppWindow.Resize(...)` en
     `MainWindow.xaml.cs`, escalado por `XamlRoot.RasterizationScale`.
   - `AcrylicBrush` de WinUI 3 no tiene `BackgroundSource` (era de UWP,
     donde distinguía acrílico in-app de host-backdrop) — se quitó de
     `Resources/Styles.xaml`; el efecto de fondo de ventana se logra con
     `SystemBackdrop` (Mica/DesktopAcrylicBackdrop), pendiente de aplicar
     cuando se retome el diseño de ventana.
4. `MainWindow.xaml.cs` reescrito: el hook de `WM_DEVICECHANGE` usaba
   `SetWindowSubclass`/`RemoveWindowSubclass` de comctl32 con una firma de
   delegado que no compilaba como método parcial de P/Invoke con
   `[LibraryImport]` (la clase no era `partial`, y el patrón de comctl32 no
   es el subclaseo clásico). Reemplazado por el subclaseo clásico de Win32
   (`SetWindowLongPtrW(GWLP_WNDPROC)` + `CallWindowProcW`), manteniendo vivo
   el delegate como campo para que el GC no lo recolecte mientras la ventana
   lo sigue apuntando. También se quitaron los handlers muertos de
   `NavigationView` (`NavView_SelectionChanged`, `NavView_SettingsInvoked`,
   `NavigateTo`) — el `MainWindow.xaml` actual es un placeholder sin
   `NavigationView` ni `ContentFrame`; esos handlers referenciaban un tipo
   (`NavigationViewSettingsInvokedEventArgs`) que ni siquiera existe con ese
   nombre en WinUI 3. Se retomarán cuando se porte la navegación real.
   `Window` tampoco tiene `DataContext` (no es `FrameworkElement`) — se quitó
   esa asignación.
5. `App.xaml.cs` usa `Microsoft.Extensions.DependencyInjection.ServiceCollection`
   pero el csproj no traía el paquete — agregado
   `Microsoft.Extensions.DependencyInjection 9.0.0`.
6. `Services/ThemeService.cs` estaba escrito contra una API de
   `ThemeValidator`/`ThemePackager`/`AuraThemeManifest` que no es la que
   expone `AuraStudio.Core` (`ThemeValidator`/`ThemePackager` son clases
   estáticas, no instanciables; `Validate` pide `firmwareSupportedFormat`;
   `AuraThemeManifest` no tiene `Read`, solo `Parse(string)`; no existe
   `ThemePackager.InstallAsync`). Reescrito para usar las APIs reales:
   valida con `ThemeValidator.Validate(path, FirmwareCapabilities.
   SupportedThemeFormat(volumeRoot))` y, si es válido, copia el paquete ya
   armado a `.rockbox/aura/themes/<id>/` (re-verificando `AuraThemeID.
   IsValid` antes de tocar la ruta, como pide la regla del repo). También
   corregido `GetInstalledThemesAsync`, que leía `manifest.json` — el
   contrato usa `theme.cfg`.
7. `Views/DeviceListPage.xaml` construía `<vm:DeviceListViewModel />`
   directo en XAML (WMC0100: el tipo no tiene constructor público sin
   argumentos, necesita `IUsbDeviceWatcher` por DI). Se quitó del XAML y se
   resuelve en el code-behind con `App.Services.GetRequiredService<...>()`,
   igual que el resto de la app.

Con eso, `dotnet build -p:Platform=ARM64` compila **0 errores** y
`AuraStudio.App.exe` arranca y muestra la ventana "Aura Studio".

### Limpieza de warnings (misma sesión)

Los 7 warnings del primer build limpio también quedaron en cero:

- `MVVMTK0045` ×5 (`DeviceListViewModel`, `MainViewModel`) — migrados los
  `[ObservableProperty]` de campos privados a **propiedades parciales**
  (el patrón AOT/WinRT que pide el toolkit). Requirió
  `<LangVersion>preview</LangVersion>` en `AuraStudio.App.csproj`: sin eso,
  el generador de Mvvm 8.4 no emite la parte de implementación y el build
  falla con CS9248. Los valores por defecto de las propiedades se mueven al
  constructor (una propiedad parcial no admite inicializador).
- `CS0067` en `SyncService.cs` — el placeholder ahora dispara
  `ProgressChanged` (Scanning al entrar, Complete al salir) en
  `SyncAsync`/`PreviewSyncAsync`, de modo que el evento del contrato
  `ISyncService` ya se ejercita aunque la sincronización real siga pendiente.

Las 5 advertencias `Unknown type 'Color'` sobre `Styles.xaml` que muestra la
Lista de Errores de Visual Studio **no aparecen en el build real** (`dotnet
build` en limpio: 0 warnings) y la app carga `Styles.xaml` sin problema en
runtime — son diagnósticos de IntelliSense, probablemente cacheados de cuando
el TFM apuntaba al SDK que no estaba instalado. Recompilar la solución o
cerrarla y reabrirla en VS debería limpiarlas.

Pendientes heredados en el Core (sin tocar): `CS8524` en
`AuraStudio.Core/Networking/VideoArtworkResolver.cs:54` (switch no
exhaustivo) y `CS8618` ×2 en `SyncMarker.cs:71` (propiedades no anulables
sin inicializar en el constructor sin parámetros, usado solo para
deserialización) — solo se reportan con analizadores en modo estricto, el
build del Core sale limpio.

### Detección real del iPod por USB (2026-08-31)

Se reemplazó el stub de `UsbDeviceWatcher` por la detección real sobre
hardware Windows:

**Nuevos archivos (lógica pura, testeable sin hardware):**
- `AuraStudio.Core\PnpDeviceId.cs` — parser de IDs Plug&Play de Windows:
  `TryParseUsbStorageId` (USBSTOR: vendor/producto SCSI + serial) y
  `TryParseUsbDeviceId` (USB\VID_05AC&PID_1261 → VID/PID). 18 tests
  nuevos en `PnpDeviceIdTests.cs` (total Core: 101/101 verdes).

**Nuevos archivos (Windows, en `Platform\`):**
- `Platform\WmiDiskEnumerator.cs` — enumera discos USB vía WMI
  (`Win32_DiskDrive WHERE InterfaceType='USB'`) y correlaciona:
  - Vendor/producto SCSI del USBSTOR ID (lectura real del firmware que
    atiende el USB, ST-016: "Apple"/"iPod" o "Rockbox"/"media player").
  - VID/PID 0x05AC/0x1261 casando serial USBSTOR ↔ nodo USB
    `Win32_PnPEntity`.
  - Letra de unidad y etiqueta vía asociaciones
    `DiskDrive → Partition → LogicalDisk`.
  - Un disco que desaparece a mitad de consulta no tumba la enumeración.
- `Platform\VolumeProbe.cs` — enriquece el candidato identificado con
  datos del volumen montado (`aura.cfg`): `HasAuraConfig`,
  `SupportedSyncMarkerVersion`, `SupportedThemeFormat`, `DeclaredFamily`.
  `RunningFirmware` sale **solo** de los descriptores USB (ST-016).

**Cambios en servicios y UI:**
- `IUsbDeviceWatcher` expone `LastIdentification` (`DiskIdentificationResult`)
  y `GetConnectedIPods()` devuelve lista vacía en NotFound/Ambiguous
  (regla de seguridad: nunca mostrar candidatos ambiguos como seleccionables).
- `UsbDeviceWatcher` reescrito: `WmiDiskEnumerator` → `IPodDiskIdentifier.Identify`
  → `VolumeProbe.Build` para el único `Found`.
- `DeviceListViewModel.RefreshDevices()` hace switch sobre
  `LastIdentification`: NotFound (mensaje actual), Found (lista + selección
  automática), Ambiguous (mensaje **exacto del repo**: "Se encontraron N
  discos que podrían ser tu iPod. Por seguridad, Aura Studio no elige uno
  solo — desconecta los demás discos externos y vuelve a intentar."). Se
  elimina la rama "N iPods detectados. Selecciona uno." (N>1 siempre es
  ambigüedad con identificación estricta).
- `MainWindow.xaml.cs`: debounce de 750 ms en `DBT_DEVICEARRIVAL` (colapsa
  la ráfaga) + reintento a 2.5 s para recoger la letra de unidad que
  aparezca tarde; todo en hilo UI con `DispatcherQueueTimer` one-shot.

**Paquete nuevo:**
- `System.Management` 10.0.11 en `AuraStudio.App.csproj` (WMI, no está en
  el BCL de .NET 10).

**Resultado:** `dotnet build` 0 errores/0 warnings; `dotnet test` 101/101
verdes; app arranca y muestra la detección real (sin dispositivo falso).
La validación con iPod real por USB passthrough de Parallels confirmó el
riesgo #1 como superado: Windows expone el iPod en `E:\` con 125 GB, y la
aplicación lo identifica correctamente.

### Primera iteración de paridad con macOS (2026-08-31)

- `IPodDiskInfo` ahora conserva capacidad, espacio usado/libre, sistema de
  archivos y el resumen de biblioteca leído desde `sync_summary.cfg`.
- `VolumeProbe` enriquece el candidato con `DriveInfo`, `CatalogSummaryReader`
  y las capacidades de `aura.cfg`, sin mezclar firmware USB con firmware en
  disco (ST-016).
- `DeviceListPage` dejó de ser una lista técnica: ahora presenta una vista
  General con identidad, firmware, almacenamiento, resumen de Música/Video/
  Fotos/Playlists, estado, actualización, abrir en Explorador y expulsión.
- Se agregó `Platform/VolumeManager.cs` para abrir y solicitar la expulsión de
  volúmenes Windows.
- Build ARM64 verificado después de estos cambios: 0 errores, 0 warnings.

Pendiente para completar la paridad: estado de sesión compartido entre
páginas, biblioteca local real, preview/sincronización real, instalador DFU,
temas y ajustes. `SyncService` sigue siendo provisional y no debe presentarse
como una sincronización funcional todavía.
---

## Sesión de cierre con el dueño (lista consolidada)

Todo lo que **necesita al dueño** y no se puede terminar sin él. Se va sumando
durante la corrida nocturna.

- **Devolver la carpeta de biblioteca** a `V:\Mac Externo\Documents\Aura Library`
  si la quiere ahí: durante la noche quedó apuntando a fixtures para no tocar la
  real (Ajustes › Biblioteca › Cambiar).
- **Reproducir el crash del cambio de familia** (Aura → Metro) con el iPod
  conectado y pasar `%LOCALAPPDATA%\Aura Studio\errores.log`. ST-088 corrigió un
  defecto compatible con la firma, pero no se pudo reproducir sin el aparato.
- **Formateo real y DFU** nunca ejecutados contra el iPod.
- **Procedencia GPL §3 de `mks5lboot.exe`**: el binario actual se compiló de un
  árbol sucio. Bloquea el release público, no el desarrollo.
- **Poblar `artifacts/` con un Release real** (instalar `gh` y autenticar).
- **Medir la comprobación de archivos contra `V:`** con su biblioteca real: en
  disco local son 54 ms para 12 000 elementos, pero por la carpeta compartida
  pueden ser segundos (ST-098).
- **Decidir el empaquetado** (Fase 7): sin empaquetar + instalador, o MSIX;
  ARM64 primero y x64 después. Es una decisión suya y bloquea el cierre.
- **Diseñar la vuelta al firmware de Apple en Windows** (`RestoreHandoffView`
  de macOS lo termina Finder; acá sería iTunes o Dispositivos de Apple): no se
  puede diseñar sin el iPod.
- **Poner sus claves de fanart.tv y TMDB** y enriquecer un artista y una
  película de prueba: es el criterio de aceptación de la Fase 6 y necesita
  claves reales.
- **Ver la pantalla de Temas con temas de verdad**: sin iPod solo se puede ver
  el estado "sin dispositivo". El ciclo completo está probado contra un volumen
  de mentira, pero la lista, la activación y el bloqueo de compartir no se han
  visto en pantalla con datos reales.
- **Probar el recorte cuadrado en la VM** (ST-140/ST-141/ST-142): correr
  `dotnet run --project tools\ImageResizerCheck -c Release` (comprobaciones
  20-27) y confirmar que no hay pausa perceptible al aplicar una tapa — el
  puente a WIC de `WicSquareImageEncoder` es síncrono
  (`Task.Run(...).GetAwaiter().GetResult()`), que es lo que permite normalizar
  desde los puntos de entrada síncronos de Core.
- **Agregar el botón de cancelar la normalización de carátulas** (ST-141): el
  modelo ya expone `IsNormalizingCovers` y `CancelCoverNormalization()`, y el
  avance sale por `StatusMessage`, que las páginas ya muestran; falta el XAML.
  Mientras tanto la migración se detiene cerrando la app y se retoma sola.
- **Revisión visual** de las pantallas nuevas en su monitor y con su biblioteca.
- **Instalar ffmpeg** (`winget install Gyan.FFmpeg`) — no está en esta VM, así
  que ninguna conversión de video real se ejecutó todavía. Los argumentos y los
  parsers están probados; el resultado en el aparato, no.
- **Sincronizar una biblioteca chica al iPod real** y arrancar el firmware para
  ver que reconstruye los índices de las secciones marcadas. Es el paso 5 de la
  Fase 4 y el único que falta de esa fase.
- **Comparar los archivos del contrato** que produce Windows contra los que
  produce macOS sobre la misma biblioteca de prueba (criterio de aceptación de
  la Fase 4). El manifiesto ya tiene pruebas de compatibilidad; el resto
  (`sync_summary.cfg`, `ratings.cfg`, índices) se comparó contra el código de
  macOS, no contra su salida real.

## Post-plan (diferido a propósito)

Lo no bloqueante que se encontró durante la corrida y **no** se arregló en
caliente, por instrucción del dueño.

- Redimensionar columnas de la tabla de Canciones arrastrando el encabezado.
- Mutex entre procesos para escrituras al iPod (`InstallerFlowRegistry` es por
  proceso; dos instancias pueden escribir al mismo disco).
- Aviso o candado suave cuando la app de macOS y la de Windows abren la misma
  carpeta de biblioteca a la vez.
- El ajuste "barra de estado" (`ShowStatusBar`) existe en Ajustes y **no lo lee
  ninguna pantalla**: la barra de conteos se muestra siempre. O se conecta o se
  quita el ajuste.
- Marcar como decorativos (`AutomationProperties.AccessibilityView="Raw"`) los
  íconos de encabezado de General y del Shell: hoy un lector de pantalla los
  anuncia como contenido.
- Edición de metadata por lote (`BatchMediaInfoView` de macOS).
- Hoja de revisión de carátulas contaminadas (`CoverContaminationSheet`).
  Mientras no exista, ningún camino borra imágenes, así que ST-012 se cumple
  por ausencia.
- Expulsión del iPod por `CM_Request_Device_Eject` en vez de invocar el verbo
  del shell con PowerShell: lo actual funciona pero no puede informar si falló.
- Regla de "mismo episodio" del detector de similares: el bloqueo previo hace
  que casi nunca se aplique. Igual en macOS; corregirlo requiere coordinar las
  dos apps (ST-084).
