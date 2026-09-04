<#
.SYNOPSIS
    Arma los instaladores de Aura Studio para Windows (ARM64 y/o x64).

.DESCRIPTION
    Publica la app autocontenida, comprueba que el árbol publicado sirva de
    verdad, y lo empaqueta con Inno Setup en `dist\`.

    Las comprobaciones no son adorno. El publish de una app WinUI 3 sin
    empaquetar puede salir completo —553 archivos, 290 MB— y aun así morir al
    arrancar porque le falta un archivo de 2 MB: `AuraStudio.App.pri`, el
    índice que resuelve `ms-appx:///MainWindow.xaml`. Pasó exactamente eso. El
    .csproj ya lo previene, y acá se vuelve a mirar antes de empaquetar: es más
    barato fallar aquí que en la máquina de quien lo instale.

    Con dos arquitecturas hay una segunda forma de equivocarse, silenciosa y
    peor: empaquetar el árbol de una dentro del Setup de la otra. Por eso se
    lee la cabecera PE del ejecutable publicado y se compara con la
    arquitectura pedida.

.PARAMETER Architecture
    `arm64` (por omisión), `x64`, o `both`.

.PARAMETER SkipPublish
    Empaqueta el publish que ya está en el árbol, sin volver a compilarlo.
    Útil para iterar sobre el .iss; no lo use para producir un instalador
    que vaya a distribuirse.

.EXAMPLE
    .\scripts\Make-Installer.ps1
    .\scripts\Make-Installer.ps1 -Architecture both
#>
[CmdletBinding()]
param(
    [ValidateSet('arm64', 'x64', 'both')]
    [string] $Architecture = 'arm64',

    [switch] $SkipPublish
)

$ErrorActionPreference = 'Stop'

$repo    = Split-Path -Parent $PSScriptRoot
$project = Join-Path $repo 'AuraStudio.App\AuraStudio.App.csproj'
$iss     = Join-Path $repo 'installer\AuraStudio.iss'
$dist    = Join-Path $repo 'dist'

# Lo que cambia entre una arquitectura y otra, en un solo lugar.
$perfiles = @{
    'arm64' = @{ Rid = 'win-arm64'; Platform = 'ARM64'; PeMachine = 0xAA64 }
    'x64'   = @{ Rid = 'win-x64';   Platform = 'x64';   PeMachine = 0x8664 }
}

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

# --- Apoyo ------------------------------------------------------------------

<#
.SYNOPSIS
    La arquitectura real de un .exe, leída de su cabecera PE.
.DESCRIPTION
    En el encabezado DOS, el offset 0x3C apunta a la firma "PE\0\0"; los dos
    bytes que siguen son el campo Machine. Es la única forma de saber qué se
    está a punto de empaquetar sin creerle a la ruta.
#>
function Get-PeMachine([string] $Path) {
    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $br = New-Object System.IO.BinaryReader($fs)
        $fs.Position = 0x3C
        $fs.Position = $br.ReadInt32()
        if ($br.ReadUInt32() -ne 0x00004550) { throw "$Path no es un PE válido." }
        return $br.ReadUInt16()
    } finally { $fs.Dispose() }
}

function Build-Installer([string] $arch) {
    $perfil     = $perfiles[$arch]
    $publishDir = Join-Path $repo `
        "AuraStudio.App\bin\$($perfil.Platform)\Release\net10.0-windows10.0.26100.0\$($perfil.Rid)\publish"

    # --- Publicación --------------------------------------------------------

    if ($SkipPublish) {
        Write-Host "[$arch] Se omite el publish (-SkipPublish): se empaqueta lo que ya está en el árbol."
    } else {
        Write-Host "[$arch] Publicando autocontenido..."
        if (Test-Path $publishDir) { Remove-Item $publishDir -Recurse -Force }
        & dotnet publish $project -c Release -r $perfil.Rid --self-contained true `
            -p:Platform=$($perfil.Platform) -p:WindowsAppSDKSelfContained=true | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "[$arch] El publish falló (código $LASTEXITCODE)." }
    }

    # --- Qué tiene que traer el publish para no ser un instalador roto ------

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
        throw "[$arch] El publish está incompleto; falta:`n  " + ($faltan -join "`n  ")
    }

    # Los avisos de licencia de las tres familias viajan con sus binarios: es
    # como se cumple el §3 de la GPL v2 (ver installer\AVISO-LICENCIAS.txt).
    foreach ($familia in @('', 'metro\', 'moonlit\')) {
        foreach ($aviso in @('MODIFICATIONS.md', 'THIRD-PARTY-NOTICES.txt')) {
            $ruta = Join-Path $publishDir "artifacts\$familia$aviso"
            if (-not (Test-Path $ruta)) { throw "[$arch] Falta el aviso de licencia: artifacts\$familia$aviso" }
        }
    }

    # Y que sea de la arquitectura que se pidió, no de la otra.
    $machine = Get-PeMachine (Join-Path $publishDir 'AuraStudio.App.exe')
    if ($machine -ne $perfil.PeMachine) {
        throw ("[$arch] El ejecutable publicado no es {0}: su cabecera PE dice 0x{1:X4} " +
               "y se esperaba 0x{2:X4}. Se estaría empaquetando el árbol equivocado." -f
               $arch, $machine, $perfil.PeMachine)
    }

    # `mks5lboot.exe` es x86-32 y así se queda: lo ejecutan igual x64 (WOW64) y
    # ARM64 (emulación). Si algún día dejara de serlo, que se note acá.
    $herramienta = Get-PeMachine (Join-Path $publishDir 'artifacts\mks5lboot.exe')
    if ($herramienta -ne 0x014C) {
        Write-Warning ("mks5lboot.exe ya no es x86-32 (0x{0:X4}): revise que siga corriendo " +
                       "en las dos arquitecturas." -f $herramienta)
    }

    $archivos = (Get-ChildItem $publishDir -Recurse -File)
    $mb = [math]::Round(($archivos | Measure-Object Length -Sum).Sum / 1MB)
    Write-Host "[$arch] Publish verificado: $($archivos.Count) archivos, $mb MB."

    # --- Empaquetado --------------------------------------------------------

    if (-not (Test-Path $dist)) { New-Item -ItemType Directory $dist | Out-Null }

    Write-Host "[$arch] Compilando el instalador..."
    & $iscc "/DArch=$arch" $iss | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "[$arch] Inno Setup falló (código $LASTEXITCODE)." }

    $setup = Join-Path $dist "AuraStudioSetup-0.1.0-$arch.exe"
    if (-not (Test-Path $setup)) {
        throw "[$arch] Inno Setup terminó bien pero no dejó $setup."
    }
    Get-Item $setup
}

<#
.SYNOPSIS
    Avisa si los dos árboles publicados difieren en archivos que el .iss no
    limpia al cambiar de arquitectura.
.DESCRIPTION
    Las dos arquitecturas comparten AppId y carpeta, así que instalar una sobre
    la otra sobrescribe casi todo — casi. Lo que solo existe en una queda
    tirado, y el desinstalador de la otra no lo conoce: basura que sobrevive a
    la desinstalación.

    `[InstallDelete]` del .iss se encarga, pero su lista se pudre en cuanto el
    Windows App SDK agrega un archivo nuevo con nombre por arquitectura. Esto lo
    detecta en el momento de armar, que es cuando se puede arreglar. Avisa, no
    detiene: un archivo huérfano no justifica no entregar el instalador.
#>
function Test-DiferenciasEntreArquitecturas {
    $arboles = @{}
    foreach ($a in @('arm64', 'x64')) {
        $p = $perfiles[$a]
        $dir = Join-Path $repo `
            "AuraStudio.App\bin\$($p.Platform)\Release\net10.0-windows10.0.26100.0\$($p.Rid)\publish"
        if (-not (Test-Path $dir)) { return }
        $arboles[$a] = Get-ChildItem $dir -Recurse -File |
                       ForEach-Object { $_.FullName.Substring($dir.Length + 1) }
    }

    # Los mismos patrones que [InstallDelete] en installer\AuraStudio.iss.
    # Si cambia uno, cambian los dos.
    $cubiertos = @('*.arm64.dll', '*.amd64.dll', '*_ec.dll', 'mscordaccore_*.dll', 'workloads.*.json')

    $solos = (Compare-Object $arboles['arm64'] $arboles['x64']).InputObject
    $sueltos = $solos | Where-Object {
        $nombre = Split-Path $_ -Leaf
        -not ($cubiertos | Where-Object { $nombre -like $_ })
    }

    if ($sueltos) {
        Write-Warning (
            "Estos archivos existen en una arquitectura y no en la otra, y [InstallDelete] no los cubre:`n  " +
            ($sueltos -join "`n  ") +
            "`nAl cambiar de arquitectura quedarían tirados y el desinstalador no los borraría." +
            "`nAgregue un patrón en installer\AuraStudio.iss (sección [InstallDelete]) y otro igual" +
            "`nen la lista `$cubiertos de este script.")
    } else {
        Write-Host 'Las dos arquitecturas no dejan huérfanos sin cubrir.'
    }
}

# --- Marcha -----------------------------------------------------------------

$objetivos = if ($Architecture -eq 'both') { @('arm64', 'x64') } else { @($Architecture) }
$hechos = foreach ($a in $objetivos) { Build-Installer $a }

if ($Architecture -eq 'both') { Test-DiferenciasEntreArquitecturas }

Write-Host ''
foreach ($s in $hechos) {
    Write-Host ("Listo: {0}" -f $s.FullName)
    Write-Host ("       {0} MB" -f [math]::Round($s.Length / 1MB, 1))
}
Write-Host ''
Write-Host 'Sin firma de código: SmartScreen va a advertir la primera vez.'
if ($Architecture -eq 'both') {
    Write-Host 'Las dos comparten AppId: instalar una reemplaza a la otra (ver installer\AuraStudio.iss).'
}
