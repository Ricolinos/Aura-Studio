// Verificación del redimensionado de fotos:
//
//     dotnet run --project tools\ImageResizerCheck -c Release
//
// Sale con 0 si todo pasó. Ver ImageResizerCheck.csproj para por qué esto no
// vive en AuraStudio.Core.Tests.

using AuraStudio.App.Platform;
using AuraStudio.Core.Library;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

static IBuffer Buf(byte[] b) { var w = new DataWriter(); w.WriteBytes(b); return w.DetachBuffer(); }
static byte[] Bytes(IBuffer b) { var a = new byte[b.Length]; DataReader.FromBuffer(b).ReadBytes(a); return a; }

// Un PNG con transparencia: la mitad izquierda roja opaca, la derecha totalmente transparente.
static async Task<byte[]> MakePngWithAlpha(int w, int h)
{
    var px = new byte[w * h * 4];
    for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++)
        {
            int i = (y * w + x) * 4;
            bool left = x < w / 2;
            px[i + 0] = 0; px[i + 1] = 0; px[i + 2] = 255;          // BGRA -> rojo
            px[i + 3] = (byte)(left ? 255 : 0);
        }
    var bmp = new SoftwareBitmap(BitmapPixelFormat.Bgra8, w, h, BitmapAlphaMode.Straight);
    bmp.CopyFromBuffer(Buf(px));
    using var s = new InMemoryRandomAccessStream();
    var enc = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, s);
    enc.SetSoftwareBitmap(bmp);
    await enc.FlushAsync();
    s.Seek(0);
    var outBuf = new Windows.Storage.Streams.Buffer((uint)s.Size);
    await s.ReadAsync(outBuf, (uint)s.Size, InputStreamOptions.None);
    return Bytes(outBuf);
}

static async Task<(int w, int h, byte[] px)> DecodeAsync(byte[] jpeg)
{
    using var s = new InMemoryRandomAccessStream();
    await s.WriteAsync(Buf(jpeg));
    s.Seek(0);
    var d = await BitmapDecoder.CreateAsync(s);
    var bmp = await d.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore);
    var buf = new Windows.Storage.Streams.Buffer((uint)(bmp.PixelWidth * bmp.PixelHeight * 4));
    bmp.CopyToBuffer(buf);
    return (bmp.PixelWidth, bmp.PixelHeight, Bytes(buf));
}

int fallas = 0;
void Check(string nombre, bool ok, string detalle = "")
{
    Console.WriteLine($"{(ok ? "OK  " : "FALLA")} {nombre} {detalle}");
    if (!ok) fallas++;
}

// 1) Una foto grande se reduce a 320 en el lado mayor, conservando aspecto.
byte[] grande = await MakePngWithAlpha(1600, 1200);
byte[] jpeg = await ImageResizer.EncodeAsync(grande, 320, 0.85);
var (w, h, px) = await DecodeAsync(jpeg);
Check("tamaño 1600x1200 -> 320x240", w == 320 && h == 240, $"({w}x{h})");

// 2) La salida es JPEG baseline (D-291) segun el propio verificador y de hecho.
Check("salida baseline", JpegMarkers.IsBaseline(jpeg));

// 3) La mitad transparente quedo BLANCA, no negra.
int cx = (int)(w * 0.75), cy = h / 2, idx = (cy * w + cx) * 4;
Check("transparente -> blanco", px[idx] > 240 && px[idx + 1] > 240 && px[idx + 2] > 240,
      $"(B={px[idx]} G={px[idx + 1]} R={px[idx + 2]})");

// 4) La mitad opaca sigue roja.
int lx = w / 4, li = (cy * w + lx) * 4;
Check("opaco intacto (rojo)", px[li + 2] > 200 && px[li] < 60 && px[li + 1] < 60,
      $"(B={px[li]} G={px[li + 1]} R={px[li + 2]})");

// 5) Una imagen chica NO se agranda.
byte[] chica = await MakePngWithAlpha(100, 80);
var (w2, h2, _) = await DecodeAsync(await ImageResizer.EncodeAsync(chica, 320, 0.85));
Check("100x80 no se agranda", w2 == 100 && h2 == 80, $"({w2}x{h2})");

// 6) Calidad alta = 640 como maximo del firmware.
var (w3, h3, _) = await DecodeAsync(await ImageResizer.EncodeAsync(await MakePngWithAlpha(3200, 2400), 640, 0.85));
Check("3200x2400 -> 640x480", w3 == 640 && h3 == 480, $"({w3}x{h3})");

// 7) Una entrada que no es imagen falla con mensaje claro, no revienta raro.
try { await ImageResizer.EncodeAsync(new byte[] { 1, 2, 3, 4 }, 320, 0.85); Check("basura rechazada", false); }
catch (ImageResizeException e) { Check("basura rechazada", true, $"\"{e.Message}\""); }

// 8) Escribir a archivo crea el directorio y deja el JPEG.
string dir = Path.Combine(Path.GetTempPath(), "imgcheck-" + Guid.NewGuid().ToString("N"), "sub");
string dest = Path.Combine(dir, "foto.jpg");
await ImageResizer.ResizeToLcdOptimalAsync(grande, dest);
Check("escribe creando carpetas", File.Exists(dest) && JpegMarkers.IsBaseline(File.ReadAllBytes(dest)));
Directory.Delete(Path.GetDirectoryName(dir)!, true);


// 9) Una foto con orientacion EXIF llega derecha (una vertical de camara viene
//    guardada horizontal con la rotacion en EXIF).
byte[] rotada = await ImageResizerCheck.Orient.MakeRotatedJpeg();
var (w4, h4, _) = await DecodeAsync(await ImageResizer.EncodeAsync(rotada, 320, 0.85));
Check("EXIF orientacion 6: 400x200 -> vertical 160x320", w4 == 160 && h4 == 320, $"({w4}x{h4})");

// --- Miniaturas de carátula (CoverThumbnailCache) ---

// 10) Una carátula 16:9 NO se deforma a cuadrado: el bug que se vio en macOS.
byte[] ancha = await MakePngWithAlpha(800, 450);
var mini = await CoverThumbnailCache.Shared.ThumbnailAsync(ancha, 96);
Check("16:9 conserva aspecto (96x54)", mini is { PixelWidth: 96, PixelHeight: 54 },
      mini is null ? "(null)" : $"({mini.PixelWidth}x{mini.PixelHeight})");

// 11) La misma carátula en dos canciones comparte UNA miniatura.
var a = await CoverThumbnailCache.Shared.ThumbnailAsync(ancha, 96);
var b = await CoverThumbnailCache.Shared.ThumbnailAsync((byte[])ancha.Clone(), 96);
Check("misma carátula, una sola miniatura", ReferenceEquals(a, b));

// 12) El mismo álbum en dos tamaños son dos miniaturas.
var chicaMini = await CoverThumbnailCache.Shared.ThumbnailAsync(ancha, 48);
Check("cada tamaño su miniatura", chicaMini is { PixelWidth: 48 } && !ReferenceEquals(chicaMini, a),
      chicaMini is null ? "(null)" : $"({chicaMini.PixelWidth}x{chicaMini.PixelHeight})");

// 13) Una carátula rota da celda sin imagen, no tumba la cuadrícula.
Check("carátula ilegible -> null", await CoverThumbnailCache.Shared.ThumbnailAsync([1, 2, 3, 4], 96) is null);
Check("sin carátula -> null", await CoverThumbnailCache.Shared.ThumbnailAsync(null, 96) is null);


// --- Imagen por omision de una lista (PlaylistArtGenerator) ---

// Una caratula lisa del color pedido, del tamano pedido.
static async Task<byte[]> MakeSolidPng(int w, int h, byte r, byte g, byte b)
{
    var px = new byte[w * h * 4];
    for (int i = 0; i < px.Length; i += 4) { px[i] = b; px[i + 1] = g; px[i + 2] = r; px[i + 3] = 255; }
    var bmp = new SoftwareBitmap(BitmapPixelFormat.Bgra8, w, h, BitmapAlphaMode.Ignore);
    bmp.CopyFromBuffer(Buf(px));
    using var s = new InMemoryRandomAccessStream();
    var enc = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, s);
    enc.SetSoftwareBitmap(bmp);
    await enc.FlushAsync();
    s.Seek(0);
    var outBuf = new Windows.Storage.Streams.Buffer((uint)s.Size);
    await s.ReadAsync(outBuf, (uint)s.Size, InputStreamOptions.None);
    return Bytes(outBuf);
}

static (byte b, byte g, byte r) At(byte[] px, int w, int x, int y)
{
    int i = (y * w + x) * 4;
    return (px[i], px[i + 1], px[i + 2]);
}
static bool Near((byte b, byte g, byte r) c, int b, int g, int r, int tol = 18)
    => Math.Abs(c.b - b) <= tol && Math.Abs(c.g - g) <= tol && Math.Abs(c.r - r) <= tol;

// 14) Cuatro caratulas distintas -> cada cuadrante con la suya, en orden.
byte[] rojo = await MakeSolidPng(300, 300, 255, 0, 0);
byte[] verde = await MakeSolidPng(300, 300, 0, 255, 0);
byte[] azul = await MakeSolidPng(300, 300, 0, 0, 255);
byte[] amarillo = await MakeSolidPng(300, 300, 255, 255, 0);

var (cw, ch, cpx) = await DecodeAsync(await PlaylistArtGenerator.ComposeAsync([rojo, verde, azul, amarillo]));
Check("colage 128x128", cw == 128 && ch == 128, $"({cw}x{ch})");
Check("cuadrante sup-izq = 1a caratula", Near(At(cpx, cw, 32, 32), 0, 0, 255));
Check("cuadrante sup-der = 2a caratula", Near(At(cpx, cw, 96, 32), 0, 255, 0));
Check("cuadrante inf-izq = 3a caratula", Near(At(cpx, cw, 32, 96), 255, 0, 0));
Check("cuadrante inf-der = 4a caratula", Near(At(cpx, cw, 96, 96), 0, 255, 255));

// 15) Con dos caratulas se reciclan, no quedan cuadrantes negros.
var (dw, _, dpx) = await DecodeAsync(await PlaylistArtGenerator.ComposeAsync([rojo, verde]));
Check("2 caratulas reciclan (inf-izq = 1a)", Near(At(dpx, dw, 32, 96), 0, 0, 255));
Check("2 caratulas reciclan (inf-der = 2a)", Near(At(dpx, dw, 96, 96), 0, 255, 0));

// 16) Una caratula 16:9 llena el cuadrante SIN franjas negras.
byte[] panoramica = await MakeSolidPng(800, 450, 255, 0, 255);
var (pw, _, ppx) = await DecodeAsync(await PlaylistArtGenerator.ComposeAsync([panoramica]));
bool sinFranjas = Near(At(ppx, pw, 32, 2), 255, 0, 255) && Near(At(ppx, pw, 32, 61), 255, 0, 255);
Check("16:9 llena el cuadrante (aspect fill, sin franjas)", sinFranjas,
      $"arriba={At(ppx, pw, 32, 2)} abajo={At(ppx, pw, 32, 61)}");

// 17) Sin caratulas: tile gris con el glifo de lista.
var (nw, _, npx) = await DecodeAsync(await PlaylistArtGenerator.ComposeAsync([]));
Check("tile: fondo E5E5EA en la esquina", Near(At(npx, nw, 4, 4), 0xEA, 0xE5, 0xE5));
// La barra mas ancha esta abajo (y ~ 79..90), la mas angosta arriba (y ~ 38..49).
Check("tile: barra abajo es la mas ancha",
      Near(At(npx, nw, 95, 84), 0x9E, 0x9A, 0x9A) && !Near(At(npx, nw, 95, 43), 0x9E, 0x9A, 0x9A),
      $"abajo={At(npx, nw, 95, 84)} arriba={At(npx, nw, 95, 43)}");
Check("tile: las tres barras existen",
      Near(At(npx, nw, 40, 43), 0x9E, 0x9A, 0x9A) && Near(At(npx, nw, 40, 64), 0x9E, 0x9A, 0x9A)
      && Near(At(npx, nw, 40, 84), 0x9E, 0x9A, 0x9A));

// 18) Una caratula ilegible entre las candidatas no deja un cuadrante negro.
var (gw, _, gpx) = await DecodeAsync(await PlaylistArtGenerator.ComposeAsync([[1, 2, 3, 4], rojo]));
Check("caratula rota se salta", Near(At(gpx, gw, 32, 32), 0, 0, 255), $"{At(gpx, gw, 32, 32)}");

// 19) Escribe el archivo de forma atomica, sin dejar .tmp.
string pdir = Path.Combine(Path.GetTempPath(), "listart-" + Guid.NewGuid().ToString("N"));
string pdest = Path.Combine(pdir, "Rolas.jpg");
await PlaylistArtGenerator.GenerateDefaultAsync([rojo], pdest);
Check("escribe la imagen sin dejar temporales",
      File.Exists(pdest) && JpegMarkers.IsBaseline(File.ReadAllBytes(pdest))
      && Directory.GetFiles(pdir, "*.tmp").Length == 0);
Directory.Delete(pdir, true);

// --- Recorte cuadrado (contrato v18, ST-140) ---

// Un PNG con tres franjas verticales: rojo [0,left), verde [left,right), azul
// [right,w). El recorte centrado tiene que quedarse EXACTAMENTE con la verde,
// asi que las esquinas del resultado delatan un recorte descentrado o un
// "ajuste" con bandas en vez de un relleno.
static async Task<byte[]> MakeBandedPng(int w, int h, int a, int b, bool vertical)
{
    var px = new byte[w * h * 4];
    for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++)
        {
            int i = (y * w + x) * 4;
            int t = vertical ? x : y;
            // BGRA
            if (t < a) { px[i] = 0; px[i + 1] = 0; px[i + 2] = 255; }
            else if (t < b) { px[i] = 0; px[i + 1] = 190; px[i + 2] = 0; }
            else { px[i] = 255; px[i + 1] = 0; px[i + 2] = 0; }
            px[i + 3] = 255;
        }
    var bmp = new SoftwareBitmap(BitmapPixelFormat.Bgra8, w, h, BitmapAlphaMode.Ignore);
    bmp.CopyFromBuffer(Buf(px));
    using var s = new InMemoryRandomAccessStream();
    var enc = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, s);
    enc.SetSoftwareBitmap(bmp);
    await enc.FlushAsync();
    s.Seek(0);
    var outBuf = new Windows.Storage.Streams.Buffer((uint)s.Size);
    await s.ReadAsync(outBuf, (uint)s.Size, InputStreamOptions.None);
    return Bytes(outBuf);
}

static bool Verde(byte[] px, int w, int x, int y)
{
    int i = (y * w + x) * 4;
    return px[i + 1] > 120 && px[i] < 110 && px[i + 2] < 110;   // BGRA
}

// 20) Una caratula 4:3 sale cuadrada de 320 y SIN sus franjas laterales.
byte[] cuatroTercios = await MakeBandedPng(1600, 1200, 200, 1400, vertical: true);
byte[] cuadrada = await ImageResizer.EncodeSquareAsync(cuatroTercios, 320, 0.85);
var (sw, sh, spx) = await DecodeAsync(cuadrada);
Check("4:3 1600x1200 -> 320x320", sw == 320 && sh == 320, $"({sw}x{sh})");
Check("4:3 sin franjas laterales (4 esquinas verdes)",
      Verde(spx, sw, 6, 6) && Verde(spx, sw, 313, 6) && Verde(spx, sw, 6, 313) && Verde(spx, sw, 313, 313),
      $"esquinas={At(spx, sw, 6, 6)} {At(spx, sw, 313, 313)}");
Check("recorte cuadrado sigue siendo baseline", JpegMarkers.IsBaseline(cuadrada));

// 21) Una 16:9 pierde mucho mas de sus lados, con el mismo resultado.
var (nw2, nh2, npx2) = await DecodeAsync(
    await ImageResizer.EncodeSquareAsync(await MakeBandedPng(1920, 1080, 420, 1500, vertical: true), 320, 0.85));
Check("16:9 1920x1080 -> 320x320", nw2 == 320 && nh2 == 320, $"({nw2}x{nh2})");
Check("16:9 sin franjas laterales",
      Verde(npx2, nw2, 6, 6) && Verde(npx2, nw2, 313, 6) && Verde(npx2, nw2, 6, 313) && Verde(npx2, nw2, 313, 313));

// 22) Una fuente 1:4 se recorta por arriba y por abajo (foto de artista, 128).
var (tw, th, tpx) = await DecodeAsync(
    await ImageResizer.EncodeSquareAsync(await MakeBandedPng(300, 1200, 450, 750, vertical: false), 128, 0.85));
Check("1:4 300x1200 -> 128x128", tw == 128 && th == 128, $"({tw}x{th})");
Check("1:4 recortada arriba y abajo",
      Verde(tpx, tw, 4, 4) && Verde(tpx, tw, 123, 4) && Verde(tpx, tw, 4, 123) && Verde(tpx, tw, 123, 123));

// 23) Nunca se agranda: lado corto 200 < 320 pedido -> sale de 200.
var (uw, uh, _) = await DecodeAsync(
    await ImageResizer.EncodeSquareAsync(await MakeBandedPng(400, 200, 100, 300, vertical: true), 320, 0.85));
Check("lado corto 200 no se agranda a 320", uw == 200 && uh == 200, $"({uw}x{uh})");

// 24) Una fuente ya cuadrada solo se reescala.
var (qw, qh, _) = await DecodeAsync(
    await ImageResizer.EncodeSquareAsync(await MakeSolidPng(1000, 1000, 0, 190, 0), 320, 0.85));
Check("1000x1000 -> 320x320 (solo reescalado)", qw == 320 && qh == 320, $"({qw}x{qh})");

// 25) La orientacion EXIF se respeta: 400x200 con orientacion 6 se VE 200x400,
//     asi que el lado corto es 200 y el recorte se planea sobre eso.
var (rw, rh, _) = await DecodeAsync(
    await ImageResizer.EncodeSquareAsync(await ImageResizerCheck.Orient.MakeRotatedJpeg(), 320, 0.85));
Check("EXIF orientacion 6 -> cuadrada de 200", rw == 200 && rh == 200, $"({rw}x{rh})");

// 25b) ST-162: la 8 gira para el otro lado y tambien intercambia los lados. El
//      recorte no distingue las cuatro rotaciones —solo si hay intercambio—,
//      asi que si el decodificador tratara distinto a la 8, se sabe aca.
var (ow2, oh2, _) = await DecodeAsync(
    await ImageResizer.EncodeSquareAsync(await ImageResizerCheck.Orient.MakeRotatedJpeg(8), 320, 0.85));
Check("EXIF orientacion 8 -> cuadrada de 200", ow2 == 200 && oh2 == 200, $"({ow2}x{oh2})");

// 26) Basura rechazada con mensaje claro, igual que el otro camino.
try { await ImageResizer.EncodeSquareAsync(new byte[] { 1, 2, 3, 4 }, 320, 0.85); Check("basura rechazada (cuadrado)", false); }
catch (ImageResizeException e) { Check("basura rechazada (cuadrado)", true, $"\"{e.Message}\""); }

// 27) Escribir a archivo crea la carpeta y deja el JPEG cuadrado.
string sdir = Path.Combine(Path.GetTempPath(), "sqcheck-" + Guid.NewGuid().ToString("N"), "sub");
string sdest = Path.Combine(sdir, "cover.jpg");
await ImageResizer.SquareCropAsync(cuatroTercios, sdest, 320);
var (fw, fh, _) = await DecodeAsync(File.ReadAllBytes(sdest));
Check("escribe cover.jpg de 320x320", fw == 320 && fh == 320 && JpegMarkers.IsBaseline(File.ReadAllBytes(sdest)),
      $"({fw}x{fh})");
Directory.Delete(Path.GetDirectoryName(sdir)!, true);


Console.WriteLine(fallas == 0 ? "TODO BIEN" : $"{fallas} FALLAS");
return fallas;
