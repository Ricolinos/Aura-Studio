using Microsoft.UI.Xaml;
using Microsoft.Extensions.DependencyInjection;
using System;
using System.Globalization;
using System.Linq;
using AuraStudio.Core.Resources;

namespace AuraStudio.App;

/// <summary>
/// Punto de entrada de la aplicación Aura Studio para Windows.
/// Configura DI y abre la ventana principal.
/// </summary>
public sealed partial class App : Application
{
    public static IServiceProvider Services { get; private set; } = null!;

    public App()
    {
        this.InitializeComponent();

        // Lo primero de todo: sin esto, cualquier excepción que escape de un
        // manejador de interfaz cierra la app SIN dejar rastro (fue el crash al
        // instalar Metro después de Aura, del que solo quedó una entrada del
        // Visor de eventos con un código COM).
        AuraStudio.App.Services.CrashReporter.Install(this);

        ConfigureServices();

        // Y el idioma, ANTES de que exista una sola vista (ST-247, B7b).
        // `x:Bind` resuelve el texto una vez, al construir la página: si la
        // cultura se fijara después, la primera pantalla quedaría en el idioma
        // anterior y las siguientes no — un revoltijo que además solo se ve al
        // abrir la app, que es cuando nadie está mirando el código.
        ApplyLanguage();
    }

    /// <summary>
    /// Deja la cultura en el idioma elegido, o en el de Windows si no hay
    /// ninguno elegido.
    ///
    /// <para>Se tocan las dos culturas, y por motivos distintos: la de interfaz
    /// decide de qué satélite salen los textos, y la de formato decide cómo se
    /// escriben las fechas y los números. Una app en inglés con los miles
    /// separados a la española se lee mal aunque cada palabra esté bien.</para>
    ///
    /// <para>Un idioma guardado que ya no se ofrece —o que nunca existió, si
    /// alguien editó el archivo de preferencias a mano— se ignora y se cae al
    /// del sistema. No se avisa: no es culpa del usuario y no hay nada que
    /// pueda hacer al respecto.</para>
    /// </summary>
    private static void ApplyLanguage()
    {
        string chosen = Services.GetRequiredService<AuraStudio.App.Services.IAppPreferences>().Language;
        if (chosen.Length == 0) return;
        if (AppLanguages.Available.All(language => language.Culture != chosen)) return;

        var culture = new CultureInfo(chosen);

        CultureInfo.DefaultThreadCurrentUICulture = culture;
        CultureInfo.DefaultThreadCurrentCulture = culture;
        CultureInfo.CurrentUICulture = culture;
        CultureInfo.CurrentCulture = culture;
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        // Se captura ANTES de crear la ventana: cualquier servicio que resuelva
        // DI después ya lo encuentra, y así nadie tiene que adivinar en qué hilo
        // se construyó.
        UiDispatcher = Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread();

        // ST-200 (PLAN-studio-rendimiento-2.md W0): vigilante de bloqueos del
        // hilo de UI, solo con AURA_WATCHDOG=1 y solo en DEBUG -- no hace
        // nada en Release ni sin la variable.
        if (UiDispatcher is not null) AuraStudio.App.Services.UiThreadWatchdog.StartIfRequested(UiDispatcher);

        var window = new MainWindow();
        MainWindow = window;
        MainWindowHandle = WinRT.Interop.WindowNative.GetWindowHandle(window);
        window.Activate();
    }

    /// <summary>
    /// La cola del hilo de interfaz. Todo lo que llegue de un hilo de fondo y
    /// vaya a tocar algo enlazado tiene que pasar por acá.
    ///
    /// <para>No es una comodidad: hacerlo desde otro hilo cierra la app <b>sin
    /// ningún mensaje</b>, con una excepción dentro de <c>combase.dll</c> que
    /// solo aparece en el Visor de eventos. Fue el crash real al instalar Metro
    /// después de Aura.</para>
    /// </summary>
    public static Microsoft.UI.Dispatching.DispatcherQueue? UiDispatcher { get; private set; }

    public Window? MainWindow { get; private set; }

    /// <summary>
    /// El <c>HWND</c> de la ventana principal. Los selectores de archivo de
    /// WinRT lo necesitan en una app sin empaquetar: sin él no saben a qué
    /// ventana pertenecen y lanzan al abrirse.
    /// </summary>
    public static IntPtr MainWindowHandle { get; private set; }

    private void ConfigureServices()
    {
        var services = new ServiceCollection();

        // Servicios de plataforma y sesión
        //
        // ST-169: `AURA_STUDIO_PREFERENCES` apunta las preferencias a otro
        // archivo. Es una **ayuda de verificación, no una función del
        // producto**: sin ella no hay forma de probar la app sin escribir en el
        // archivo real del usuario, porque `Environment.GetFolderPath` no lee
        // `%LOCALAPPDATA%`. Usa el constructor con ruta que `AppPreferences` ya
        // tenía para sus pruebas. Sin la variable, todo queda como estaba.
        string? preferencesOverride = Environment.GetEnvironmentVariable("AURA_STUDIO_PREFERENCES");
        if (string.IsNullOrWhiteSpace(preferencesOverride))
        {
            services.AddSingleton<Services.IAppPreferences, Services.AppPreferences>();
        }
        else
        {
            services.AddSingleton<Services.IAppPreferences>(
                _ => new Services.AppPreferences(preferencesOverride));
        }
        services.AddSingleton<Services.IUsbDeviceWatcher, Services.UsbDeviceWatcher>();
        services.AddSingleton<Services.IDeviceSessionService, Services.DeviceSessionService>();
        services.AddSingleton<Services.IVolumeService, Services.VolumeService>();
        services.AddSingleton<Services.IThemeService, Services.ThemeService>();
        services.AddSingleton<Platform.CredentialStore>();
        services.AddSingleton<Services.IEnrichmentService, Services.EnrichmentService>();
        services.AddSingleton<Services.ISyncService, Services.SyncService>();
        services.AddSingleton<Services.IFirmwareArtifactsProvider, Services.FirmwareArtifactsProvider>();
        // D-185: una sola verdad sobre si el instalador está activo, compartida
        // por todo lo que pueda querer tomar la pantalla o escribir en el iPod.
        services.AddSingleton<AuraStudio.Core.Installer.InstallerFlowRegistry>();
        services.AddSingleton<Services.IAppleDeviceSupport, Platform.AppleDeviceSupport>();
        services.AddSingleton<Platform.IPrivilegedOperationLog, Platform.PrivilegedOperationLog>();
        services.AddSingleton<Services.IPrivilegedRunner, Platform.PrivilegedRunner>();
        // El runner resuelve los artefactos en cada operación (no una vez al
        // construirse): el directorio puede repoblarse mientras la app corre.
        services.AddSingleton<Services.IDfuFlashRunner>(sp =>
            new Platform.DfuFlashRunner(
                () => sp.GetRequiredService<Services.IFirmwareArtifactsProvider>().Current()));
        services.AddSingleton<Services.IFirmwareTreeInstaller, Services.FirmwareTreeInstaller>();
        services.AddSingleton<Services.IDeviceSafetyValidator, Services.DeviceSafetyValidator>();

        // ViewModels.
        //
        // Los que observan la sesión del dispositivo son SINGLETON a propósito
        // (mismo motivo que D-187 en macOS, donde el ViewModel del instalador
        // vive en el contenedor raíz y no en su vista): las páginas se
        // reconstruyen en cada navegación, y un ViewModel transitorio suscrito
        // a `IDeviceSessionService` dejaría una suscripción viva por cada
        // visita — fuga y trabajo duplicado. Con singleton hay una sola
        // suscripción y el estado de la pantalla sobrevive al ir y volver.
        services.AddSingleton<ViewModels.ShellViewModel>();
        services.AddSingleton<ViewModels.DeviceListViewModel>();
        services.AddSingleton<Services.AppUpdateService>();
        services.AddSingleton<ViewModels.SettingsViewModel>();
        services.AddTransient<ViewModels.LicensesViewModel>();
        services.AddSingleton<ViewModels.InstallerViewModel>();
        services.AddSingleton<ViewModels.SyncViewModel>();
        services.AddSingleton<Services.ILibraryProcessor, Services.LibraryProcessor>();

        // ST-203: uno solo para toda la app. Lo que la app hace por su cuenta se
        // anuncia en un único lugar, y la franja de estado de cualquier sección
        // muestra el mismo.
        services.AddSingleton<Services.BackgroundTaskCenter>();

        services.AddSingleton<ViewModels.LibraryViewModel>();
        services.AddSingleton<ViewModels.SongsViewModel>();
        services.AddSingleton<ViewModels.MediaGridViewModel>();
        services.AddSingleton<ViewModels.ArtistsViewModel>();
        services.AddSingleton<AuraStudio.Core.Installer.IReleaseCacheStore, Services.ReleaseCacheStore>();
        services.AddSingleton<ViewModels.ExtrasViewModel>();
        services.AddSingleton<ViewModels.PlaylistsViewModel>();
        services.AddSingleton<ViewModels.SimilarItemsViewModel>();
        services.AddTransient<ViewModels.ThemesViewModel>();

        Services = services.BuildServiceProvider();
    }
}
