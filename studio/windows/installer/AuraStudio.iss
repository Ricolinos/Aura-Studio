; Aura Studio para Windows — script de Inno Setup (Ronda 5, empaquetado).
;
; No se compila a mano: lo invoca `scripts\Make-Installer.ps1`, que antes
; corre el `dotnet publish` autocontenido y verifica que el árbol publicado
; sea el que se va a empaquetar. Compilarlo suelto puede empaquetar un
; publish viejo.
;
; Decisiones que este archivo sostiene:
;
;  - **Instalación por usuario, sin UAC** (`PrivilegesRequired=lowest`). El
;    programa no necesita permisos de administrador para existir; los pide
;    después, una operación a la vez, cuando de verdad va a tocar el disco del
;    iPod. Un instalador que pide elevación de entrada enseña justo lo
;    contrario de lo que la app promete en PermissionsView.
;  - **Solo ARM64.** Es lo único que esta ronda produce y probó. Un x64 sin
;    probar no se ofrece; ver ESTADO-PORT.md.
;  - **Sin firma de código todavía**: SmartScreen va a advertir. Es un
;    pendiente consciente, no un descuido.

#define AppName        "Aura Studio"
#define AppVersion     "0.1.0"
#define AppPublisher   "Ricolinos"
#define AppExe         "AuraStudio.App.exe"
#define AppUrl         "https://github.com/Ricolinos/Aura-Studio"
; Relativo a este archivo. Lo produce `dotnet publish ... --self-contained`.
#define PublishDir     "..\AuraStudio.App\bin\ARM64\Release\net10.0-windows10.0.26100.0\win-arm64\publish"

[Setup]
; Este GUID identifica al producto para Windows: es lo que hace que una
; instalación nueva ACTUALICE la anterior en vez de dejar dos entradas en
; «Aplicaciones instaladas». No se cambia nunca.
AppId={{7B3C1E24-9A4F-4C8D-9E51-2F6A0D7B4C13}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}
VersionInfoVersion={#AppVersion}

; Con PrivilegesRequired=lowest, {autopf} es %LOCALAPPDATA%\Programs.
DefaultDirName={autopf}\Aura Studio
DefaultGroupName=Aura Studio
DisableProgramGroupPage=yes
PrivilegesRequired=lowest

ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
; Mismo mínimo que TargetPlatformMinVersion del .csproj (Windows 10 2004).
MinVersion=10.0.19041

OutputDir=..\dist
OutputBaseFilename=AuraStudioSetup-{#AppVersion}-arm64
SetupIconFile=..\AuraStudio.App\Assets\AuraStudio.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
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
