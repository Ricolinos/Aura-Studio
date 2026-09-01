using System.Text.Json;
using System.Text.Json.Serialization;

namespace AuraStudio.Core.Library;

/// <summary>
/// Lee una fecha del catálogo venga como venga: **número** (lo que escribe
/// Swift) o **texto ISO 8601** (lo que escribe esta app). Siempre escribe ISO.
///
/// <para><b>Por qué existe.</b> `Codable` de Swift codifica un `Date` como los
/// segundos transcurridos desde el 1 de enero de <b>2001</b> — no desde 1970 —,
/// y sin esto un `"addedAt" : 808784218.004062` hace fallar la lectura del
/// archivo <b>entero</b>. Se descubrió con el catálogo real del dueño: 2809
/// elementos hechos en la Mac que esta app mostraba como biblioteca vacía,
/// porque el error de una sola fecha se tragaba todo el catálogo.</para>
///
/// <para>Es la misma regla que ya se había escrito para los campos nuevos
/// (ST-083): <b>un campo no puede tirar el catálogo entero</b>. Acá la regla
/// existía y el código no la cumplía.</para>
/// </summary>
public sealed class AppleEpochDateConverter : JsonConverter<DateTimeOffset>
{
    /// <summary>El 1 de enero de 2001, UTC: el cero de las fechas de Apple.</summary>
    public static readonly DateTimeOffset AppleEpoch = new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);

    public static DateTimeOffset FromAppleSeconds(double seconds) =>
        AppleEpoch.AddSeconds(seconds);

    public static double ToAppleSeconds(DateTimeOffset value) =>
        (value - AppleEpoch).TotalSeconds;

    public override DateTimeOffset Read(
        ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.Number)
            return FromAppleSeconds(reader.GetDouble());

        if (reader.TokenType == JsonTokenType.String)
        {
            string? text = reader.GetString();

            if (DateTimeOffset.TryParse(text, System.Globalization.CultureInfo.InvariantCulture,
                    System.Globalization.DateTimeStyles.RoundtripKind, out DateTimeOffset parsed))
                return parsed;

            // Un texto que no es fecha: se trata como "no se sabe cuándo", que
            // es exactamente lo que significa. Tirar el catálogo por esto sería
            // desproporcionado.
            return AppleEpoch;
        }

        return AppleEpoch;
    }

    /// <summary>
    /// Se escribe <b>el número de Apple</b>, no ISO 8601.
    ///
    /// <para>La biblioteca es compartida entre las dos apps: el dueño usa la
    /// misma carpeta desde la Mac y desde Windows. La app de macOS decodifica
    /// con un <c>JSONDecoder()</c> por omisión, que para un <c>Date</c> espera
    /// un número — y lo hace con <c>try?</c>, así que un texto ISO no da error
    /// visible: <b>deja la biblioteca vacía en silencio</b>. Escribir el número
    /// es lo único que la Mac puede volver a leer.</para>
    /// </summary>
    public override void Write(
        Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options) =>
        writer.WriteNumberValue(ToAppleSeconds(value));
}
