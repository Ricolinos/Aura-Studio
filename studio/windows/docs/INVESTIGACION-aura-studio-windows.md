# INVESTIGACIÓN — Aura Studio Windows: Arquitectura, Fluent 2 y Pantallas

> **Fecha:** 2026-08-31
> **Fase I** del plan de 4 etapas (gobernada por `Aura/docs/plans/PLAN-aura-studio-windows.md`).
> Este es el producto de la investigación. La Fase II (ejecución desatendida) lo sigue al pie de la letra.

---

## A. Decisiones de Arquitectura

### A.1 Stack fijo

| Componente | Versión | Nota |
|------------|---------|------|
| Windows App SDK | **2.4.0 stable** (ago 2026) | Canal stable actual |
| CommunityToolkit.Mvvm | **8.4.0** | Requiere `LangVersion latest` |
| CommunityToolkit.WinUI | **8.2.*** | Converters, Behaviors |
| Microsoft.Extensions.DI | **9.0.*** | Solo `ServiceCollection`, sin `IHost` |
| Fluent UI System Icons | (no incluido) | Segoe Fluent Icons nativo de WinUI 3 basta |
| WinUIEx | **NO** | Nativo (`AppWindow`) cubre todo lo necesario |

### A.2 TFM (Target Framework)

```xml
<!-- AuraStudio.Core (portable, compila en la Mac) -->
<TargetFramework>net10.0</TargetFramework>

<!-- AuraStudio.Desktop (WinUI 3, solo compila en Windows) -->
<TargetFramework>net10.0-windows10.0.19041.0</TargetFramework>
<TargetPlatformMinVersion>10.0.17763.0</TargetPlatformMinVersion>
<WindowsAppSDKSelfContained>true</WindowsAppSDKSelfContained>
<WindowsPackageType>MSIX</WindowsPackageType>
```

- Si WASDK 2.4 GA soporta `net10.0-windows` (verificar en la VM): host y Core ambos en `net10.0`, sin multi-targeting.
- Si NO soporta: host en `net8.0-windows10.0.19041.0` → `AuraStudio.Core` pasa a `<TargetFrameworks>net8.0;net10.0</TargetFrameworks>` (cambio de una línea).

### A.3 Estructura de proyecto

```
studio/windows/
  AuraStudio.Windows.sln
  AuraStudio.Core/                   # net10.0, SIN dependencia WinUI
    IPodDiskIdentifier.cs            #   ✅ portado
    USBDeviceIdentity.cs             #   ✅ portado
    RunningFirmware.cs               #   ✅ portado
    Services/                        #   Interfaces + lógica portable
      IDeviceDetector.cs
      IFirmwareService.cs
      ILibraryService.cs
    Models/
    Helpers/
  AuraStudio.Win/                    # WinUI 3, net10.0-windows
    App.xaml(.cs)                    #   DI raíz (ServiceCollection)
    MainWindow.xaml(.cs)             #   Title bar custom, MicaBackdrop
    Views/
      ShellPage.xaml                 #   NavigationView + Frame
      InstallerFlow/                 #   7 pantallas del instalador
        WelcomePage.xaml
        PermissionsPage.xaml
        DetectDevicePage.xaml
        EnterDFUPage.xaml
        FlashingPage.xaml
        AwaitBootloaderPage.xaml
        DonePage.xaml
      DeviceGeneralPage.xaml         #   Post-v1
      LicensesPage.xaml
    ViewModels/
      ShellViewModel.cs
      InstallerViewModel.cs          #   Estado que sobrevive navegación
      DeviceViewModel.cs
      FlashViewModel.cs
    Platform/
      DeviceWatcher.cs               #   WM_DEVICECHANGE + P/Invoke
      VolumeManager.cs               #   Win32 volume APIs
      PrivilegedRunner.cs            #   UAC (helper elevado separado)
      DfuFlashRunner.cs              #   mks5lboot.exe como subproceso
      CredentialStore.cs             #   Credential Manager
    Converters/
    Messages/                        #   WeakReferenceMessenger records
  tests/
    AuraStudio.Core.Tests/           #   xUnit, net10.0 (corre en la Mac)
    AuraStudio.Win.Tests/            #   ViewModel tests con Moq
  scripts/
    FirmwareFetch.ps1
  artifacts/
    mks5lboot.exe                    #   cross-compilado
  docs/
    MAPPING.md
```

**Regla cardinal:** `AuraStudio.Core` **nunca** referencia `Microsoft.WindowsAppSDK` ni `Microsoft.UI.Xaml`. Solo BCL + CommunityToolkit.Mvvm. La frontera entre portable y Windows es `Platform/` en el host.

### A.4 MVVM con CommunityToolkit.Mvvm

**ViewModels: siempre `partial class` hereda `ObservableObject`.**

```csharp
public sealed partial class FlashViewModel : ObservableObject
{
    private readonly IFirmwareService _firmware;

    public FlashViewModel(IFirmwareService firmware) => _firmware = firmware;

    [ObservableProperty] private double _percent;
    [ObservableProperty] private string _phase = "Listo";

    [RelayCommand(IncludeCancelCommand = true)]
    private async Task FlashAsync(IProgress<double> progress, CancellationToken token)
    {
        Phase = "Flasheando...";
        await _firmware.FlashDfuAsync(progress, token);
        Phase = "Completado";
    }
}
```

**Reglas:**
- Campo privado → `[ObservableProperty]` genera la propiedad pública
- `[RelayCommand]` genera `IAsyncRelayCommand` para comandos async
- `IncludeCancelCommand = true` genera `FlashCancelCommand` gratis
- `IProgress<double>` + `CancellationToken` son los parámetros del patrón de progreso

### A.5 Inyección de dependencias

```csharp
// App.xaml.cs
public sealed partial class App : Application
{
    public static IServiceProvider Services { get; private set; } = null!;
    public static Window MainWindowInstance { get; private set; } = null!;

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        var services = new ServiceCollection();
        ConfigureServices(services);
        Services = services.BuildServiceProvider(validateScopes: true);
        MainWindowInstance = Services.GetRequiredService<MainWindow>();
        MainWindowInstance.Activate();
    }

    private static void ConfigureServices(IServiceCollection s)
    {
        // Servicios de plataforma
        s.AddSingleton<IUsbDeviceWatcher, UsbDeviceWatcher>();
        s.AddSingleton<IVolumeManager, VolumeManager>();
        s.AddSingleton<IPrivilegedRunner, PrivilegedRunner>();
        s.AddSingleton<IDfuFlashRunner, DfuFlashRunner>();

        // Servicios de dominio
        s.AddSingleton<IDeviceDetector, DeviceDetector>();
        s.AddSingleton<IFirmwareService, FirmwareService>();

        // ViewModels
        s.AddSingleton<ShellViewModel>();
        s.AddTransient<InstallerViewModel>();
        s.AddTransient<FlashViewModel>();

        // Windows
        s.AddSingleton<MainWindow>();
        s.AddTransient<FlashProgressWindow>();
    }
}
```

**Lifetimes:**
| Lifetime | Cuándo |
|----------|--------|
| Singleton | Servicios de estado global (watchers, navigation, ShellViewModel) |
| Transient | ViewModels de página, windows secundarios |
| Scoped | **Evitar** — no existe request scope en WinUI |

### A.6 Navegación

**Patrón: `NavigationView` (shell) + `Frame` (contenido)**

```xml
<NavigationView PaneDisplayMode="Left" IsBackButtonVisible="Collapsed">
    <NavigationView.MenuItems>
        <NavigationViewItem Content="General" Tag="DeviceGeneral" Icon="CellPhone"/>
        <NavigationViewItem Content="Licencias" Tag="Licenses" Icon="Document"/>
    </NavigationView.MenuItems>
    <Frame x:Name="ContentFrame"/>
</NavigationView>
```

```csharp
// NavigationService.cs
public bool Navigate<TPage>(object? parameter = null) where TPage : Page
    => _frame?.Navigate(typeof(TPage), parameter) ?? false;
```

**Cross-ViewModel messaging:** `WeakReferenceMessenger` con `record` inmutables.

```csharp
// Mensaje
public sealed record DeviceConnectedMessage(string DeviceId, string? VolumeLabel)
    : ValueChangedMessage<string>(DeviceId);

// Emisor (desde Platform/)
WeakReferenceMessenger.Default.Send(new DeviceConnectedMessage(id, label));

// Receptor (ViewModel)
public sealed partial class DeviceViewModel : ObservableRecipient, IRecipient<DeviceConnectedMessage>
{
    public DeviceViewModel() { IsActive = true; }
    public void Receive(DeviceConnectedMessage m) => LoadDevice(m.Value);
}
```

### A.7 Manejo de ventanas

**Ventana principal:** title bar custom con `ExtendsContentIntoTitleBar` + `SetTitleBar`. MicaBackdrop como fondo. Tamaño inicial ~1160×760, mínimo ~960×640.

**Ventanas modales (DFU):** `Window` nueva con `OverlappedPresenter.IsModal = true` + owner HWND. **NO** `ContentDialog` para flasheo (es operación larga y no debe cerrarse por accidente). Manejar `AppWindow.Closing` para bloquear cierre durante DFU.

**Ventanas ligeras (confirmaciones, licencias):** `ContentDialog` con `XamlRoot` obligatorio en WinUI 3.

**UAC:** proceso principal con `asInvoker`. Helper elevado separado (`AuraStudio.Helper.exe`) con manifest `requireAdministrator`. Se lanza solo para la operación que necesita permisos.

### A.8 Operaciones asíncronas

**Patrón para todo I/O largo (DFU, sync, detección):**

```csharp
// Servicio — I/O sin tocar UI
await Task.Run(async () => {
    var blocks = await ReadBlocksAsync(token).ConfigureAwait(false);
    for (int i = 0; i < blocks.Length; i++) {
        token.ThrowIfCancellationRequested();
        await WriteBlockAsync(blocks[i], token).ConfigureAwait(false);
        progress.Report((i + 1) * 100.0 / blocks.Length);
    }
}, token).ConfigureAwait(false);
```

**Reglas:**
- Servicios usan `ConfigureAwait(false)` — no capturan contexto UI
- ViewModels capturan contexto vía `Progress<double>` (creado en hilo UI → callback en UI)
- `DispatcherQueue.TryEnqueue` solo en el borde (callbacks de eventos Win32 que llegan desde otro hilo)
- Nunca `BackgroundWorker` (obsoleto), nunca `Task.Run(() => { /* UI */ })`

### A.9 Detección USB en Windows

**`DeviceWatcher`** encapsula `WM_DEVICECHANGE` via subclass de WndProc:

```csharp
// Platform/DeviceWatcher.cs
private nint WndProc(nint hWnd, uint msg, nint wParam, nint lParam)
{
    if (msg == 0x0219 /* WM_DEVICECHANGE */)
    {
        // Parsea DEV_BROADCAST_HDR, resuelve DeviceId + VolumeLabel
        // Marshaling a UI thread via DispatcherQueue.TryEnqueue
        WeakReferenceMessenger.Default.Send(new DeviceConnectedMessage(...));
    }
    return CallWindowProc(_oldWndProc, hWnd, msg, wParam, lParam);
}
```

**Alternativa WinRT pura:** `Windows.Devices.Enumeration.DeviceWatcher` con AQS para USB — más idiomático pero menos fiable para volúmenes RAW de iPod. Evaluar como fase 2; WndProc es el fallback probado.

### A.10 Testing

| Capa | Estrategia | Runner |
|------|-----------|--------|
| `AuraStudio.Core` | xUnit + datos sintéticos | `dotnet test` en la Mac |
| ViewModels | xUnit + Moq (mock de interfaces) | `dotnet test` en la Mac |
| `Platform/` | **Integration** en VM Windows (P/Invoke, UAC, USB) | `[Trait("Category","Integration")]` |
| Conversores | Tests directos | `dotnet test` |

```bash
dotnet test --filter "Category!=Integration"   # CI rápido (Mac)
dotnet test --filter "Category=Integration"    # nightly en VM
```

---

## B. Fluent 2 Aplicado a Aura Studio

### B.1 Tokens del sistema

| Elemento | Recurso WinUI 3 |
|----------|----------------|
| Fuente | Segoe UI Variable (incluida en Windows 11; fallback Segoe UI en 10) |
| Title | `{StaticResource TitleTextBlockStyle}` (28px, SemiBold) |
| Subtitle | `{StaticResource SubtitleTextBlockStyle}` (20px, SemiBold) |
| Body | `{StaticResource BodyTextBlockStyle}` (14px, Normal) |
| Body Strong | `{StaticResource BodyStrongTextBlockStyle}` (14px, SemiBold) |
| Caption | `{StaticResource CaptionTextBlockStyle}` (12px, Normal) |
| Espaciado | Múltiplos de 4px: xs=8, s=12, m=16, l=24, xl=32 |
| Elevated BG | `{ThemeResource CardBackgroundFillColorDefaultBrush}` |
| Elevated border | `{ThemeResource CardStrokeColorDefaultBrush}` |

**Regla:** no inventar valores — usar siempre `ThemeResource` y los estilos predefinidos.

### B.2 Paleta de marca Aura

Definida en `App.xaml` dentro de `ThemeDictionaries` (soporte light/dark automático):

```xml
<ResourceDictionary.ThemeDictionaries>
    <ResourceDictionary x:Key="Light">
        <Color x:Key="AuraPrimaryColor">#0078D4</Color>
        <Color x:Key="AuraPrimaryHoverColor">#106EBE</Color>
        <Color x:Key="AuraPrimaryPressedColor">#005A9E</Color>
    </ResourceDictionary>
    <ResourceDictionary x:Key="Dark">
        <Color x:Key="AuraPrimaryColor">#60CDFF</Color>
        <Color x:Key="AuraPrimaryHoverColor">#4CC2FF</Color>
        <Color x:Key="AuraPrimaryPressedColor">#99E4FF</Color>
    </ResourceDictionary>
</ResourceDictionary.ThemeDictionaries>
```

**Colores semánticos:** usar los del sistema — `SystemFillColorSuccessBrush` (éxito), `SystemFillColorCautionBrush` (warning), `SystemFillColorCriticalBrush` (error).

**Accent color:** usar `AccentFillColorDefaultBrush` del sistema para botones primarios e interactivos. La paleta Aura solo para elementos de marca (logo, iconos decorativos). No forzar un accent propio.

### B.3 Materiales visuales

| Superficie | Material | Uso en Aura |
|------------|----------|-------------|
| Ventana principal | `MicaBackdrop` | Fondo translúcido del escritorio |
| Sidebar (NavigationView) | Mica automático | Pane izquierdo |
| Diálogos modales | `AcrylicBrush` (Backdrop) | Transparencia borrosa |
| Flyouts/menus | `AcrylicBrush` | Overlay semi-transparente |
| Cards de contenido | `CardBackgroundFillColorDefaultBrush` + corner radius 8 | Secciones de contenido |

**No abusar de elevation:** mantener jerarquía visual limpia. Shadow solo en cards elevadas.

### B.4 Iconografía

**Segoe Fluent Icons** (incluido en WinUI 3, sin dependencia extra):

```xml
<SymbolIcon Symbol="DeviceMobile24"/>
<SymbolIcon Symbol="ArrowSync24"/>
<SymbolIcon Symbol="CheckmarkCircle24"/>
<SymbolIcon Symbol="Warning24"/>
<SymbolIcon Symbol="Settings24"/>
```

| Función | Symbol |
|---------|--------|
| iPod detectado | `DeviceMobile24` |
| Sincronizar | `ArrowSync24` |
| Flashear | `ArrowDownload24` |
| Éxito | `CheckmarkCircle24` |
| Error | `DismissCircle24` |
| Warning | `Warning24` |
| Configuración | `Settings24` |
| Licencias | `DocumentText24` |
| USB | `Usb24` |
| Música | `MusicNote224` |
| Cancelar | `Dismiss24` |
| Reintentar | `ArrowClockwise24` |

**No instalar** `Microsoft.FluentUI.SystemIcons.WinUI` a menos que se necesite un icono que Segoe Fluent Icons no tenga. Segoe basta para v1.

### B.5 Layouts por pantalla (WinUI 3)

#### 1. Detección de dispositivos

- `NavigationView` como shell (sidebar izquierda)
- `SymbolIcon` grande (64px) + `SubtitleTextBlockStyle` centrados = empty state
- `ListView` para lista de dispositivos detectados
- Estados: spinner (`ProgressRing` indeterminado), check verde, warning `InfoBar`

#### 2. Progreso de flasheo DFU

- Ventana modal `Window` (no ContentDialog)
- `ProgressRing` + `SubtitleTextBlockStyle` para título de operación
- `ProgressBar` determinado (0-100) con `Value` bind a ViewModel
- `TextBlock` para texto de fase/estado
- `Expander` "Ver detalles" → log en `ScrollViewer` con fuente monoespaciada
- Botón "Cancelar" (`SecondaryButtonStyle`)
- Bloquear cierre accidental (`AppWindow.Closing` + `e.Cancel = true` si `IsFlashing`)

#### 3. Confirmación destructiva

- `ContentDialog` con `InfoBar` severity="Warning" inline
- Texto con nombre del dispositivo, serial, tamaño
- Botón primario rojo (`SystemFillColorCriticalBrush`)
- Botón close "Cancelar"

#### 4. Pantalla de licencias

- `ScrollViewer` vertical + `StackPanel` MaxWidth 800, centrado
- Título `TitleTextBlockStyle`, texto `BodyTextBlockStyle`
- `Expander` por componente (Rockbox/GPLv2, etc.)
- Links con `Button` estilo `LinkButtonStyle`

#### 5. Configuración (post-v1)

- `Expander` por sección (General, Biblioteca, Avanzado)
- `ToggleSwitch` para on/off, `ComboBox` para opciones, `TextBox` + `Button` para rutas

#### 6. Error

- `InfoBar` severity="Error" arriba (banner)
- `SymbolIcon` grande centrado + `TitleTextBlockStyle` + texto descriptivo
- Botón "Reintentar" (`AccentButtonStyle`) + "Ver detalles"

#### 7. Dispositivo no encontrado (empty state)

- `SymbolIcon` grande (64px, `TextFillColorTertiaryBrush`)
- Título + descripción centrados
- `Border` con `CardBackgroundFillColorSecondaryBrush` para instrucciones paso a paso
- Botón "Buscar dispositivos" (`AccentButtonStyle`)

### B.6 Accesibilidad

- **Siempre `ThemeResource`** (nunca colores hardcodeados) → High Contrast automático
- **`AutomationProperties.Name`** en todo control interactivo
- **`AutomationProperties.HelpText`** en botones y toggles
- **`UseSystemFocusVisuals="True"`** en todos los controles
- **Focus trapping** automático en `ContentDialog`
- **MinWidth 800 + MinHeight 600** en la ventana principal

### B.7 Responsive

- `NavigationView` con `PaneDisplayMode="Left"` se adapta (minimal en ventanas estrechas)
- Contenido centrado con `MaxWidth` y `HorizontalAlignment="Center"`
- App no necesita ser fully responsive — solo no romperse al redimensionar
- Detectar `Window.SizeChanged` para layouts condicionales si hace falta

---

## C. Inventario de Pantallas macOS → Windows

### Tabla resumen (alcance v1)

| # | Pantalla macOS | Archivo | v1 | Dependencia Windows |
|---|---------------|---------|----|----|
| 1 | Welcome | WelcomeView.swift | ✅ | — |
| 2 | Permissions | PermissionsView.swift | ✅⚠️ | UAC (PrivilegedRunner) |
| 3 | Detect Device | DetectDeviceView.swift | ✅⚠️ | DeviceWatcher (WM_DEVICECHANGE) + VolumeManager |
| 4 | Enter DFU | EnterDFUView.swift | ✅⚠️ | DFU detection (mks5lboot --dfuscan) |
| 5 | Installing | InstallingView.swift | ✅⚠️ | DfuFlashRunner (mks5lboot.exe) |
| 6 | Await Bootloader USB | AwaitBootloaderUSBView.swift | ✅⚠️ | DeviceWatcher + USB descriptor check |
| 7 | Done | DoneView.swift | ✅ | — |
| 8 | General (Device) | DeviceGeneralView.swift | ❌ | Post-v1 |
| 9 | Licenses | LicensesView.swift | ✅ | — |
| 10-20 | Media, Themes, Settings | (varios) | ❌ | Post-v1 |

✅ = UI pura, ⚠️ = requiere reimplementación de API de plataforma, ❌ = post-v1

### Pantallas v1: descripción y mapeo

#### 1. Welcome — `WelcomePage.xaml`
- **Función:** Selector de modo Instalar vs Restaurar. Advertencia roja de que el firmware original se borra. Casilla de confirmación (ST-053).
- **Servicios:** — (UI pura)
- **WinUI:** `RadioButton` o `ListView` para modo selector. `CheckBox` para confirmación. `InfoBar` severity="Warning" para la advertencia. Botones Atrás/Continuar.

#### 2. Permissions — `PermissionsPage.xaml`
- **Función:** Explica qué necesita la app (acceso a disco, permisos admin). Botón "Permitir" que dispara UAC. **Nunca pedir sin explicar primero** (regla CLAUDE.md).
- **Servicios:** `IPrivilegedRunner` → UAC
- **WinUI:** Texto explicativo largo + `Button` "Permitir" (`AccentButtonStyle`). La explicación va ANTES del prompt UAC — en Windows, UAC es un diálogo del sistema; la app no controla su contenido, pero SÍ puede mostrar su propia pantalla explicativa antes de lanzarlo.

#### 3. Detect Device — `DetectDevicePage.xaml`
- **Función:** Spinner mientras se espera conexión. Estados: detectando, FAT32 OK, FAT32 NO, sin filesystem. Auto-advance cuando detecta.
- **Servicios:** `IDeviceDetector` → `DeviceWatcher` (WM_DEVICECHANGE) + `VolumeManager` (lectura tabla particiones)
- **WinUI:** `ProgressRing` indeterminado + texto de estado. `InfoBar` warning para FAT32 no. Auto-avance via `WeakReferenceMessenger` (mensaje `DeviceConnectedMessage` → `InstallerViewModel` navega sola).

#### 4. Enter DFU — `EnterDFUPage.xaml`
- **Función:** Instrucciones paso-a-paso para entrar a DFU (4 pasos). Badge que cambia: esperando → DFU detectado → error (con motivo).
- **Servicios:** `IDfuFlashRunner` (`--dfuscan`) o `DeviceWatcher` detectando VID/PID DFU (`0x05AC`/`0x1201`)
- **WinUI:** Lista de pasos con `TextBlock` + `SymbolIcon`. `ProgressBar` indeterminado debajo. Badge de estado que cambia según `InstallerViewModel.dfuState`.

#### 5. Flashing — `FlashingPage.xaml`
- **Función:** Progreso de flasheo. **No hay botón cancelar** (D-188: mks5lboot escribiendo NOR no se puede detener sin riesgo). Advertencia "No desconectes el iPod".
- **Servicios:** `IDfuFlashRunner` (`--flash-only` o `--bl-inst`) via helper elevado
- **WinUI:** Ventana modal `Window` (no ContentDialog). `ProgressBar` + `TextBlock` de fase + `ProgressRing`. `InfoBar` severity="Warning" como recordatorio. Bloquear cierre de ventana.

#### 6. Await Bootloader — `AwaitBootloaderPage.xaml`
- **Función:** Solo en modo "Solo Aura" (ST-017). Spinner esperando que el iPod reaparezca como disco con bootloader Rockbox atendiendo USB. Auto-advance.
- **Servicios:** `DeviceWatcher` + USB descriptor check (`Rockbox.org` en vendor)
- **WinUI:** `ProgressRing` + texto. Auto-avance via mensaje `DeviceConnectedMessage` cuando USB atiende Rockbox.

#### 7. Done — `DonePage.xaml`
- **Función:** Resumen "✅ Firmware instalado". Opciones: "Abrir Extras", "Ir a la biblioteca", "Listo". Caso especial: botón "¿No arranca?" si asumió bootloader sin verificar.
- **Servicios:** — (UI pura)
- **WinUI:** `SymbolIcon` checkmark grande + `TitleTextBlockStyle` + botones de acción.

#### 9. Licenses — `LicensesPage.xaml`
- **Función:** Aviso GPL v2 con componentes y atribuciones.
- **Servicios:** — (UI pura, lee archivos embebidos)
- **WinUI:** `ScrollViewer` + `StackPanel` + `Expander` por componente. Ver §B.5.4.

### ViewModels críticos para v1

| ViewModel | Duración | Datos | Servicios |
|-----------|----------|-------|-----------|
| `InstallerViewModel` | App-level (singleton), sobrevive navegación | Paso actual, modo, nombre dispositivo, estado DFU | — (consume servicios) |
| `FlashViewModel` | Transient (por operación) | Progress, phase, status | `IFirmwareService` |
| `DeviceViewModel` | Singleton | Dispositivo actual, estado conexión | `IUsbDeviceWatcher` |

**`InstallerViewModel` es el VM más complejo:** mantiene el estado del asistente lineal (7 pasos) y sobrevive a la destrucción/recreación de páginas. Se registra como singleton en DI. Cada página lo resuelve en su constructor y lo bindea.

### Modelos a portar de Swift

| Modelo Swift | C# equivalente | Notas |
|-------------|---------------|-------|
| `InstallerMode` (enum) | `enum InstallerMode { Install, Restore }` | — |
| `InstallerStep` (enum) | `enum InstallerStep { Welcome, Permissions, ... }` | 7 valores |
| `DiskCandidateInfo` | `DiskCandidateInfo` | ✅ ya portado |
| `DiskIdentificationResult` | `DiskIdentificationResult` | ✅ ya portado |
| `USBDeviceIdentity` | `USBDeviceIdentity` | ✅ ya portado |
| `RunningFirmware` | `RunningFirmware` | ✅ ya portado |
| `DeviceState` (enum) | `enum DeviceState` | notConnected, detecting, diskMode, dfuMode |

---

## D. Checklist de ejecución desatendida (Fase II)

Antes de arrancar la Fase II, verificar:

- [ ] Se confirmó el TFM soportado por WASDK 2.4 en la VM (net10.0-windows o net8.0-windows)
- [ ] `brew install mingw-w64` listo para cross-compile de `mks5lboot.exe`
- [ ] `AuraStudio.Core` ya tiene los 4 módulos portados con tests verdes (19/19)
- [ ] Este documento de investigación aprobado (sin ambigüedades abiertas)

Durante la ejecución:

- [ ] `AuraStudio.Core` completo (todos los módulos del grupo A del plan)
- [ ] `AuraStudio.Win` escrito con TFM confirmado
- [ ] MVVM con CommunityToolkit.Mvvm 8.4 (partial classes, [ObservableProperty], [RelayCommand])
- [ ] DI con ServiceCollection (sin IHost)
- [ ] Navegación NavigationView + Frame + NavigationService
- [ ] Ventana principal: MicaBackdrop, title bar custom, tamaño 1160×760
- [ ] Ventanas modales (DFU): Window con IsModal=true + owner HWND
- [ ] UAC: helper separado con manifest requireAdministrator
- [ ] DeviceWatcher: WM_DEVICECHANGE via WndProc subclass + DispatcherQueue.TryEnqueue
- [ ] FirmwareService: Task.Run + ConfigureAwait(false) + IProgress<double> + CancellationToken
- [ ] WeakReferenceMessenger con records inmutables
- [ ] AutomationProperties en todo control interactivo
- [ ] ThemeResource (nunca colores hardcodeados)
- [ ] `mks5lboot.exe` cross-compilado en artifacts/
- [ ] `FirmwareFetch.ps1` escrito
- [ ] `MAPPING.md` actualizado
- [ ] `NOTAS-SIN-COMPILAR.md` en AuraStudio.Win/ con supuestos
