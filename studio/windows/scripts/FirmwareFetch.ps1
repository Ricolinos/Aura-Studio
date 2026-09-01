# FirmwareFetch.ps1
#
# Puente del script `scripts/fetch-firmware.sh` de Aura Studio (macOS) a
# PowerShell para la versión Windows. Puebla `studio/windows/artifacts/`
# con los artefactos que el firmware Aura publica -- nunca lee el árbol de
# fuentes de un checkout de Aura-Firmware. Ver CONTRATO-firmware-studio.md
# §A. NOTA: este script se escribe en la Mac y NO se ejecuta ahí (es
# PowerShell de Windows); se revisa por lectura y se valida en la sesión VM.
#
# Uso normal (con Release publicado):
#   .\FirmwareFetch.ps1
#     Descarga el tag fijado en FIRMWARE_VERSION con `gh release download`.
#
# Uso de desarrollo (sin Release público todavía):
#   .\FirmwareFetch.ps1 -FromDir C:\ruta\a\Aura-Firmware\firmware\dist
#     Copia desde un firmware/dist/ local. Excepción de desarrollo, nunca
#     la ruta por defecto del proyecto.
#
# En ambos casos verifica checksums.txt antes de dejar los archivos
# utilizables, y falla con mensaje claro si algo no coincide o falta.

param(
    [string]$Family,
    [string]$FromDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# La raíz del repo Windows, para resolver rutas relativas al script.
$rootDir = Split-Path -Parent $PSScriptRoot            # studio/windows
$workspaceRoot = Split-Path -Parent $rootDir           # studio
$repoRoot = Split-Path -Parent $workspaceRoot          # Aura-Studio (raíz del repo macOS)

# Convenir: en la versión Windows los artefactos viven en este directorio,
# el análogo de Vendor/firmware-dist de macOS.
$vendorRoot = Join-Path $rootDir 'artifacts'
$versionFile = Join-Path $repoRoot 'FIRMWARE_VERSION'

# En macOS los nombres de assets son rockbox.ipod, mks5lboot, etc. En
# Windows, el binario que antes se llamaba `mks5lboot` ahora es
# `mks5lboot.exe` (producido por el cross-compile de mingw-w64, Fase
# II.3). El resto de nombres de Release no cambia: es el mismo asset
# publicado por el firmware.
$assets = @('rockbox.ipod', 'rockbox.zip', 'mks5lboot.exe', 'checksums.txt')
$optionalAssets = @('bootloader-ipod6g.ipod', 'AuraPalette.swift', 'MODIFICATIONS.md',
                    'theme-format-v1.json', 'aura-theme-default.zip', 'THIRD-PARTY-NOTICES.txt')

# Por familia: repositorio, prefijo de clave en FIRMWARE_VERSION y destino.
# Se fija con Set-Family antes de cualquier operación.
$families = [ordered]@{
    aura    = @{ Repo = 'Ricolinos/Aura-Firmware'; KeyPrefix = '';     Dir = $vendorRoot }
    metro   = @{ Repo = 'Ricolinos/Metro-Aura';    KeyPrefix = 'metro.'; Dir = (Join-Path $vendorRoot 'metro') }
    moonlit = @{ Repo = 'Ricolinos/moonlit-aura';  KeyPrefix = 'moonlit.'; Dir = (Join-Path $vendorRoot 'moonlit') }
}

function Clear-DownloadedFiles {
    param([string]$Dir)
    # Limpia lo que va a volver a bajarse, PRESERVANDO lo que no viene del
    # Release. `mks5lboot.exe` es nuestro cross-compile para Windows (§A publica
    # el `mks5lboot` de Unix, no un .exe) y vive versionado en el repositorio con
    # su archivo de procedencia al lado: borrarlo en cada fetch dejaba a la app
    # sin herramienta de grabado hasta restaurarla del índice a mano.
    $preserve = @('mks5lboot.exe', 'mks5lboot.exe.origin')
    Get-ChildItem -Path $Dir -File -Force |
        Where-Object { $preserve -notcontains $_.Name } |
        Remove-Item -Force
}
function Write-VersionMarker {
    param([string]$Dir, [string]$Tag)
    # Deja junto a los artefactos el tag descargado, para que la pantalla
    # de Licencias de la app (CONTRATO §B) pueda mostrarlo sin leer
    # FIRMWARE_VERSION, que no viaja en el bundle.
    Set-Content -Path (Join-Path $Dir 'firmware-version.txt') -Value $Tag -Encoding UTF8
}

function Verify-Checksums {
    param([string]$Dir)
    Write-Host "==> Verificando checksums en $Dir"
    $checksumsPath = Join-Path $Dir 'checksums.txt'
    if (-not (Test-Path $checksumsPath)) {
        throw "ERROR: falta checksums.txt en $Dir"
    }
    # shasum -c (en macOS) ignora entradas cuyo archivo no está presente;
    # lo replicamos: solo comparamos los archivos presentes. Pero SI falla
    # si un archivo presente no coincide con su hash esperado.
    $lines = Get-Content -Path $checksumsPath
    $present = @()
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        # Formato de checksums.txt: "<sha256>  <nombre>"
        $parts = $line -split '\s+', 2
        $hashExpected = $parts[0]
        $fileName = ($parts[1] -replace '^[*]?', '').Trim()
        if ([string]::IsNullOrWhiteSpace($fileName)) { continue }
        if (Test-Path (Join-Path $Dir $fileName)) {
            $present += [PSCustomObject]@{ Hash = $hashExpected; File = $fileName }
        }
    }
    if ($present.Count -eq 0) {
        throw "ERROR: checksums.txt no describe ningun archivo presente en $Dir"
    }
    foreach ($item in $present) {
        $filePath = Join-Path $Dir $item.File
        $actual = (Get-FileHash -Path $filePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $item.Hash.ToLowerInvariant()) {
            throw "ERROR: hash no coincide para $($item.File): esperado $($item.Hash), obtenido $actual"
        }
    }
    Write-Host "==> Checksums OK ($($present.Count) archivo(s) verificados)"
}

function Restore-ExecBit {
    param([string]$Dir)
    # En Windows no existe bit de ejecución POSIX; los .exe se ejecutan
    # igual. La función se mantiene como no-op para preservar el contrato
    # del script original y dejar documentado por qué no hace nada aquí.
    # (En macOS este paso evitaba el ST-018 al restaurar +x a mks5lboot.)
}

function Write-DevMarkerIfNeeded {
    param([string]$Dir)
    # Sin acción adicional en Windows; write_version_marker se llama desde
    # cada modo por separado.
}

function Copy-FromDir {
    param([string]$Src, [string]$Dir)
    if (-not (Test-Path $Src)) {
        throw "ERROR: $Src no existe"
    }
    Write-Host "==> [$FamilyName] Copiando artefactos locales desde $Src (modo desarrollo, -FromDir)"
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    # Solo archivos de nivel superior: borrar nuevos en la raíz no toca
    # los subdirectorios metro/ moonlit/.
    Clear-DownloadedFiles -Dir $Dir
    foreach ($f in ($assets + $optionalAssets)) {
        $srcFile = Join-Path $Src $f
        if (Test-Path $srcFile) {
            Copy-Item -Path $srcFile -Destination (Join-Path $Dir $f) -Force
        }
    }
    foreach ($f in $assets) {
        if (-not (Test-Path (Join-Path $Dir $f))) {
            throw "ERROR: falta $f en $Src -- corre package_dist.sh alla primero"
        }
    }
    Verify-Checksums -Dir $Dir
    Restore-ExecBit -Dir $Dir
    Write-VersionMarker -Dir $Dir -Tag 'local-dev'
    Write-Host "==> Listo: $Dir (modo desarrollo)"
}

function Copy-FromRelease {
    param([string]$Dir, [string]$Repo, [string]$KeyPrefix)
    if (-not (Test-Path $versionFile)) {
        throw "ERROR: falta $versionFile (tags de los Releases a usar)"
    }
    $tag = $null
    # Solo la clave exacta al inicio de línea: para Aura (prefijo vacío)
    # NO deben casar ni comentarios ni `metro.tag=`/`moonlit.tag=`.
    $tagPattern = '^' + [regex]::Escape($KeyPrefix) + 'tag=(.+)$'
    foreach ($line in (Get-Content -Path $versionFile)) {
        if ($line -match '^\s*#') { continue }
        if ($line -match $tagPattern) {
            $tag = $Matches[1].Trim()
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($tag)) {
        throw "ERROR: $versionFile no define '$($KeyPrefix)tag=' -- ver FIRMWARE_VERSION.example"
    }
    Write-Host "==> [$FamilyName] Descargando Release $tag de $Repo (gh release download)"
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    Clear-DownloadedFiles -Dir $Dir
    # Nota: `gh release download` en Windows con un asset llamado
    # mks5lboot.exe depende de que el Release del firmware publique ese
    # nombre. Si el Release continúa publicando `mks5lboot`, adaptar el
    # nombre aquí (ver Notas de la Fase II.3). El download descarga todo
    # lo del release; `--pattern` opcional para filtrar si hiciera falta.
    & gh release download $tag --repo $Repo --dir $Dir --clobber
    if ($LASTEXITCODE -ne 0) {
        throw "ERROR: gh release download falló para $Repo@$tag"
    }
    Verify-Checksums -Dir $Dir
    Restore-ExecBit -Dir $Dir
    Write-VersionMarker -Dir $Dir -Tag $tag
    Write-Host "==> Listo: $Dir ($tag)"
}

# --- Selección de familia(s) ---
$selected = @()
if (-not [string]::IsNullOrWhiteSpace($Family)) {
    if (-not $families.Contains($Family)) {
        Write-Error "ERROR: familia desconocida '$Family' (aura|metro|moonlit)"
        exit 1
    }
    $selected = @($Family)
} else {
    $selected = @($families.Keys)
}

# --- -FromDir es un dist concreto de UNA familia ---
if (-not [string]::IsNullOrWhiteSpace($FromDir) -and $selected.Count -ne 1) {
    $selected = @('aura')   # compatibilidad: el script original siempre asumía Aura
}

foreach ($famKey in $selected) {
    $Global:FamilyName = $famKey
    $cfg = $families[$famKey]
    $dir = $cfg.Dir
    if (-not [string]::IsNullOrWhiteSpace($FromDir)) {
        Copy-FromDir -Src $FromDir -Dir $dir
    } else {
        Copy-FromRelease -Dir $dir -Repo $cfg.Repo -KeyPrefix $cfg.KeyPrefix
    }
}
