using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace ImageResizerCheck;

public static class Orient
{
    static IBuffer Buf(byte[] b) { var w = new DataWriter(); w.WriteBytes(b); return w.DetachBuffer(); }
    static byte[] Bytes(IBuffer b) { var a = new byte[b.Length]; DataReader.FromBuffer(b).ReadBytes(a); return a; }

    /// JPEG de 400x200 (horizontal) con EXIF orientation = 6 (rotar 90 CW),
    /// o sea que ORIENTADO mide 200x400 (vertical).
    public static async Task<byte[]> MakeRotatedJpeg()
    {
        int w = 400, h = 200;
        var px = new byte[w * h * 4];
        for (int i = 0; i < px.Length; i += 4) { px[i] = 30; px[i + 1] = 90; px[i + 2] = 200; px[i + 3] = 255; }
        var bmp = new SoftwareBitmap(BitmapPixelFormat.Bgra8, w, h, BitmapAlphaMode.Ignore);
        bmp.CopyFromBuffer(Buf(px));

        using var s = new InMemoryRandomAccessStream();
        var enc = await BitmapEncoder.CreateAsync(BitmapEncoder.JpegEncoderId, s);
        enc.SetSoftwareBitmap(bmp);
        await enc.BitmapProperties.SetPropertiesAsync(new[]
        {
            new KeyValuePair<string, BitmapTypedValue>(
                "System.Photo.Orientation",
                new BitmapTypedValue((ushort)6, Windows.Foundation.PropertyType.UInt16))
        });
        await enc.FlushAsync();
        s.Seek(0);
        var outBuf = new Windows.Storage.Streams.Buffer((uint)s.Size);
        await s.ReadAsync(outBuf, (uint)s.Size, InputStreamOptions.None);
        return Bytes(outBuf);
    }
}
