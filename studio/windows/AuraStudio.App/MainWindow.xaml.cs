using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using System;
using System.Runtime.InteropServices;
using Windows.Graphics;
using WinRT.Interop;
using AuraStudio.App.Services;

namespace AuraStudio.App;

/// <summary>
/// Ventana principal. Se ocupa de lo que es propio de una ventana y de nada
/// más: respaldo Mica (con degradación a acrílico o sólido), tema claro/oscuro
/// con anulación desde Ajustes, tamaño y posición persistidos, y el WndProc
/// subclaseado que captura WM_DEVICECHANGE — el equivalente Windows de lo que
/// en macOS hacen IOKit/DiskArbitration.
///
/// La interfaz vive en <see cref="Views.ShellPage"/>.
/// </summary>
public sealed partial class MainWindow : Window
{
    private const int MinWidth = 900;
    private const int MinHeight = 620;
    private const int DefaultWidth = 1180;
    // Alto suficiente para que la barra de navegación muestre las tres
    // secciones de biblioteca expandidas más Extras sin tener que desplazarla.
    private const int DefaultHeight = 860;

    private readonly IDeviceSessionService _session;
    private readonly IAppPreferences _preferences;
    private readonly IntPtr _hwnd;
    private WindowSubclassHook? _subclassHook;

    // Debounce + reintento de montaje: DBT_DEVICEARRIVAL llega en ráfaga y
    // la letra de unidad puede tardar 1–3 s en aparecer. Todo en hilo UI con
    // DispatcherQueueTimer (one-shot) para no introducir threads nuevos.
    private readonly DispatcherQueueTimer _arrivalDebounce;
    private readonly DispatcherQueueTimer _mountRetry;
    private bool _debounceArmed;

    public MainWindow()
    {
        this.InitializeComponent();

        _session = App.Services.GetRequiredService<IDeviceSessionService>();
        _preferences = App.Services.GetRequiredService<IAppPreferences>();
        _preferences.Changed += OnPreferenceChanged;

        ApplyIcon();
        ApplyBackdrop();
        ApplyTheme();
        RestorePlacement();

        // El HWND existe desde que se construye la Window (no hay evento
        // Loaded en Window): el hook se instala aquí mismo.
        _hwnd = WindowNative.GetWindowHandle(this);
        _subclassHook = new WindowSubclassHook(_hwnd, WndProc);
        _subclassHook.Install();

        // Timers de debounce y reintento (creados en el hilo UI del constructor).
        var queue = DispatcherQueue.GetForCurrentThread();
        _mountRetry = queue.CreateTimer();
        _mountRetry.Interval = TimeSpan.FromMilliseconds(2500);
        _mountRetry.IsRepeating = false;
        _mountRetry.Tick += (_, _) => EnqueueDeviceChange(true); // segunda pasada: completa VolumePath/enriquecimiento

        _arrivalDebounce = queue.CreateTimer();
        _arrivalDebounce.Interval = TimeSpan.FromMilliseconds(750);
        _arrivalDebounce.IsRepeating = false;
        _arrivalDebounce.Tick += (_, _) =>
        {
            _debounceArmed = false;
            EnqueueDeviceChange(true);          // primera pasada: ya tiene VID/PID
            _mountRetry.Start();                // 2.5 s para recoger letra tardía
        };

        this.Closed += MainWindow_Closed;

        // El primer sondeo de discos va DESPUÉS de que la ventana esté en
        // pantalla, nunca durante la construcción: con un disco USB en mal
        // estado la enumeración de WMI se bloquea en código nativo, y hacerlo
        // acá dejaba la app creada pero invisible para siempre.
        this.Activated += MainWindow_FirstActivated;
    }

    private void MainWindow_FirstActivated(object sender, WindowActivatedEventArgs args)
    {
        this.Activated -= MainWindow_FirstActivated;
        _session.StartInitialScan();
    }

    // MARK: - Presentación

    /// <summary>
    /// Icono de la barra de título y de la barra de tareas. El del `.exe` que
    /// muestra el Explorador lo pone `&lt;ApplicationIcon&gt;` en el csproj; este
    /// es el de la ventana, que se carga por ruta en runtime.
    ///
    /// Si el archivo no está (una build sin correr `scripts\Make-Icon.ps1`), la
    /// ventana se queda con el icono por omisión de WinUI: un icono es una
    /// mejora, nunca un motivo para no abrir.
    /// </summary>
    private void ApplyIcon()
    {
        try
        {
            string path = Path.Combine(AppContext.BaseDirectory, "Assets", "AuraStudio.ico");
            if (File.Exists(path)) AppWindow.SetIcon(path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            // Sin icono se ve peor; sin ventana, no se ve nada.
        }
    }

    /// <summary>
    /// Mica es de Windows 11. En Windows 10 (el mínimo del proyecto es
    /// 10.0.19041) no existe: se cae a acrílico de escritorio y, si tampoco,
    /// al fondo sólido del sistema. Nunca queda una ventana transparente.
    /// </summary>
    private void ApplyBackdrop()
    {
        if (MicaController.IsSupported())
        {
            SystemBackdrop = new MicaBackdrop();
        }
        else if (DesktopAcrylicController.IsSupported())
        {
            SystemBackdrop = new DesktopAcrylicBackdrop();
        }
        else if (Content is Control solid)
        {
            solid.Background = (Brush)Application.Current.Resources["ApplicationPageBackgroundThemeBrush"];
        }
    }

    /// <summary>
    /// `ElementTheme.Default` sigue al sistema (claro/oscuro y contraste alto);
    /// Ajustes puede fijarlo solo para esta app. La barra de título se pide
    /// aparte: es del sistema, no del árbol XAML, así que sin esto una app en
    /// oscuro sobre un Windows en claro queda con el marco del color contrario.
    /// </summary>
    private void ApplyTheme()
    {
        if (Content is not FrameworkElement root) return;

        root.RequestedTheme = _preferences.Theme switch
        {
            AppTheme.Light => ElementTheme.Light,
            AppTheme.Dark => ElementTheme.Dark,
            _ => ElementTheme.Default
        };

        AppWindow.TitleBar.PreferredTheme = _preferences.Theme switch
        {
            AppTheme.Light => TitleBarTheme.Light,
            AppTheme.Dark => TitleBarTheme.Dark,
            _ => TitleBarTheme.UseDefaultAppMode
        };
    }

    private void OnPreferenceChanged(object? sender, string propertyName)
    {
        if (propertyName == nameof(IAppPreferences.Theme)) ApplyTheme();
    }

    // MARK: - Tamaño y posición

    /// <summary>
    /// Restaura lo guardado, pero solo si sigue cabiendo en una pantalla que
    /// exista hoy: con un monitor desconectado, la posición vieja dejaría la
    /// ventana fuera de vista y sin forma de recuperarla con el mouse.
    /// </summary>
    private void RestorePlacement()
    {
        var saved = _preferences.WindowPlacement;

        if (saved is { } placement && IsOnAVisibleDisplay(placement))
        {
            AppWindow.MoveAndResize(new RectInt32(
                placement.X, placement.Y,
                Math.Max(placement.Width, MinWidth),
                Math.Max(placement.Height, MinHeight)));

            if (placement.Maximized && AppWindow.Presenter is OverlappedPresenter maximize)
            {
                maximize.Maximize();
            }
            return;
        }

        AppWindow.Resize(new SizeInt32(DefaultWidth, DefaultHeight));
    }

    private static bool IsOnAVisibleDisplay(WindowPlacement placement)
    {
        if (placement.Width < MinWidth || placement.Height < MinHeight) return false;

        var rect = new RectInt32(placement.X, placement.Y, placement.Width, placement.Height);
        var area = DisplayArea.GetFromRect(rect, DisplayAreaFallback.Nearest);
        var work = area.WorkArea;

        // Basta con que una franja visible de la barra de título quede dentro
        // del área de trabajo para que se pueda volver a mover con el mouse.
        int visibleLeft = Math.Max(placement.X, work.X);
        int visibleRight = Math.Min(placement.X + placement.Width, work.X + work.Width);
        int visibleTop = Math.Max(placement.Y, work.Y);
        int visibleBottom = Math.Min(placement.Y + placement.Height, work.Y + work.Height);

        return visibleRight - visibleLeft >= 120 && visibleBottom - visibleTop >= 40;
    }

    private void SavePlacement()
    {
        bool maximized = AppWindow.Presenter is OverlappedPresenter
        {
            State: OverlappedPresenterState.Maximized
        };

        // Maximizada, la posición y el tamaño reportados son los de la pantalla
        // completa: se conserva lo anterior para que al restaurar no quede
        // pegada a los bordes.
        if (maximized && _preferences.WindowPlacement is { } previous)
        {
            _preferences.WindowPlacement = previous with { Maximized = true };
            return;
        }

        _preferences.WindowPlacement = new WindowPlacement(
            AppWindow.Position.X, AppWindow.Position.Y,
            AppWindow.Size.Width, AppWindow.Size.Height,
            maximized);
    }

    // MARK: - Ciclo de vida

    private void MainWindow_Closed(object sender, WindowEventArgs args)
    {
        SavePlacement();

        // ST-169: si esta app detuvo el servicio de Apple, se reanuda al
        // cerrar. Es el camino rápido, no la garantía — cerrar bien es
        // justamente lo que no pasa en un cuelgue, y para eso está la tarea
        // programada que el lado elevado crea ANTES de detener nada.
        App.Services.GetRequiredService<ViewModels.InstallerViewModel>()
            .ResumeAppleServiceIfPausedAsync()
            .ContinueWith(_ => { }, TaskScheduler.Default);

        _preferences.Changed -= OnPreferenceChanged;
        _arrivalDebounce.Stop();
        _mountRetry.Stop();
        _subclassHook?.Uninstall();
        _subclassHook = null;
    }

    // MARK: - WM_DEVICECHANGE

    private void EnqueueDeviceChange(bool arrived)
    {
        DispatcherQueue.TryEnqueue(() => _session.OnDeviceChange(arrived));
    }

    private IntPtr WndProc(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam)
    {
        const uint WM_DEVICECHANGE = 0x0219;
        const uint DBT_DEVICEARRIVAL = 0x8000;
        const uint DBT_DEVICEREMOVECOMPLETE = 0x8004;

        if (msg == WM_DEVICECHANGE)
        {
            if (wParam == (IntPtr)DBT_DEVICEARRIVAL)
            {
                // Colapsar la ráfaga de arrival; el reintento recogerá el
                // volumen que aparezca tarde.
                if (!_debounceArmed)
                {
                    _debounceArmed = true;
                    _arrivalDebounce.Start();
                }
                else
                {
                    // Ya hay uno armado: reiniciar la ventana de 750 ms.
                    _arrivalDebounce.Stop();
                    _arrivalDebounce.Start();
                }
            }
            else if (wParam == (IntPtr)DBT_DEVICEREMOVECOMPLETE)
            {
                // Remoción instantánea: sin debounce, parada inmediata.
                _arrivalDebounce.Stop();
                _mountRetry.Stop();
                _debounceArmed = false;
                EnqueueDeviceChange(false);
            }
        }

        return _subclassHook!.CallOriginalWndProc(hwnd, msg, wParam, lParam);
    }
}

/// <summary>
/// Subclaseo clásico de una ventana Win32 desde WinUI 3: reemplaza el WndProc
/// con SetWindowLongPtr(GWLP_WNDPROC) y reenvía todo lo demás al original con
/// CallWindowProcW. (No confundir con SetWindowSubclass de comctl32, que usa
/// otra firma de callback.)
/// </summary>
internal sealed partial class WindowSubclassHook : IDisposable
{
    internal delegate IntPtr WndProcDelegate(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);

    private const int GWLP_WNDPROC = -4;

    private readonly IntPtr _hwnd;
    private readonly WndProcDelegate _callback;

    // Mantiene vivo el delegate mientras el WndProc nativo lo apunta: si el
    // GC lo recolecta, la ventana llama a memoria liberada.
    private WndProcDelegate? _newWndProc;
    private IntPtr _oldWndProc;
    private bool _installed;

    public WindowSubclassHook(IntPtr hwnd, WndProcDelegate callback)
    {
        _hwnd = hwnd;
        _callback = callback;
    }

    public void Install()
    {
        if (_installed) return;

        _newWndProc = (hwnd, msg, wParam, lParam) => _callback(hwnd, msg, wParam, lParam);
        IntPtr newPtr = Marshal.GetFunctionPointerForDelegate(_newWndProc);
        _oldWndProc = SetWindowLongPtrW(_hwnd, GWLP_WNDPROC, newPtr);
        _installed = _oldWndProc != IntPtr.Zero;
        if (!_installed) _newWndProc = null;
    }

    public void Uninstall()
    {
        if (!_installed) return;
        SetWindowLongPtrW(_hwnd, GWLP_WNDPROC, _oldWndProc);
        _installed = false;
        _newWndProc = null;
    }

    /// <summary>Reenvía el mensaje al WndProc original de la ventana.</summary>
    public IntPtr CallOriginalWndProc(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam)
    {
        return CallWindowProcW(_oldWndProc, hwnd, msg, wParam, lParam);
    }

    public void Dispose() => Uninstall();

    [LibraryImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)]
    private static partial IntPtr SetWindowLongPtrW(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

    [LibraryImport("user32.dll", EntryPoint = "CallWindowProcW")]
    private static partial IntPtr CallWindowProcW(IntPtr lpPrevWndFunc, IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
}
