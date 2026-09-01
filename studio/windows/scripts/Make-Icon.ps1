# Make-Icon.ps1
#
# Genera `AuraStudio.App/Assets/AuraStudio.ico` a partir del master que entregó
# el dueño (`studio/windows/icono/Aura icono.png`, 1088x1088, 32 bpp con alfa).
#
# El master es la FUENTE ÚNICA: este script solo lo lee. No lo edita, no lo
# mueve y no lo reemplaza. Si el icono tiene que cambiar, cambia el master y se
# vuelve a correr esto — nada de conversiones a mano irrepetibles.
#
# Por qué un script y no una herramienta: en esta VM no hay ImageMagick, y
# System.Drawing con interpolación HighQualityBicubic alcanza de sobra para
# reducir un PNG cuadrado con alfa. Lo que System.Drawing NO sabe hacer es
# escribir un .ico multi-tamaño, así que el contenedor se arma acá byte a byte
# (es un formato chico y estable: cabecera, una entrada por tamaño, y los datos).
#
# Uso:
#   .\Make-Icon.ps1                 genera el .ico
#   .\Make-Icon.ps1 -WhatIfOnly     dice qué haría, sin escribir
#
# Los assets de MSIX (Square44x44, Square150x150, StoreLogo...) NO salen de acá:
# se derivan del mismo master en la Fase 7 (empaquetado).

param(
    [switch]$WhatIfOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# Sin esto la consola muestra los acentos de los mensajes como basura.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$windowsRoot = Split-Path -Parent $PSScriptRoot
$master      = Join-Path $windowsRoot 'icono\Aura icono.png'
$outputDir   = Join-Path $windowsRoot 'AuraStudio.App\Assets'
$output      = Join-Path $outputDir 'AuraStudio.ico'

# 256 va como PNG comprimido (es lo que espera Windows para ese tamaño y evita
# un .ico enorme); el resto como BMP de 32 bpp, que es lo más compatible para
# los tamaños chicos. Orden descendente: los visores toman el primero que les
# sirve y así el grande queda al frente.
$pngSize    = 256
$bmpSizes   = @(64, 48, 32, 24, 20, 16)

function Resize-Master {
    param([System.Drawing.Image]$Source, [int]$Size)

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bmp.SetResolution(96, 96)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.CompositingMode    = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.Clear([System.Drawing.Color]::Transparent)

        # TileFlipXY evita el halo transparente que deja el muestreo en el borde
        # de la imagen al reducir mucho.
        $attr = New-Object System.Drawing.Imaging.ImageAttributes
        $attr.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
        $rect = New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)
        $g.DrawImage($Source, $rect, 0, 0, $Source.Width, $Source.Height,
                     [System.Drawing.GraphicsUnit]::Pixel, $attr)
        $attr.Dispose()
    }
    finally { $g.Dispose() }
    return $bmp
}

function Get-PngBytes {
    param([System.Drawing.Bitmap]$Bitmap)
    $ms = New-Object System.IO.MemoryStream
    $Bitmap.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bytes = $ms.ToArray()
    $ms.Dispose()
    return ,$bytes
}

function Get-IcoBmpBytes {
    param([System.Drawing.Bitmap]$Bitmap)

    # Dentro de un .ico, una entrada BMP lleva BITMAPINFOHEADER con el ALTO
    # DUPLICADO (la imagen y su máscara AND), los píxeles BGRA de abajo hacia
    # arriba, y después la máscara. Con 32 bpp la transparencia la da el canal
    # alfa, así que la máscara va en ceros — pero tiene que estar.
    $w = $Bitmap.Width
    $h = $Bitmap.Height
    $maskStride = [int](([math]::Floor(($w + 31) / 32)) * 4)
    $maskSize   = $maskStride * $h
    $pixelSize  = $w * $h * 4

    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)

    $bw.Write([int]40)                 # biSize
    $bw.Write([int]$w)                 # biWidth
    $bw.Write([int]($h * 2))           # biHeight (imagen + máscara)
    $bw.Write([int16]1)                # biPlanes
    $bw.Write([int16]32)               # biBitCount
    $bw.Write([int]0)                  # biCompression = BI_RGB
    $bw.Write([int]($pixelSize + $maskSize))
    $bw.Write([int]0); $bw.Write([int]0)   # resolución: irrelevante en un icono
    $bw.Write([int]0); $bw.Write([int]0)   # biClrUsed, biClrImportant

    $data = $Bitmap.LockBits(
        (New-Object System.Drawing.Rectangle(0, 0, $w, $h)),
        [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $row = New-Object byte[] ($w * 4)
        for ($y = $h - 1; $y -ge 0; $y--) {
            $src = [IntPtr]::Add($data.Scan0, $y * $data.Stride)
            [System.Runtime.InteropServices.Marshal]::Copy($src, $row, 0, $row.Length)
            $bw.Write($row, 0, $row.Length)
        }
    }
    finally { $Bitmap.UnlockBits($data) }

    $bw.Write((New-Object byte[] $maskSize))
    $bw.Flush()
    $bytes = $ms.ToArray()
    $bw.Dispose(); $ms.Dispose()
    return ,$bytes
}

# --- Lectura del master ---

if (-not (Test-Path $master)) {
    throw "ERROR: no está el master del icono en $master"
}

$source = [System.Drawing.Image]::FromFile($master)
try {
    Write-Host "==> Master: $master ($($source.Width)x$($source.Height), $($source.PixelFormat))"
    if ($source.Width -ne $source.Height) {
        throw "ERROR: el master no es cuadrado ($($source.Width)x$($source.Height)); un icono de Windows sí lo es."
    }

    $images = @()
    foreach ($size in (@($pngSize) + $bmpSizes)) {
        $bmp = Resize-Master -Source $source -Size $size
        $bytes = if ($size -eq $pngSize) { Get-PngBytes -Bitmap $bmp } else { Get-IcoBmpBytes -Bitmap $bmp }
        $images += [PSCustomObject]@{ Size = $size; Bytes = $bytes; IsPng = ($size -eq $pngSize) }
        $bmp.Dispose()
        Write-Host ("    {0,3} px  {1,8:N0} bytes  {2}" -f $size, $bytes.Length, $(if ($size -eq $pngSize) { 'PNG' } else { 'BMP' }))
    }
}
finally { $source.Dispose() }

if ($WhatIfOnly) {
    Write-Host "==> -WhatIfOnly: no se escribió nada. Se habría generado $output"
    return
}

# --- Contenedor .ico ---

New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$fs = [System.IO.File]::Create($output)
$bw = New-Object System.IO.BinaryWriter($fs)
try {
    $bw.Write([int16]0)                  # reservado
    $bw.Write([int16]1)                  # tipo: 1 = icono
    $bw.Write([int16]$images.Count)

    # Los datos empiezan después de la cabecera y de todas las entradas.
    $offset = 6 + (16 * $images.Count)
    foreach ($img in $images) {
        # 0 significa 256: el campo es de un byte.
        $dim = if ($img.Size -ge 256) { 0 } else { $img.Size }
        $bw.Write([byte]$dim)            # ancho
        $bw.Write([byte]$dim)            # alto
        $bw.Write([byte]0)               # colores de la paleta: ninguna
        $bw.Write([byte]0)               # reservado
        $bw.Write([int16]1)              # planos
        $bw.Write([int16]32)             # bits por píxel
        $bw.Write([int]$img.Bytes.Length)
        $bw.Write([int]$offset)
        $offset += $img.Bytes.Length
    }
    foreach ($img in $images) { $bw.Write($img.Bytes) }
}
finally { $bw.Dispose(); $fs.Dispose() }

$final = Get-Item $output
Write-Host "==> Listo: $output ($('{0:N0}' -f $final.Length) bytes, $($images.Count) tamaños)"
