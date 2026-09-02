using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using AuraStudio.Core;
using AuraStudio.Core.Installer;
using AuraStudio.App.Resources;
using AuraStudio.App.Services;

namespace AuraStudio.App.ViewModels;

/// <summary>
/// El asistente de instalación. Port del flujo de `InstallerViewModel` de macOS,
/// con los mismos pasos (<see cref="InstallerStep"/>) y, sobre todo, las mismas
/// promesas:
///
/// <list type="bullet">
/// <item><b>Nada se toca sin explicar antes qué va a pasar.</b> El paso
/// `Permissions` describe la elevación **antes** de que aparezca el diálogo de
/// UAC — es la promesa textual que `PermissionsView` le hace al usuario en
/// macOS, y acá se cumple igual.</item>
/// <item><b>Confirmación explícita del disco</b> mostrando nombre, letra,
/// tamaño y bus antes de tocarlo.</item>
/// <item><b>El formateo se ensaya primero.</b> `PrepareDisk` corre la operación
/// privilegiada en modo ensayo, muestra el plan real (partición, clústeres,
/// etiqueta) y solo entonces ofrece hacerlo de verdad. Nada de esta cadena se
/// pudo probar contra un iPod todavía, así que el ensayo no es una comodidad:
/// es cómo se valida sin arriesgar un disco.</item>
/// <item><b>El grabado del bootloader exige confirmación aparte</b>
/// (<see cref="FlashConfirmedByUser"/>): es irreversible y, en modo Solo
/// firmware, destruye el arranque original de Apple.</item>
/// </list>
///
/// Singleton (D-187): navegar a otra sección y volver retoma la pantalla exacta
/// donde iba, en vez de perder una instalación en curso.
/// </summary>
public sealed partial class InstallerViewModel : ViewModelBase
{
    private readonly IDfuFlashRunner _dfu;
    private readonly IFirmwareTreeInstaller _treeInstaller;
    private readonly IDeviceSafetyValidator _safety;
    private readonly IDeviceSessionService _session;
    private readonly IFirmwareArtifactsProvider _artifactsProvider;
    private readonly IPrivilegedRunner _privileged;
    private readonly IAppleDeviceSupport _appleSupport;
    private readonly InstallerFlowRegistry _flowRegistry;

    /// <summary>
    /// La regla de "¿se puede borrar el disco ahora?", en Core y probada:
    /// objetivo presente + ensayo hecho + consentimiento explícito, y el
    /// consentimiento se consume en cada ejecución.
    /// </summary>
    private readonly DestructiveActionGate _formatGate = new();

    private CancellationTokenSource? _cancellation;

    // MARK: - Estado

    [ObservableProperty] public partial InstallerStep Step { get; set; }
    [ObservableProperty] public partial FirmwareFamily TargetFamily { get; set; }
    [ObservableProperty] public partial string StatusMessage { get; set; }

    /// <summary>
    /// El porqué concreto: qué archivo, qué no cuadró. Cuando algo falla, esto
    /// es lo que distingue un problema de otro — ver <see cref="HasDetail"/>.
    /// </summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasDetail))]
    public partial string DetailMessage { get; set; }

    /// <summary>
    /// Hay un detalle que mostrar. Existe porque la tarjeta de fallo enseñaba
    /// **solo** <see cref="StatusMessage"/> —«Los archivos del firmware no se
    /// pudieron verificar»— y dejaba fuera el `DetailMessage` que decía cuál y
    /// por qué. El dueño se topó con eso probando Metro en la app instalada:
    /// dos fallas muy distintas se veían idénticas en pantalla (ST-137).
    /// </summary>
    public bool HasDetail => !string.IsNullOrWhiteSpace(DetailMessage);
    [ObservableProperty] public partial bool IsBusy { get; set; }
    [ObservableProperty] public partial bool IsNonCancelable { get; set; }

    /// <summary>
    /// Solo firmware (`--single`): destruye el arranque NOR original de Apple.
    /// Es el modo que instala macOS desde ST-050; se deja explícito para que
    /// nunca sea un detalle escondido del flujo.
    /// </summary>
    [ObservableProperty] public partial bool SingleBoot { get; set; }

    /// <summary>
    /// El usuario vio en pantalla qué va a pasar y lo confirmó. Sin esto,
    /// <c>Flash</c> se rehúsa: ningún camino de código graba el bootloader sin
    /// pasar por acá.
    /// </summary>
    [ObservableProperty] public partial bool FlashConfirmedByUser { get; set; }

    /// <summary>
    /// El ensayo del formateo salió bien. **No es consentimiento**: es una
    /// comprobación técnica. Que el ensayo pase solo habilita *mostrar* la
    /// confirmación, nunca formatear.
    /// </summary>
    [ObservableProperty] public partial bool DryRunSucceeded { get; set; }

    /// <summary>
    /// El usuario confirmó **este** formateo, con el disco nombrado delante.
    ///
    /// <para>Se consume en cada intento: después de formatear vuelve a `false`,
    /// así que un segundo formateo exige una confirmación nueva. Sin esto, el
    /// dueño ejecutó dos formateos reales creyendo que solo probaba el
    /// software — el botón de formatear era el único de la pantalla, con el
    /// estilo de acento, justo donde estaba el clic anterior: tenía la forma de
    /// un "Continuar". Un usuario explorando a clics no puede llegar nunca a una
    /// escritura destructiva.</para>
    /// </summary>
    [ObservableProperty] public partial bool FormatConfirmedByUser { get; set; }

    /// <summary>
    /// Todo listo para ofrecer el formateo real: hay dispositivo, el ensayo pasó
    /// y el usuario confirmó explícitamente.
    /// </summary>
    public bool CanFormatNow => DryRunSucceeded && FormatConfirmedByUser && HasDevice;

    partial void OnDryRunSucceededChanged(bool value) => OnPropertyChanged(nameof(CanFormatNow));
    partial void OnFormatConfirmedByUserChanged(bool value) => OnPropertyChanged(nameof(CanFormatNow));

    /// <summary>
    /// El disco concreto que se va a borrar, nombrado. Va en la confirmación y
    /// en el propio botón: el clic destructivo tiene que decir sobre qué actúa,
    /// no "continuar".
    /// </summary>
    public string FormatTargetDescription => _session.Device is { } device
        ? $"{(device.VolumeName.Length > 0 ? device.VolumeName : "iPod")} ({device.VolumePath}) · {device.CapacityDisplay} · USB"
        : AppStrings.NotAvailable;

    public string FormatConfirmText => AppStrings.InstallerFormatConfirm(FormatTargetDescription);
    public string FormatButtonText => AppStrings.InstallerFormatNowOn(FormatTargetDescription);

    /// <summary>Lo que informó la última operación privilegiada, línea por línea.</summary>
    [ObservableProperty] public partial IReadOnlyList<string> PrivilegedLog { get; set; }

    public IReadOnlyList<FirmwareFamily> Families => FirmwareFamily.Installable;

    // MARK: - Visibilidad de cada paso

    public bool IsWelcome => Step == InstallerStep.Welcome;
    public bool IsPermissions => Step == InstallerStep.Permissions;
    public bool IsDetectDevice => Step == InstallerStep.DetectDevice;
    public bool IsPreparingDisk => Step == InstallerStep.PreparingDisk;
    public bool IsCopyingFiles => Step == InstallerStep.CopyingFiles;
    public bool IsEnterDfu => Step == InstallerStep.EnterDfu;
    public bool IsInstalling => Step == InstallerStep.Installing;
    public bool IsAwaitingBootloaderUsb => Step == InstallerStep.AwaitingBootloaderUsb;
    public bool IsDone => Step == InstallerStep.Done;
    public bool IsFailed => Step == InstallerStep.Failed;

    /// <summary>
    /// La tarjeta genérica de "en curso" solo aplica a los pasos que no traen
    /// su propio progreso. Sin esto, durante la preparación del disco se
    /// dibujaban el mensaje y la barra **dos veces**: una en el panel del paso y
    /// otra en la tarjeta genérica.
    /// </summary>
    public bool ShowGenericProgress => IsBusy && !IsPreparingDisk;
    public bool HasPrivilegedLog => PrivilegedLog.Count > 0;

    // MARK: - Resumen del dispositivo (lo que se confirma antes de tocarlo)

    public bool HasDevice => _session.Device is not null;

    public string DeviceName => _session.Device?.DisplayName ?? AppStrings.NotAvailable;
    public string DeviceVolume => _session.Device is { VolumePath.Length: > 0 } d ? d.VolumePath : AppStrings.NotAvailable;
    public string DeviceCapacity => _session.Device?.CapacityDisplay ?? AppStrings.NotAvailable;
    public string DeviceBus => _session.Device?.USBIdentity is null ? "USB" : "USB";
    public string DeviceFirmware => _session.Device?.FirmwareDisplay ?? AppStrings.NotAvailable;

    public string DeviceMessage => _session.Device is { } device
        ? $"{device.DisplayName} · {device.CapacityDisplay} · {device.VolumePath}"
        : AppStrings.InstallerNoDevice;

    /// <summary>
    /// El iPod ya tiene instalada una familia **distinta** de la elegida. No es
    /// un error — el contrato v10/ST-056 dice que la saliente se estaciona
    /// entera y se puede volver a ella — pero es exactamente la clase de cambio
    /// que no puede pasar en silencio: ST-046 nació de ofrecerle a un iPod con
    /// Metro una actualización de Aura que lo habría sobrescrito.
    /// </summary>
    public bool IsFamilyChange =>
        InstalledFamily is { } installed && TargetFamily is { } target && !Equals(installed, target);

    /// <summary>
    /// El texto del aviso. <b>Es una propiedad de presentación y no puede
    /// lanzar</b>: se lee desde un enlace de XAML que se dispara con cada
    /// cambio de dispositivo, y esos cambios ocurren <i>durante</i> la copia y
    /// el formateo —el validador de seguridad refresca la sesión antes de cada
    /// operación destructiva—. Una excepción acá no rompe una etiqueta: mata el
    /// flujo del usuario a mitad de escribir en su iPod, que es exactamente lo
    /// que le pasó al dueño (`errores.log`, NRE en esta línea disparado desde
    /// <c>CopyFilesAsync</c> y desde <c>RunFormatAsync</c>).
    ///
    /// <para>Por eso <b>ningún</b> valor se dereferencia sin guardia, ni
    /// siquiera los que el tipo declara como no nulos: en el momento en que
    /// esto se evalúa, el modelo puede estar a medio actualizar.</para>
    /// </summary>
    public string FamilyChangeWarning =>
        InstalledFamily is { } installed && TargetFamily is { } target
            ? AppStrings.InstallerFamilyChange(installed.DisplayName, target.DisplayName)
            : "";

    /// <summary>Familia que el iPod tiene instalada de verdad, o `null` si ninguna con evidencia.</summary>
    private FirmwareFamily? InstalledFamily
    {
        get
        {
            // Se lee mientras el disco se está formateando o escribiendo, con
            // el volumen yendo y viniendo: cualquier cosa de acá adentro puede
            // fallar sin que eso signifique nada para el usuario. Sin familia
            // conocida no hay aviso, que es la respuesta correcta.
            try
            {
                return _session.Device is { } device && device.SupportsAuraContract
                    ? device.DeclaredFamily
                    : null;
            }
            catch (Exception)
            {
                return null;
            }
        }
    }

    /// <summary>Qué dice el sistema del driver que hace falta para hablarle al iPod en DFU.</summary>
    [ObservableProperty] public partial string DriverStatusText { get; set; }

    // MARK: - Reconocimiento automático de DFU

    /// <summary>
    /// Se detectó un iPod en DFU y se está **preguntando** qué hacer. Nunca se
    /// actúa solo: esto solo enciende una pregunta en pantalla.
    /// </summary>
    [ObservableProperty] public partial bool DfuDetectedAwaitingChoice { get; set; }

    /// <summary>Familias que de verdad se pueden instalar ahora (las que tienen artefactos válidos).</summary>
    [ObservableProperty] public partial IReadOnlyList<FirmwareFamily> AvailableFamilies { get; set; }

    public bool HasAvailableFamilies => AvailableFamilies.Count > 0;

    partial void OnAvailableFamiliesChanged(IReadOnlyList<FirmwareFamily> value)
        => OnPropertyChanged(nameof(HasAvailableFamilies));

    /// <summary>
    /// El usuario ya dijo "ahora no" para esta conexión. No se le vuelve a
    /// preguntar hasta que el iPod salga y entre otra vez en DFU: insistir en
    /// cada sondeo sería peor que no preguntar.
    /// </summary>
    private bool _dfuPromptDismissed;
    private bool _dfuWasPresent;

    public InstallerViewModel(IDfuFlashRunner dfu, IFirmwareTreeInstaller treeInstaller,
                              IDeviceSafetyValidator safety, IDeviceSessionService session,
                              IFirmwareArtifactsProvider artifactsProvider,
                              IPrivilegedRunner privileged, IAppleDeviceSupport appleSupport,
                              InstallerFlowRegistry flowRegistry, IAppPreferences preferences)
    {
        _dfu = dfu;
        _treeInstaller = treeInstaller;
        _safety = safety;
        _session = session;
        _artifactsProvider = artifactsProvider;
        _privileged = privileged;
        _appleSupport = appleSupport;
        _flowRegistry = flowRegistry;

        // R4: la elección de Extras es la que manda acá (ST-047). Antes esta
        // línea fijaba Aura, así que elegir Metro en Extras no cambiaba lo que
        // el asistente iba a instalar — la preferencia existía y no se leía.
        TargetFamily = preferences.FirmwareFamilyToInstall;
        SingleBoot = true;                     // ST-050: la instalación es siempre Solo firmware
        Step = InstallerStep.Welcome;
        StatusMessage = AppStrings.InstallerWelcomeTitle;
        DetailMessage = "";
        DriverStatusText = "";
        PrivilegedLog = [];
        AvailableFamilies = [];

        // El constructor no consulta hardware (regla de ARQUITECTURA): solo se
        // suscribe. El primer sondeo de DFU llega con el evento de la sesión o
        // al abrir la página.
        _session.Changed += (_, _) =>
        {
            NotifyDeviceChanged();
            _ = LookForDfuAsync();
        };
    }

    partial void OnStepChanged(InstallerStep value) => NotifyStepChanged();

    /// <summary>
    /// <b>La familia de destino nunca puede quedar en nulo</b> (ST-130).
    ///
    /// <para>Dos selectores de la pantalla del instalador están enlazados en
    /// dos sentidos a esta propiedad. Cuando a uno se le reemplaza la lista de
    /// opciones —cosa que pasa cada vez que se recalculan las familias
    /// disponibles—, el control vacía su selección y <b>escribe nulo acá</b>.
    /// Nadie lo pidió y nada lo delataba hasta que alguien leía la propiedad:
    /// el aviso de cambio de familia reventaba al pintarse (ST-124) y la copia
    /// de firmware reventaba al resolver los artefactos, las dos con un
    /// <c>NullReferenceException</c> en medio de escribir en el iPod.</para>
    ///
    /// <para>Se restaura el valor <b>anterior</b>, no "Aura": volver a Aura por
    /// omisión convertiría un destino Metro en un destino Aura sin que nadie lo
    /// eligiera, que es exactamente la trampa de ST-046.</para>
    /// </summary>
    partial void OnTargetFamilyChanged(FirmwareFamily oldValue, FirmwareFamily newValue)
    {
        if (newValue is null)
        {
            TargetFamily = oldValue ?? FirmwareFamily.Aura;
            return;
        }

        OnPropertyChanged(nameof(IsFamilyChange));
        OnPropertyChanged(nameof(FamilyChangeWarning));
    }

    partial void OnPrivilegedLogChanged(IReadOnlyList<string> value) => OnPropertyChanged(nameof(HasPrivilegedLog));

    private void NotifyStepChanged()
    {
        foreach (string name in new[]
        {
            nameof(IsWelcome), nameof(IsPermissions), nameof(IsDetectDevice), nameof(IsPreparingDisk),
            nameof(IsCopyingFiles), nameof(IsEnterDfu), nameof(IsInstalling),
            nameof(IsAwaitingBootloaderUsb), nameof(IsDone), nameof(IsFailed),
            nameof(ShowGenericProgress)
        })
        {
            OnPropertyChanged(name);
        }
    }

    partial void OnIsBusyChanged(bool value) => OnPropertyChanged(nameof(ShowGenericProgress));

    private void NotifyDeviceChanged()
    {
        foreach (string name in new[]
        {
            nameof(HasDevice), nameof(DeviceName), nameof(DeviceVolume), nameof(DeviceCapacity),
            nameof(DeviceBus), nameof(DeviceFirmware), nameof(DeviceMessage),
            nameof(IsFamilyChange), nameof(FamilyChangeWarning),
            nameof(FormatTargetDescription), nameof(FormatConfirmText),
            nameof(FormatButtonText), nameof(CanFormatNow)
        })
        {
            OnPropertyChanged(name);
        }

        // Si cambió el dispositivo, la confirmación anterior ya no vale: se dio
        // para OTRO disco. Y el ensayo tampoco: se hizo sobre otra geometría.
        _formatGate.TargetChanged(HasDevice);
        FormatConfirmedByUser = false;
        DryRunSucceeded = false;
    }

    // MARK: - Reconocimiento automático de DFU

    /// <summary>
    /// Mira si hay un iPod en modo DFU y, si lo hay, **pregunta**. Lo llama el
    /// evento de la sesión (llegada USB) y la página al abrirse.
    ///
    /// <para><b>Nunca actúa solo</b> y nunca interrumpe: si ya hay un flujo
    /// corriendo, no enciende nada. Es el guard de D-185 — en macOS, un disparo
    /// automático en medio de una instalación en curso lanzó un segundo
    /// instalador sobre el mismo volumen y abortó la primera.</para>
    /// </summary>
    public async Task LookForDfuAsync()
    {
        // Sondear cuesta lanzar un proceso: primero la consulta barata a WMI.
        // Si no hay ningún dispositivo Apple que no sea el iPod en modo disco,
        // no hay nada que sondear.
        DfuDriverReport report = _appleSupport.Probe();
        if (report.Status == DfuDriverStatus.NoAppleDevice)
        {
            _dfuWasPresent = false;
            _dfuPromptDismissed = false;   // al desconectarse, vuelve a poder preguntarse
            DfuDetectedAwaitingChoice = false;
            return;
        }

        // Hay un aparato de Apple pero Windows no le dio driver: sin eso
        // `mks5lboot` no lo ve. Se dice, en vez de quedarse mudo.
        if (report.Status == DfuDriverStatus.DeviceWithoutDriver)
        {
            RefreshDriverStatus();
            return;
        }

        DfuScanResult scan = await _dfu.ScanAsync();
        if (!scan.IsPresent)
        {
            _dfuWasPresent = false;
            return;
        }

        // Ya estaba en DFU y ya se preguntó: no se insiste en cada sondeo.
        if (_dfuWasPresent && _dfuPromptDismissed) return;
        _dfuWasPresent = true;

        // D-185: jamás tomar la pantalla con un flujo activo.
        if (!_flowRegistry.CanInterrupt || Step != InstallerStep.Welcome) return;
        if (_dfuPromptDismissed) return;

        AvailableFamilies = _artifactsProvider.AvailableFamilies();
        if (AvailableFamilies.Count > 0 && !AvailableFamilies.Contains(TargetFamily))
        {
            TargetFamily = AvailableFamilies[0];
        }
        DfuDetectedAwaitingChoice = true;
        RefreshDriverStatus();
    }

    /// <summary>El usuario aceptó instalar el iPod que ya estaba en DFU.</summary>
    [RelayCommand]
    private void AcceptDetectedDfu()
    {
        DfuDetectedAwaitingChoice = false;
        _flowRegistry.FlowActive = true;
        // El disco ya no hace falta prepararlo: el aparato está en DFU y lo que
        // sigue es grabar. Se va directo al paso de DFU, que ya lo muestra
        // detectado y pide la confirmación explícita antes de grabar.
        Step = InstallerStep.EnterDfu;
        StatusMessage = AppStrings.InstallerEnterDfuTitle;
        RefreshDriverStatus();
    }

    [RelayCommand]
    private void DismissDetectedDfu()
    {
        DfuDetectedAwaitingChoice = false;
        _dfuPromptDismissed = true;
    }

    // MARK: - Navegación del asistente

    [RelayCommand]
    private void Begin()
    {
        PrivilegedLog = [];
        DryRunSucceeded = false;
        DetailMessage = "";
        DfuDetectedAwaitingChoice = false;
        // A partir de acá hay un flujo del usuario: nada automático puede
        // interrumpirlo (D-185).
        _flowRegistry.FlowActive = true;
        Step = InstallerStep.Permissions;
        StatusMessage = AppStrings.InstallerPermissionsTitle;
    }

    /// <summary>
    /// El usuario leyó la explicación de qué permisos hacen falta y por qué.
    /// Recién ahora se pasa a mirar el dispositivo — y el diálogo de UAC no
    /// aparece hasta el formateo.
    /// </summary>
    [RelayCommand]
    private void AcknowledgePermissions()
    {
        Step = InstallerStep.DetectDevice;
        StatusMessage = AppStrings.InstallerDetectTitle;
        RefreshDriverStatus();
    }

    [RelayCommand]
    private void Restart()
    {
        _cancellation?.Cancel();
        PrivilegedLog = [];
        DryRunSucceeded = false;
        FlashConfirmedByUser = false;
        FormatConfirmedByUser = false;
        DetailMessage = "";
        DfuDetectedAwaitingChoice = false;
        _flowRegistry.FlowActive = false;
        Step = InstallerStep.Welcome;
        StatusMessage = AppStrings.InstallerWelcomeTitle;
    }

    [RelayCommand]
    private void RefreshDriverStatus()
    {
        DfuDriverReport report = _appleSupport.Probe();
        DriverStatusText = report.Status switch
        {
            DfuDriverStatus.DeviceReady => AppStrings.DfuDriverReady(report.DeviceName ?? "el dispositivo"),
            DfuDriverStatus.DeviceWithoutDriver => AppStrings.DfuDriverMissing,
            DfuDriverStatus.NoAppleDevice => report.DriverPackageInstalled
                ? AppStrings.DfuDriverInstalledNoDevice
                : AppStrings.DfuDriverPackageMissing,
            _ => AppStrings.DfuDriverUnknown
        };
    }

    // MARK: - Preparar el disco (formateo)

    /// <summary>
    /// Paso 1 de 2: **ensayo**. Pide la elevación, re-verifica el disco en el
    /// proceso elevado y devuelve el plan de formateo sin escribir nada.
    /// </summary>
    [RelayCommand]
    private Task DryRunFormatAsync() => RunFormatAsync(dryRun: true);

    /// <summary>Paso 2 de 2: el formateo de verdad. Solo se ofrece si el ensayo salió bien.</summary>
    [RelayCommand]
    private Task FormatAsync() => RunFormatAsync(dryRun: false);

    private async Task RunFormatAsync(bool dryRun)
    {

        // La regla vive en Core (`DestructiveActionGate`) y está probada ahí: el
        // ensayo comprueba, no autoriza, y el permiso se consume en cada
        // ejecución. Acá solo se refleja el estado de la interfaz y se pide.
        if (!dryRun)
        {
            _formatGate.HasTarget = HasDevice;
            _formatGate.SetConfirmed(FormatConfirmedByUser);
            if (!_formatGate.TryConsume())
            {
                Fail(_formatGate.Evaluate() switch
                {
                    DestructiveRefusal.NoTarget => AppStrings.InstallerNoDevice,
                    DestructiveRefusal.NotChecked => AppStrings.InstallerFormatNeedsDryRun,
                    _ => AppStrings.InstallerFormatNeedsConfirmation
                });
                FormatConfirmedByUser = false;
                return;
            }
        }

        if (_session.Device is not { } device)
        {
            Fail(AppStrings.InstallerNoDevice);
            return;
        }

        // Re-verificación del lado de la app, ANTES de pedir permisos: si acá ya
        // no cuadra, no se molesta al usuario con un diálogo de UAC.
        DeviceSafetyResult safety = _safety.Validate(device);
        if (!safety.IsSafe)
        {
            Fail(safety.Message);
            return;
        }

        if (!PhysicalDrivePath.TryGetNumber(device.DevicePath, out int diskNumber))
        {
            Fail(AppStrings.InstallerUnknownDisk(device.DevicePath));
            return;
        }

        // Cinturón y tirantes de D-185: un solo escritor a la vez, aunque dos
        // flujos llegaran a coexistir. El ensayo no escribe, así que no toma el
        // candado.
        if (!dryRun && !_flowRegistry.BeginWriting())
        {
            Fail(AppStrings.InstallerAlreadyWriting);
            return;
        }

        Step = InstallerStep.PreparingDisk;
        IsBusy = true;
        IsNonCancelable = !dryRun;
        StatusMessage = dryRun ? AppStrings.InstallerDryRunRunning : AppStrings.InstallerFormatRunning;

        try
        {
            var operation = new PrivilegedOperation
            {
                Kind = PrivilegedOperationKind.FormatIPodFat32,
                DiskNumber = diskNumber,
                ExpectedSizeBytes = device.SizeBytes,
                ExpectedModel = device.USBIdentity?.ProductName ?? "",
                VolumeLabel = "IPOD",
                DryRun = dryRun
            };

            PrivilegedOperationResult result = await _privileged.RunAsync(operation);
            PrivilegedLog = result.Log;

            if (result.Success)
            {
                if (dryRun) _formatGate.MarkChecked();
                DryRunSucceeded = dryRun || DryRunSucceeded;
                StatusMessage = result.Message;
                DetailMessage = dryRun ? AppStrings.InstallerDryRunOk : "";
                if (!dryRun)
                {
                    _session.Refresh();
                    Step = InstallerStep.EnterDfu;
                    StatusMessage = AppStrings.InstallerEnterDfuTitle;
                    // Al llegar al paso de DFU hay que saber ya si el
                    // controlador está: si el aparato no aparece nunca, la
                    // primera pregunta es si Windows podría verlo siquiera.
                    RefreshDriverStatus();
                }
            }
            else
            {
                Fail(result.SafetyAbort ? AppStrings.InstallerSafetyAbort(result.Message) : result.Message);
            }
        }
        finally
        {
            if (!dryRun)
            {
                _flowRegistry.EndWriting();
                // Se consume: otro formateo exige una confirmación nueva. Nunca
                // se reusa el permiso de uno anterior.
                FormatConfirmedByUser = false;
            }
            IsBusy = false;
            IsNonCancelable = false;
        }
    }

    // MARK: - Copiar el árbol del firmware

    /// <summary>
    /// Actualizar el firmware que ya está instalado, <b>sin pasar por el
    /// asistente</b> (D-222): el usuario aprieta "Actualizar" donde se lo
    /// avisaron y ve una barra de progreso, no cinco pasos.
    ///
    /// <para><b>Siempre la familia que ya está en el iPod</b> (ST-047), diga lo
    /// que diga la preferencia de Extras: actualizar nunca puede convertirse en
    /// cambiar de familia sin que nadie lo haya pedido.</para>
    ///
    /// <para>Es exactamente el mismo camino de copia del asistente, con sus
    /// mismas defensas —revalidar el disco, tomar el candado de escritura— y
    /// <b>sin formatear ni entrar a DFU</b>: un árbol que ya arrancó una vez
    /// tiene su bootloader puesto, así que actualizar es reemplazar archivos.</para>
    /// </summary>
    public async Task UpdateInPlaceAsync(FirmwareFamily family)
    {
        if (IsBusy) return;

        IsAutomaticUpdate = true;
        TargetFamily = family;

        try
        {
            await CopyFilesCommand.ExecuteAsync(null);
        }
        finally
        {
            IsAutomaticUpdate = false;
        }
    }

    /// <summary>Si lo que corre ahora es una actualización directa y no el asistente.</summary>
    [ObservableProperty] public partial bool IsAutomaticUpdate { get; set; }

    [RelayCommand]
    private async Task CopyFilesAsync()
    {
        if (_session.Device is not { VolumePath.Length: > 0 } device)
        {
            Fail(AppStrings.InstallerNeedsMountedVolume);
            return;
        }

        DeviceSafetyResult safety = _safety.Validate(device);
        if (!safety.IsSafe) { Fail(safety.Message); return; }
        if (!TryGetArtifacts(out FirmwareArtifacts artifacts)) return;

        if (!_flowRegistry.BeginWriting())
        {
            Fail(AppStrings.InstallerAlreadyWriting);
            return;
        }

        Step = InstallerStep.CopyingFiles;
        IsBusy = true;
        StatusMessage = AppStrings.InstallerCopyingTitle;
        _cancellation = new CancellationTokenSource();
        try
        {
            FirmwareTreeInstallResult result = await _treeInstaller.InstallAsync(
                device.VolumePath, artifacts,
                new Progress<string>(line => DetailMessage = line),
                _cancellation.Token);

            if (result.Success)
            {
                Step = InstallerStep.Done;
                StatusMessage = AppStrings.InstallerDoneTitle;
                DetailMessage = AppStrings.InstallerCopiedFiles(result.FilesCopied);
                _flowRegistry.FlowActive = false;   // el flujo terminó de verdad
            }
            else
            {
                Fail(result.ErrorMessage ?? AppStrings.InstallerCopyFailed);
            }
        }
        catch (OperationCanceledException)
        {
            Restart();
        }
        finally
        {
            _flowRegistry.EndWriting();
            _cancellation?.Dispose();
            _cancellation = null;
            IsBusy = false;
        }
    }

    // MARK: - DFU

    [RelayCommand]
    private async Task ScanDfuAsync()
    {
        IsBusy = true;
        StatusMessage = AppStrings.InstallerScanningDfu;
        _cancellation = new CancellationTokenSource();
        try
        {
            DfuScanResult result = await _dfu.ScanAsync(_cancellation.Token);
            DfuDriverReport report = _appleSupport.Probe();
            RefreshDriverStatus();

            if (result.IsPresent)
            {
                StatusMessage = AppStrings.InstallerDfuFound(result.DfuState);
                DetailMessage = "";
            }
            else if (!result.ReportedNoDevice)
            {
                StatusMessage = AppStrings.InstallerDfuUnreadable;
                DetailMessage = result.Output;
            }
            else
            {
                // "No hay dispositivo" tiene dos causas muy distintas y el
                // usuario no puede adivinar cuál le tocó: o no logró entrar en
                // DFU, o el aparato sí está en DFU pero no llega hasta Windows
                // (el caso de una máquina virtual sin el USB redirigido). Con el
                // controlador de Apple instalado y ningún dispositivo suyo a la
                // vista, lo segundo es tan probable como lo primero.
                bool driverReadyButNothingSeen =
                    report.DriverPackageInstalled && report.Status == DfuDriverStatus.NoAppleDevice;

                StatusMessage = driverReadyButNothingSeen
                    ? AppStrings.InstallerDfuNotSeenByWindows
                    : AppStrings.InstallerDfuNotFound;
                DetailMessage = result.Output;
            }
        }
        catch (OperationCanceledException)
        {
            StatusMessage = AppStrings.InstallerCancelled;
        }
        finally
        {
            _cancellation?.Dispose();
            _cancellation = null;
            IsBusy = false;
        }
    }

    [RelayCommand]
    private async Task FlashAsync()
    {
        // Grabar el bootloader es irreversible y, en modo Solo firmware,
        // destruye el arranque NOR original de Apple. Nunca sale de un botón sin
        // que el usuario lo haya confirmado explícitamente en pantalla.
        if (!FlashConfirmedByUser)
        {
            Fail(AppStrings.InstallerFlashNeedsConfirmation);
            return;
        }
        if (!TryGetArtifacts(out FirmwareArtifacts artifacts)) return;

        if (!_flowRegistry.BeginWriting())
        {
            Fail(AppStrings.InstallerAlreadyWriting);
            return;
        }

        Step = InstallerStep.Installing;
        IsBusy = true;
        IsNonCancelable = true;
        StatusMessage = AppStrings.InstallerFlashing;
        _cancellation = new CancellationTokenSource();

        // El servicio de Apple puede quedarse con el USB justo cuando el iPod
        // entra en DFU (equivalente de los agentes AMP en macOS, D-191). Se
        // pausa si está, y se reanuda pase lo que pase.
        bool pausedAppleService = await PauseAppleServiceAsync();
        try
        {
            DfuOperationResult result = await _dfu.InstallBootloaderAsync(
                artifacts, SingleBoot,
                new Progress<string>(line => DetailMessage = line),
                _cancellation.Token);

            if (!result.Success)
            {
                // La salida de mks5lboot es el único testimonio de por qué no
                // grabó; va al detalle, que ahora sí se ve en la tarjeta.
                Fail(AppStrings.InstallerFlashFailed, result.Output);
                return;
            }

            Step = InstallerStep.AwaitingBootloaderUsb;
            StatusMessage = AppStrings.InstallerAwaitingReboot;
            bool exited = await _dfu.WaitForExitAsync(TimeSpan.FromSeconds(45),
                new Progress<string>(line => DetailMessage = line), _cancellation.Token);

            if (exited)
            {
                _session.Refresh();
                StatusMessage = AppStrings.InstallerRebooted;
            }
            else
            {
                Fail(AppStrings.InstallerStuckInDfu);
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            Fail(ex.Message);
        }
        finally
        {
            if (pausedAppleService) await ResumeAppleServiceAsync();
            _flowRegistry.EndWriting();
            // Mismo criterio que el formateo: el permiso se consume, no se reusa.
            FlashConfirmedByUser = false;
            _cancellation?.Dispose();
            _cancellation = null;
            IsBusy = false;
            IsNonCancelable = false;
        }
    }

    private async Task<bool> PauseAppleServiceAsync()
    {
        DfuDriverReport report = _appleSupport.Probe();
        if (!report.ServiceRunning) return false;

        PrivilegedOperationResult result = await _privileged.RunAsync(new PrivilegedOperation
        {
            Kind = PrivilegedOperationKind.PauseAppleMobileDeviceService
        });
        return result.Success;
    }

    private async Task ResumeAppleServiceAsync()
    {
        // Reanudar es best-effort: que falle no puede tapar el resultado real
        // del grabado, pero sí queda en la bitácora de operaciones.
        await _privileged.RunAsync(new PrivilegedOperation
        {
            Kind = PrivilegedOperationKind.ResumeAppleMobileDeviceService
        });
    }

    [RelayCommand]
    private void Cancel()
    {
        if (!IsNonCancelable) _cancellation?.Cancel();
    }

    // MARK: - Apoyo

    /// <summary>
    /// Falla el asistente diciendo qué pasó y —cuando se sabe— por qué.
    ///
    /// <para><b>El detalle se fija siempre, aunque sea vacío.</b> Antes esto no
    /// tocaba <c>DetailMessage</c>, así que un fallo sin detalle propio se
    /// quedaba con el de la operación anterior: la última línea de progreso de
    /// la copia colgando debajo de un error de otra cosa. Mientras el detalle
    /// no se mostraba en la tarjeta de fallo daba igual; ahora se muestra
    /// (ST-137), y un detalle viejo junto a un error nuevo es peor que
    /// ninguno.</para>
    /// </summary>
    private void Fail(string message, string? detail = null)
    {
        Step = InstallerStep.Failed;
        StatusMessage = message;
        DetailMessage = detail ?? "";
    }

    private bool TryGetArtifacts(out FirmwareArtifacts artifacts)
    {
        // El `out` solo se lee cuando esto devuelve `true`; en el camino de
        // fallo no hay artefactos que entregar.
        artifacts = null!;

        // Cinturón además del tirante de `OnTargetFamilyChanged`: sin familia
        // no se resuelve nada. **No se cae a Aura**: instalar una familia que
        // el usuario no eligió es peor que no instalar (ST-046).
        if (TargetFamily is null)
        {
            Fail(AppStrings.InstallerArtifactsInvalid,
                 "No se pudo determinar qué firmware instalar. Vuelve a elegirlo y reintenta.");
            return false;
        }

        // El tag sale de `firmware-version.txt`, nunca de una constante: la
        // pantalla de Licencias cita esa versión y no puede citar una inventada.
        artifacts = _artifactsProvider.For(TargetFamily);
        ArtifactVerificationResult verification = FirmwareArtifactVerifier.Verify(artifacts);
        if (verification.IsValid) return true;

        // Un problema por renglón: pegados con espacios, tres archivos faltantes
        // se leían como una sola frase larga.
        Fail(AppStrings.InstallerArtifactsInvalid, string.Join("\n", verification.Errors));
        return false;
    }
}
