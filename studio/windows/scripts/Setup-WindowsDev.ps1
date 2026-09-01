<#
.SYNOPSIS
    Setup completo del entorno de desarrollo Windows para Aura Studio.
    Ejecutar DENTRO de la VM Windows (PowerShell Admin).

.NOTES
    Instala: .NET 10 SDK, Windows App SDK 1.6+, Visual Studio 2022 workload,
    mingw-w64 (para mks5lboot), Git, drivers USB iPod.
#>

param(
    [switch]$SkipVS,
    [switch]$SkipMingw
)

$ErrorActionPreference = 'Stop'

Write-Host "🔧 Configurando entorno de desarrollo Windows para Aura Studio..." -ForegroundColor Cyan

# 1. .NET 10 SDK
Write-Host "`n📦 Verificando .NET 10 SDK..." -ForegroundColor Yellow
$dotnet10 = & dotnet --list-sdks | Select-String '^10\.'
if (-not $dotnet10) {
    Write-Host "Instalando .NET 10 SDK..." -ForegroundColor Green
    winget install Microsoft.DotNet.SDK.10 --accept-source-agreements --accept-package-agreements
}
else {
    Write-Host "✅ .NET 10 SDK ya instalado: $($dotnet10.ToString().Trim())" -ForegroundColor Green
}

# 2. Windows App SDK 1.6+ (runtime)
Write-Host "`n📦 Verificando Windows App SDK runtime..." -ForegroundColor Yellow
$wasdk = Get-AppxPackage -Name 'Microsoft.WindowsAppRuntime.*' | Where-Object { $_.Version -like '1.6.*' }
if (-not $wasdk) {
    Write-Host "Instalando Windows App SDK 1.6 runtime..." -ForegroundColor Green
    winget install Microsoft.WindowsAppSDK.1.6 --accept-source-agreements --accept-package-agreements
}
else {
    Write-Host "✅ Windows App SDK 1.6+ ya instalado" -ForegroundColor Green
}

# 3. Visual Studio 2022 Workload (si no se salta)
if (-not $SkipVS) {
    Write-Host "`n📦 Instalando workload de Visual Studio 2022..." -ForegroundColor Yellow
    $vsInstaller = "${env:ProgramFiles}\Microsoft Visual Studio\Installer\vs_installer.exe"
    if (Test-Path $vsInstaller) {
        & $vsInstaller modify --installPath "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community" `
            --add Microsoft.VisualStudio.Workload.Universal `
            --add Microsoft.VisualStudio.Workload.NetCoreTools `
            --add Microsoft.VisualStudio.Component.Windows10SDK.19041 `
            --add Microsoft.VisualStudio.Component.Windows11SDK `
            --quiet --wait --norestart
        Write-Host "✅ Workloads instaladas" -ForegroundColor Green
    }
    else {
        Write-Warning "Visual Studio Installer no encontrado. Instala VS 2022 Community manualmente."
    }
}

# 4. mingw-w64 para cross-compilar mks5lboot
if (-not $SkipMingw) {
    Write-Host "`n📦 Instalando mingw-w64 (para mks5lboot)..." -ForegroundColor Yellow
    winget install mingw64.mingw-w64 --accept-source-agreements --accept-package-agreements
    Write-Host "✅ mingw-w64 instalado" -ForegroundColor Green
}

# 5. Git
Write-Host "`n📦 Verificando Git..." -ForegroundColor Yellow
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    winget install Git.Git --accept-source-agreements --accept-package-agreements
    Write-Host "✅ Git instalado" -ForegroundColor Green
}
else {
    Write-Host "✅ Git ya instalado" -ForegroundColor Green
}

# 6. Drivers USB iPod (Apple Mobile Device Support)
Write-Host "`n📦 Verificando Apple Mobile Device Support (drivers iPod)..." -ForegroundColor Yellow
$appleMobile = Get-AppxPackage -Name 'AppleInc.AppleMobileDeviceSupport' -ErrorAction SilentlyContinue
if (-not $appleMobile) {
    Write-Host "Instalando Apple Mobile Device Support..." -ForegroundColor Green
    winget install Apple.AppleMobileDeviceSupport --accept-source-agreements --accept-package-agreements
}
else {
    Write-Host "✅ Apple Mobile Device Support ya instalado" -ForegroundColor Green
}

# 7. Verificar proyecto
Write-Host "`n🔨 Verificando compilación del proyecto..." -ForegroundColor Yellow
$projectRoot = "C:\Aura-Studio\studio\windows"  # Ajustar a tu ruta en la VM
if (Test-Path "$projectRoot\AuraStudio.Windows.slnx") {
    Set-Location $projectRoot
    dotnet restore
    dotnet build -c Debug -v minimal
    Write-Host "✅ Proyecto compila correctamente" -ForegroundColor Green
}
else {
    Write-Warning "No se encontró la solución en $projectRoot. Ajusta la ruta en el script."
}

Write-Host "`n🎉 Setup completo. Para desarrollar:" -ForegroundColor Cyan
Write-Host "  1. Abre Visual Studio 2022" -ForegroundColor White
Write-Host "  2. Open -> Project/Solution -> AuraStudio.Windows.slnx" -ForegroundColor White
Write-Host "  3. Set 'AuraStudio.App' como Startup Project" -ForegroundColor White
Write-Host "  4. F5 para debug" -ForegroundColor White
Write-Host "`n💡 Para cross-compilar mks5lboot:" -ForegroundColor Cyan
Write-Host "  cd Aura-Firmware/tools/mks5lboot" -ForegroundColor White
Write-Host "  make CROSS_COMPILE=x86_64-w64-mingw32- clean all" -ForegroundColor White
Write-Host "  cp mks5lboot.exe ../../../studio/windows/artifacts/" -ForegroundColor White