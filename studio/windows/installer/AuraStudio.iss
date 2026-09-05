; Aura Studio para Windows — script de Inno Setup.
;
; No se compila a mano: lo invoca `scripts\Make-Installer.ps1`, que antes corre
; el `dotnet publish` autocontenido y verifica que el árbol publicado sea el que
; se va a empaquetar. Compilarlo suelto puede empaquetar un publish viejo.
;
; La arquitectura llega de afuera:  ISCC /DArch=x64 AuraStudio.iss
; (sin `/D`, ARM64 — que es la nativa del aparato del dueño).
;
; Decisiones que este archivo sostiene:
;
;  - **Instalación por usuario, sin UAC** (`PrivilegesRequired=lowest`). El
;    programa no necesita permisos de administrador para existir; los pide
;    después, una operación a la vez, cuando de verdad va a tocar el disco del
;    iPod. Un instalador que pide elevación de entrada enseña justo lo
;    contrario de lo que la app promete en PermissionsView.
;  - **Un solo AppId para las dos arquitecturas** — ver el comentario en
;    `AppId`, más abajo: es una decisión, no un descuido.
;  - **Sin firma de código todavía**: SmartScreen va a advertir. Es un
;    pendiente consciente.

#ifndef Arch
  #define Arch "arm64"
#endif

#if Arch == "x64"
  #define RuntimeId       "win-x64"
  #define PlatformDir     "x64"
  ; `x64compatible` incluye a ARM64: Windows 11 en ARM emula x64, y esa es
  ; justamente la razón de que este Setup se pueda probar en el aparato del
  ; dueño. `x64os` lo habría prohibido ahí.
  #define ArchAllowed     "x64compatible"
  #define ArchSuffix      " (x64)"
#else
  #define RuntimeId       "win-arm64"
  #define PlatformDir     "ARM64"
  #define ArchAllowed     "arm64"
  #define ArchSuffix      ""
#endif

#define AppName        "Aura Studio"
#define AppVersion     "0.2.1"
#define AppPublisher   "Ricolinos"
#define AppExe         "AuraStudio.App.exe"
#define AppUrl         "https://github.com/Ricolinos/Aura-Studio"
; Relativo a este archivo. Lo produce `dotnet publish ... --self-contained`.
#define PublishDir     "..\AuraStudio.App\bin\" + PlatformDir + "\Release\net10.0-windows10.0.26100.0\" + RuntimeId + "\publish"

[Setup]
; Este GUID identifica al producto para Windows. **Es el mismo para ARM64 y
; para x64, a propósito**: son el mismo programa, y la arquitectura es un
; detalle del empaquetado, no un producto aparte.
;
; La consecuencia buscada es que **no convivan**: instalar una reemplaza a la
; otra en el mismo lugar. Dos entradas en «Aplicaciones instaladas» con el
; mismo nombre y el mismo icono serían ~600 MB y ninguna forma de saber cuál
; abre el acceso directo. Y el caso que de verdad ocurre —alguien en ARM64 que
; bajó el x64 por error y después instala el nativo— se arregla solo.
;
; Lo que sí cambia por arquitectura es `UninstallDisplayName`, para que la
; entrada diga cuál está instalada. No se cambia nunca.
AppId={{7B3C1E24-9A4F-4C8D-9E51-2F6A0D7B4C13}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}{#ArchSuffix}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}
VersionInfoVersion={#AppVersion}

; Con PrivilegesRequired=lowest, {autopf} es %LOCALAPPDATA%\Programs.
DefaultDirName={autopf}\Aura Studio
DefaultGroupName=Aura Studio
DisableProgramGroupPage=yes
PrivilegesRequired=lowest

ArchitecturesAllowed={#ArchAllowed}
ArchitecturesInstallIn64BitMode={#ArchAllowed}
; Mismo mínimo que TargetPlatformMinVersion del .csproj (Windows 10 2004).
MinVersion=10.0.19041

OutputDir=..\dist
OutputBaseFilename=AuraStudioSetup-{#AppVersion}-{#Arch}
SetupIconFile=..\AuraStudio.App\Assets\AuraStudio.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}{#ArchSuffix}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

; El aviso GPL v2 se muestra ANTES de instalar, no enterrado en la carpeta:
; es la parte del §3 que le toca al instalador.
InfoBeforeFile=AVISO-LICENCIAS.txt

; Si el programa está abierto al actualizar, Windows lo pide cerrar en vez de
; fallar a la mitad con archivos bloqueados. No lo relanza solo: si estaba
; sincronizando, quien decide volver a abrirlo es el usuario.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"

[LangOptions]
; La variante: español de México (0x080A), no el es-ES del .isl base.
es.LanguageID=$080A

[Messages]
; El .isl que trae Inno es español neutro (sin voseo, sin españolismos), así
; que sirve de base; acá solo se ajustan los textos donde el genérico decía
; menos de lo que este instalador sí puede decir.
es.WelcomeLabel2=Se instalará [name/ver] en su cuenta de usuario.%n%nNo hacen falta permisos de administrador y no se modifica nada del sistema.
es.FinishedLabel=Aura Studio quedó instalado. Conecte su iPod Classic y ábralo para empezar.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Restos de la OTRA arquitectura, porque las dos comparten AppId y carpeta.
;
; Casi todo el árbol tiene los mismos nombres en ARM64 y en x64, así que se
; sobrescribe solo; estos dos no, y quedaban tirados tras cambiar de
; arquitectura — invisibles, inofensivos en ejecución, pero **el desinstalador
; no los conoce**, así que desinstalar habría dejado basura para siempre. Se
; verificó comparando los dos árboles publicados, archivo por archivo.
;
; Corre antes de [Files], así que borrar también los de la arquitectura que se
; está instalando no molesta: se copian enseguida.
;
; **Esta lista no se mantiene a mano.** `Make-Installer.ps1 -Architecture both`
; compara los dos árboles publicados archivo por archivo y avisa si aparece uno
; que solo exista en uno de los dos y que ningún patrón de acá cubra — que es
; exactamente como se descubrieron los `workloads.*.json`, después de creer que
; con las dos primeras líneas bastaba.
Type: files; Name: "{app}\*.arm64.dll"
Type: files; Name: "{app}\*.amd64.dll"
Type: files; Name: "{app}\*_ec.dll"
Type: files; Name: "{app}\mscordaccore_*.dll"
Type: files; Name: "{app}\workloads.*.json"

[Files]
; Todo el publish autocontenido: el runtime de .NET, el Windows App SDK y
; `artifacts\` con las tres familias de firmware y sus avisos de licencia.
; `AuraStudio.App.pri` entra acá dentro — sin ese archivo la app arranca y
; muere sin poder resolver su propio XAML; ver el target
; AuraPublicarPriDeLaApp en AuraStudio.App.csproj.
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

; Al desinstalar NO se toca %LOCALAPPDATA%\Aura Studio: ahí viven las
; preferencias, la caché de Releases y el registro de errores del usuario.
; Borrarlos sería decidir por él; el aviso de licencias dice dónde quedan.

#if Arch == "x64"
[Code]
{ En una máquina ARM64 el Setup x64 SÍ se instala y funciona —Windows 11 emula
  x64—, pero lo nativo corre mejor. Se avisa y se deja seguir: prohibirlo sería
  decidir por alguien que quizá tiene una razón (probar, o replicar un
  problema). Informar y obedecer, no bloquear.

  Callado en modo silencioso: ahí no hay quien lea un diálogo, y un instalador
  desatendido que se cuelga esperando un botón es peor que el aviso. }
function InitializeSetup(): Boolean;
begin
  Result := True;
  if IsArm64 and not WizardSilent then
  begin
    MsgBox('Esta es la versión x64 de Aura Studio y su equipo es ARM64.' + #13#10 + #13#10 +
           'Va a funcionar: Windows la ejecuta emulada. Aun así, hay una versión ARM64 nativa ' +
           '(AuraStudioSetup-' + '{#AppVersion}' + '-arm64.exe) que aprovecha mejor su equipo.' + #13#10 + #13#10 +
           'Puede continuar con esta si prefiere.',
           mbInformation, MB_OK);
  end;
end;
#endif
