# VM Windows Setup para Aura Studio

Guía rápida para compilar y debuggear AuraStudio.App (WinUI 3) en VM Windows desde macOS.

## Opciones de VM (orden de preferencia para desarrollo WinUI 3)

| VM | Pros | Contras | Costo |
|----|------|---------|-------|
| **Parallels Desktop 20** | Mejor integración (Coherence), debugging VS nativo, performance gráfico, "Game Hub" mode | Pago (suscripción) | ~$100/año |
| **VMware Fusion Pro** | Gratis uso personal (desde 2024), buen soporte, snapshots | Sin Coherence, debugging un poco menos fluido | Gratis* |
| **UTM (QEMU)** | Open source, Apple Silicon nativo | Sin drivers GPU virgl para WinUI 3 Fluent 2, debugging difícil | Gratis |

> **Recomendación**: Parallels Desktop para desarrollo WinUI 3 serio. VMware Fusion Pro si no quieres pagar.

---

## Setup rápido (Parallels)

### 1. En macOS: Ejecutar script de apertura
```bash
cd /Volumes/Ricolinos/Codigo/GitHub/Aura/Aura-Studio/studio/windows
pwsh scripts/OpenInVM.ps1 -VMType Parallels -OpenVS
```
Esto detecta la VM, mapea la ruta compartida (`\\Mac\Volumes\...`), compila y abre VS 2022.

### 2. En la VM Windows (PowerShell Admin): Setup completo
```powershell
# Copiar script a la VM y ejecutar:
powershell -ExecutionPolicy Bypass -File Setup-WindowsDev.ps1
```
Instala: .NET 10 SDK, Windows App SDK 1.6, VS 2022 workloads, mingw-w64, Git, drivers iPod.

### 3. En Visual Studio 2022
1. **Set Startup Project** → `AuraStudio.App` (clic derecho → Set as Startup Project)
2. **Target** → `x64` o `ARM64` (no `Any CPU` para WinUI 3)
3. **F5** → Debug

---

## Compilar mks5lboot.exe (cross-compile)

En la VM Windows (terminal Developer PowerShell for VS 2022):
```powershell
cd C:\Aura-Firmware\tools\mks5lboot  # Ajustar ruta
make CROSS_COMPILE=x86_64-w64-mingw32- clean all
cp mks5lboot.exe C:\Aura-Studio\studio\windows\artifacts\
```

> El `artifacts/mks5lboot.exe` ya está versionado en el repo (compilado en CI).

---

## Estructura de carpetas compartidas

### Parallels
| macOS | Windows (VM) |
|-------|--------------|
| `/Volumes/Ricolinos/...` | `\\Mac\Volumes\Ricolinos\...` |
| `~/...` | `\\Mac\Home\...` |

### VMware Fusion
Configurar en **VM Settings > Sharing > Add** → `/Volumes/Ricolinos` → aparece en `\\vmware-host\Shared Folders\Ricolinos\...`

---

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `winui3` template not found | `dotnet new install Microsoft.WindowsAppSDK.WinUI.CSharp.Templates` |
| `MSB4018: The "GenerateMsixManifest` task failed` | Instalar Windows App SDK 1.6 runtime (`winget install Microsoft.WindowsAppSDK.1.6`) |
| `Mica/Acrylic not rendering` | VM necesita GPU virtualization activada (Parallels: **Hardware > Graphics > Auto**; VMware: **3D Graphics**) |
| `USB iPod no detectado` | 1. Instalar Apple Mobile Device Support 2. En VM settings: **USB > Connect Apple iPod automatically** 3. `WM_DEVICECHANGE` hook en `MainWindow.xaml.cs` |
| `Cannot debug: symbols not loaded` | Build config = **Debug**, Platform = **x64**, `Debug > Options > Enable .NET Framework source stepping` |
| `The project doesn't know how to run the profile` | `Properties/launchSettings.json` debe tener `commandName: "Project"` |

---

## Flujo de trabajo diario

```bash
# En macOS Terminal:
cd /Volumes/Ricolinos/Codigo/GitHub/Aura/Aura-Studio/studio/windows

# 1. Abrir VM + compilar + abrir VS
pwsh scripts/OpenInVM.ps1 -VMType Parallels -OpenVS

# 2. En VS: F5 para debug
# 3. Cambios en Core → rebuild automático (ProjectReference)
# 4. Cambios en App → Hot Reload (F5 continue)
```

---

## Notas importantes

- **Target Framework**: `net10.0-windows10.0.19041.0` — requiere Windows 10 2004+ (build 19041)
- **Platform**: **x64** o **ARM64** obligatorio (WinUI 3 no soporta Any CPU)
- **Windows App SDK**: 1.6.250605001 (último stable al 2026-08)
- **mks5lboot.exe**: Ya compilado en `artifacts/` — no hace falta recompilar salvo cambios en firmware
- **Drivers iPod**: Apple Mobile Device Support instala el driver USB `usbaapl64.sys` necesario para `WM_DEVICECHANGE` detectar el iPod Classic (VID 0x05AC PID 0x1261)