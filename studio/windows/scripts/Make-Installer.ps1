<#
.SYNOPSIS
    Arma el instalador de Aura Studio para Windows (ARM64).

.DESCRIPTION
    Publica la app autocontenida, comprueba que el árbol publicado sirva de
    verdad, y lo empaqueta con Inno Setup en `dist\`.

    Las comprobaciones no son adorno. El publish de una app WinUI 3 sin
    empaquetar puede salir completo —437 archivos, 289 MB— y aun así morir al
    arrancar porque le falta un archivo de 2 MB: `AuraStudio.App.pri`, el
    índice que resuelve `ms-appx:///MainWindow.xaml`. Pasó exactamente eso en
    esta ronda. El .csproj ya lo previene, y acá se vuelve a mirar antes de
    empaquetar: es más barato fallar aquí que en la máquina de quien lo instale.

.PARAMETER SkipPublish
    Empaqueta el publish que ya está en el árbol, sin volver a compilarlo.
    Útil para iterar sobre el .iss; no lo use para producir un instalador
    que vaya a distribuirse.

.EXAMPLE
    .\scripts\Make-Installer.ps1
#>
[CmdletBinding()]
param(
    [switch] $SkipPublish
)

$ErrorActionPreference = 'Stop'

$repo       = Split-Path -Parent $PSScriptRoot
$project    = Join-Path $repo 'AuraStudio.App\AuraStudio.App.csproj'
$publishDir = Join-Path $repo 'AuraStudio.App\bin\ARM64\Release\net10.0-windows10.0.26100.0\win-arm64\publish'
$iss        = Join-Path $repo 'installer\AuraStudio.iss'
$dist       = Join-Path $repo 'dist'

# --- Inno Setup -------------------------------------------------------------

$candidatos = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe'
)
$iscc = $candidatos | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) {
    throw @'
No se encontró Inno Setup 6 (ISCC.exe). Instálelo sin permisos de
administrador con:

    winget install --id JRSoftware.InnoSetup --scope user

y vuelva a correr este script.
'@
}
Write-Host "Inno Setup: $iscc"

# --- Publicación ------------------------------------------------------------

if ($SkipPublish) {
    Write-Host 'Se omite el publish (-SkipPublish): se empaqueta lo que ya está en el árbol.'
} else {
    Write-Host 'Publicando ARM64 autocontenido...'
    if (Test-Path $publishDir) { Remove-Item $publishDir -Recurse -Force }
    & dotnet publish $project -c Release -r win-arm64 --self-contained true `
        -p:Platform=ARM64 -p:WindowsAppSDKSelfContained=true
    if ($LASTEXITCODE -ne 0) { throw "El publish falló (código $LASTEXITCODE)." }
}

# --- Qué tiene que traer el publish para no ser un instalador roto ----------

$imprescindibles = @(
    'AuraStudio.App.exe',              # el programa
    'AuraStudio.App.pri',              # sin esto no resuelve su propio XAML
    'AuraStudio.Core.dll',
    'Microsoft.WindowsAppRuntime.Bootstrap.dll',
    'artifacts\mks5lboot.exe',         # herramienta de flasheo (Windows)
    'artifacts\rockbox.ipod',          # familia Aura
    'artifacts\metro\rockbox.ipod',    # familia Metro-Aura
    'artifacts\moonlit\rockbox.ipod'   # familia moonlit.aura
)
$faltan = $imprescindibles | Where-Object { -not (Test-Path (Join-Path $publishDir $_)) }
if ($faltan) {
    throw "El publish está incompleto; falta:`n  " + ($faltan -join "`n  ")
}

# Los avisos de licencia de las tres familias viajan con sus binarios: es como
# se cumple el §3 de la GPL v2 (ver installer\AVISO-LICENCIAS.txt).
foreach ($familia in @('', 'metro\', 'moonlit\')) {
    foreach ($aviso in @('MODIFICATIONS.md', 'THIRD-PARTY-NOTICES.txt')) {
        $ruta = Join-Path $publishDir "artifacts\$familia$aviso"
        if (-not (Test-Path $ruta)) { throw "Falta el aviso de licencia: artifacts\$familia$aviso" }
    }
}

$archivos = (Get-ChildItem $publishDir -Recurse -File)
$mb = [math]::Round(($archivos | Measure-Object Length -Sum).Sum / 1MB)
Write-Host "Publish verificado: $($archivos.Count) archivos, $mb MB."

# --- Empaquetado ------------------------------------------------------------

if (-not (Test-Path $dist)) { New-Item -ItemType Directory $dist | Out-Null }

Write-Host 'Compilando el instalador...'
& $iscc $iss
if ($LASTEXITCODE -ne 0) { throw "Inno Setup falló (código $LASTEXITCODE)." }

$setup = Get-ChildItem $dist -Filter 'AuraStudioSetup-*-arm64.exe' |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $setup) { throw 'Inno Setup terminó bien pero no dejó ningún instalador en dist\.' }

Write-Host ''
Write-Host "Listo: $($setup.FullName)"
Write-Host ("      {0} MB" -f [math]::Round($setup.Length / 1MB, 1))
Write-Host ''
Write-Host 'Sin firma de código: SmartScreen va a advertir la primera vez.'
