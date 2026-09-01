using System.Management;
using System.ServiceProcess;
using AuraStudio.Core;
using AuraStudio.App.Services;

namespace AuraStudio.App.Platform;

/// <summary>
/// Consulta, sin privilegios y sin escribir nada, si Windows puede hablarle al
/// iPod en modo DFU. Ver <see cref="IAppleDeviceSupport"/> para por qué el
/// driver que hace falta es el de Apple y no WinUSB.
/// </summary>
public sealed class AppleDeviceSupport : IAppleDeviceSupport
{
    /// <summary>Servicio de dispositivos móviles de Apple (lo instalan iTunes o "Dispositivos Apple").</summary>
    public const string ServiceName = "Apple Mobile Device Service";

    /// <summary>Driver USB de Apple. Su presencia acredita el paquete instalado.</summary>
    private static readonly string[] DriverFileNames = ["usbaapl64.sys", "usbaapl.sys"];

    /// <summary>`ConfigManagerErrorCode` 28: el dispositivo está pero sin driver instalado.</summary>
    private const int CmDriversNotInstalled = 28;

    public DfuDriverReport Probe()
    {
        bool driverPackage = DriverPackageInstalled();
        bool serviceRunning = ServiceIsRunning();

        try
        {
            string vendor = USBDeviceIdentity.AppleVendorID.ToString("X4");
            using var searcher = new ManagementObjectSearcher(
                "SELECT Name, DeviceID, ConfigManagerErrorCode FROM Win32_PnPEntity " +
                $"WHERE DeviceID LIKE 'USB\\\\VID_{vendor}%'");

            using ManagementObjectCollection devices = searcher.Get();

            string? bestName = null;
            int? bestPid = null;
            var bestStatus = DfuDriverStatus.NoAppleDevice;

            foreach (ManagementBaseObject device in devices)
            {
                using (device)
                {
                    string deviceId = device["DeviceID"] as string ?? "";
                    string name = device["Name"] as string ?? "Dispositivo Apple";
                    int? errorCode = device["ConfigManagerErrorCode"] is uint code ? (int)code : null;

                    int? pid = PnpDeviceId.TryParseUsbDeviceId(deviceId, out _, out int parsedPid, out _)
                        ? parsedPid
                        : null;

                    // Un iPod en modo disco (PID 0x1261) no es lo que se busca acá:
                    // ese ya lo atiende el almacenamiento masivo y no está en DFU.
                    if (pid == USBDeviceIdentity.IPodClassicProductID) continue;

                    var status = errorCode == CmDriversNotInstalled
                        ? DfuDriverStatus.DeviceWithoutDriver
                        : DfuDriverStatus.DeviceReady;

                    // "Listo" gana sobre "sin driver": si hay dos nodos del mismo
                    // aparato, el que responde es el que importa.
                    if (bestStatus != DfuDriverStatus.DeviceReady)
                    {
                        bestStatus = status;
                        bestName = name;
                        bestPid = pid;
                    }
                }
            }

            return new DfuDriverReport(bestStatus, bestName, bestPid, driverPackage, serviceRunning);
        }
        catch (ManagementException)
        {
            // No se pudo consultar: no se afirma nada, ni bueno ni malo.
            return new DfuDriverReport(DfuDriverStatus.Unknown, null, null, driverPackage, serviceRunning);
        }
        catch (UnauthorizedAccessException)
        {
            return new DfuDriverReport(DfuDriverStatus.Unknown, null, null, driverPackage, serviceRunning);
        }
    }

    private static bool DriverPackageInstalled()
    {
        try
        {
            string drivers = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "drivers");
            return DriverFileNames.Any(name => File.Exists(Path.Combine(drivers, name)));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    private static bool ServiceIsRunning()
    {
        try
        {
            using var service = new ServiceController(ServiceName);
            return service.Status == ServiceControllerStatus.Running;
        }
        catch (Exception ex) when (ex is InvalidOperationException or ArgumentException)
        {
            // El servicio no existe (sin iTunes instalado): no está corriendo.
            return false;
        }
    }
}
