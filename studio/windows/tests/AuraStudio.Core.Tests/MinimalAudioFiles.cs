namespace AuraStudio.Core.Tests;

/// <summary>
/// Archivos de audio mínimos pero <b>válidos</b>, escritos en el momento
/// (ST-242). No son música: son el envase, que es lo único que hace falta para
/// que TagLib# abra el archivo y le escriba etiquetas de verdad.
///
/// <para>Existe para no depender de tener música en el disco ni de un fixture
/// compartido: las pruebas de etiquetas tienen que poder correr en cualquier
/// máquina y en cualquier orden. El arnés de B0 arma un fixture más completo
/// —con archivos de verdad— y es el que sirve para medir; esto es para
/// verificar reglas.</para>
/// </summary>
internal static class MinimalAudioFiles
{
    /// <summary>Cuarenta tramas MPEG-1 Layer III de 128 kbps / 44,1 kHz.</summary>
    public static void WriteMp3(string path)
    {
        var frame = new List<byte> { 0xFF, 0xFB, 0x90, 0x64 };
        frame.AddRange(new byte[413]);

        var bytes = new List<byte>();
        for (int i = 0; i < 40; i++) bytes.AddRange(frame);

        Write(path, [.. bytes]);
    }

    /// <summary>
    /// Un FLAC con solo su bloque <c>STREAMINFO</c>: firma <c>fLaC</c>, cabecera
    /// de bloque (último, tipo 0, 34 bytes) y los 34 bytes del bloque. Sin
    /// tramas de audio — el contenedor es válido igual, y las etiquetas van en
    /// bloques de metadata, no en el audio.
    /// </summary>
    public static void WriteFlac(string path)
    {
        var bytes = new List<byte> { 0x66, 0x4C, 0x61, 0x43 };   // "fLaC"

        bytes.Add(0x80);                                          // último bloque + tipo 0 (STREAMINFO)
        bytes.AddRange([0x00, 0x00, 0x22]);                       // longitud: 34

        bytes.AddRange(BigEndian16(4096));                        // bloque mínimo
        bytes.AddRange(BigEndian16(4096));                        // bloque máximo
        bytes.AddRange(BigEndian24(0));                           // trama mínima (desconocida)
        bytes.AddRange(BigEndian24(0));                           // trama máxima (desconocida)

        // 20 bits de frecuencia, 3 de canales-1, 5 de bits-1, 36 de muestras.
        ulong packed = ((ulong)44100 << 44) | ((ulong)1 << 41) | ((ulong)15 << 36) | 44100;
        for (int shift = 56; shift >= 0; shift -= 8) bytes.Add((byte)(packed >> shift));

        bytes.AddRange(new byte[16]);                             // MD5 del audio: sin calcular

        Write(path, [.. bytes]);
    }

    /// <summary>
    /// Un M4A mínimo: <c>ftyp</c> + <c>moov</c> con la cadena que exige el
    /// formato (<c>mvhd</c>, y un <c>trak</c> de audio hasta el
    /// <c>stbl</c>) + un <c>mdat</c> vacío.
    ///
    /// <para>Es el más largo de los tres porque MP4 no tiene atajo: las
    /// etiquetas viven en <c>moov/udta/meta/ilst</c>, y para llegar ahí el
    /// archivo tiene que ser un MP4 de verdad. TagLib# crea el <c>udta</c> él
    /// mismo al guardar.</para>
    /// </summary>
    public static void WriteM4a(string path)
    {
        byte[] ftyp = Box("ftyp",
        [
            .. Ascii("M4A "),
            .. BigEndian32(0x200),
            .. Ascii("M4A "), .. Ascii("isom"), .. Ascii("mp42")
        ]);

        byte[] mvhd = FullBox("mvhd", 0,
        [
            .. BigEndian32(0), .. BigEndian32(0),                 // creación y modificación
            .. BigEndian32(44100),                                // escala de tiempo
            .. BigEndian32(44100),                                // duración: un segundo
            .. BigEndian32(0x00010000),                           // velocidad 1.0
            .. BigEndian16(0x0100), .. new byte[2],               // volumen 1.0 + reservado
            .. new byte[8],                                       // reservado
            .. UnityMatrix(),
            .. new byte[24],                                      // predefinidos
            .. BigEndian32(2)                                     // próximo id de pista
        ]);

        byte[] tkhd = FullBox("tkhd", 0x000007,                   // habilitada, en película, en vista previa
        [
            .. BigEndian32(0), .. BigEndian32(0),
            .. BigEndian32(1),                                    // id de pista
            .. new byte[4],                                       // reservado
            .. BigEndian32(44100),                                // duración
            .. new byte[8],                                       // reservado
            .. BigEndian16(0), .. BigEndian16(0),                 // capa y grupo alterno
            .. BigEndian16(0x0100), .. new byte[2],               // volumen 1.0 (audio) + reservado
            .. UnityMatrix(),
            .. BigEndian32(0), .. BigEndian32(0)                  // ancho y alto: audio
        ]);

        byte[] mdhd = FullBox("mdhd", 0,
        [
            .. BigEndian32(0), .. BigEndian32(0),
            .. BigEndian32(44100),                                // escala
            .. BigEndian32(44100),                                // duración
            .. BigEndian16(0x55C4),                               // idioma "und"
            .. BigEndian16(0)
        ]);

        byte[] hdlr = FullBox("hdlr", 0,
        [
            .. new byte[4],                                       // predefinido
            .. Ascii("soun"),
            .. new byte[12],                                      // reservado
            0                                                     // nombre vacío
        ]);

        byte[] smhd = FullBox("smhd", 0, [.. BigEndian16(0), .. BigEndian16(0)]);

        byte[] dref = FullBox("dref", 0, [.. BigEndian32(1), .. FullBox("url ", 1, [])]);
        byte[] dinf = Box("dinf", dref);

        byte[] mp4a = Box("mp4a",
        [
            .. new byte[6],                                       // reservado
            .. BigEndian16(1),                                    // índice de referencia de datos
            .. new byte[8],                                       // reservado
            .. BigEndian16(2),                                    // canales
            .. BigEndian16(16),                                   // bits por muestra
            .. BigEndian16(0), .. BigEndian16(0),                 // predefinido y reservado
            .. BigEndian32(44100 << 16)                           // frecuencia en 16.16
        ]);

        byte[] stbl = Box("stbl",
        [
            .. FullBox("stsd", 0, [.. BigEndian32(1), .. mp4a]),
            .. FullBox("stts", 0, BigEndian32(0)),
            .. FullBox("stsc", 0, BigEndian32(0)),
            .. FullBox("stsz", 0, [.. BigEndian32(0), .. BigEndian32(0)]),
            .. FullBox("stco", 0, BigEndian32(0))
        ]);

        byte[] minf = Box("minf", [.. smhd, .. dinf, .. stbl]);
        byte[] mdia = Box("mdia", [.. mdhd, .. hdlr, .. minf]);
        byte[] trak = Box("trak", [.. tkhd, .. mdia]);
        byte[] moov = Box("moov", [.. mvhd, .. trak]);
        byte[] mdat = Box("mdat", []);

        Write(path, [.. ftyp, .. moov, .. mdat]);
    }

    // MARK: - Cajas MP4

    private static byte[] Box(string type, byte[] payload) =>
        [.. BigEndian32(8 + payload.Length), .. Ascii(type), .. payload];

    private static byte[] FullBox(string type, int flags, byte[] payload) =>
        Box(type, [0, (byte)(flags >> 16), (byte)(flags >> 8), (byte)flags, .. payload]);

    /// <summary>La matriz identidad de MP4, en 16.16 salvo la última fila (2.30).</summary>
    private static byte[] UnityMatrix() =>
    [
        .. BigEndian32(0x00010000), .. BigEndian32(0), .. BigEndian32(0),
        .. BigEndian32(0), .. BigEndian32(0x00010000), .. BigEndian32(0),
        .. BigEndian32(0), .. BigEndian32(0), .. BigEndian32(0x40000000)
    ];

    private static byte[] Ascii(string value) => System.Text.Encoding.ASCII.GetBytes(value);

    private static byte[] BigEndian32(int value) =>
        [(byte)(value >> 24), (byte)(value >> 16), (byte)(value >> 8), (byte)value];

    private static byte[] BigEndian24(int value) =>
        [(byte)(value >> 16), (byte)(value >> 8), (byte)value];

    private static byte[] BigEndian16(int value) => [(byte)(value >> 8), (byte)value];

    private static void Write(string path, byte[] bytes)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, bytes);
    }
}
