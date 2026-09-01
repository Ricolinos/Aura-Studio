namespace AuraStudio.App.Services;

/// <summary>En qué estado está el soporte de Windows para hablarle al iPod en DFU.</summary>
public enum DfuDriverStatus
{
    /// <summary>No hay ningún dispositivo Apple en el USB — probablemente el iPod no está en DFU.</summary>
    NoAppleDevice,

    /// <summary>
    /// Hay un dispositivo Apple pero Windows no le asignó driver
    /// (`ConfigManagerErrorCode` 28). Sin driver, `mks5lboot.exe` no lo ve.
    /// </summary>
    DeviceWithoutDriver,

    /// <summary>Hay un dispositivo Apple con driver funcionando.</summary>
    DeviceReady,

    /// <summary>No se pudo consultar (WMI falló). No se afirma nada.</summary>
    Unknown
}

/// <param name="Status">Qué se encontró.</param>
/// <param name="DeviceName">Nombre del dispositivo Apple hallado, para poder nombrarlo en pantalla.</param>
/// <param name="ProductId">PID USB del dispositivo hallado.</param>
/// <param name="DriverPackageInstalled">
/// Está instalado el paquete de drivers de dispositivos móviles de Apple (el que
/// traen iTunes o la app "Dispositivos Apple").
/// </param>
/// <param name="ServiceRunning">Está corriendo el servicio de Apple que puede quedarse con el USB.</param>
public sealed record DfuDriverReport(
    DfuDriverStatus Status,
    string? DeviceName,
    int? ProductId,
    bool DriverPackageInstalled,
    bool ServiceRunning);

/// <summary>
/// Estado del driver que `mks5lboot.exe` necesita para hablar con el iPod en DFU.
///
/// <para><b>Por qué es el driver de Apple y no WinUSB.</b> El plan de la Fase 2
/// planteaba "Apple Mobile Device Support si hay iTunes; si no, guía WinUSB".
/// El `mks5lboot.exe` que trae este port **no usa libusb ni WinUSB**: importa
/// `setupapi.dll` y abre el dispositivo por la interfaz `GUID_AAPLDFU` (visible
/// entre sus símbolos), o sea la que publica el driver de Apple. Con este
/// binario, la vía WinUSB no aplica: o está el driver de Apple, o no hay
/// flasheo. La guía en pantalla apunta ahí.</para>
///
/// Todo lo de esta interfaz es de **solo lectura** y sin privilegios. Pausar o
/// reanudar el servicio de Apple sí requiere elevación y va por la lista cerrada
/// de operaciones privilegiadas.
/// </summary>
public interface IAppleDeviceSupport
{
    DfuDriverReport Probe();
}
