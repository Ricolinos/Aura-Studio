using System.Text.Json;
using System.Text.Json.Serialization;

namespace AuraStudio.Core.Library;

/// <summary>
/// Lee un entero opcional del catálogo sin que un valor imposible se lleve por
/// delante el archivo entero.
///
/// <para><b>El caso real.</b> En el catálogo del dueño, una canción tenía
/// <c>"trackNumber" : 4294967295</c> — el máximo de un entero sin signo de 32
/// bits, que es lo que devuelve una etiqueta rota leída como "sin signo". No
/// cabe en un <c>int</c>, así que la lectura fallaba y se perdían los 2809
/// elementos del catálogo por una sola canción de Kesha.</para>
///
/// <para>Un número de pista que no cabe en un entero no es un número de pista:
/// <b>vale más "no sé" que perder la biblioteca</b>. Lo mismo para el disco, la
/// calificación, la temporada y el episodio.</para>
/// </summary>
public sealed class TolerantInt32Converter : JsonConverter<int?>
{
    public override int? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        switch (reader.TokenType)
        {
            case JsonTokenType.Null:
                return null;

            case JsonTokenType.Number:
                // Fuera de rango, o con decimales: no es un número de pista.
                return reader.TryGetInt32(out int value) ? Sanitize(value) : null;

            case JsonTokenType.String:
                // Alguna herramienta escribe "4" en vez de 4.
                return int.TryParse(reader.GetString(), out int parsed) ? Sanitize(parsed) : null;

            default:
                return null;
        }
    }

    /// <summary>
    /// Un negativo tampoco es un número de pista válido. Cero sí se conserva:
    /// es lo que significa "sin número" en los átomos de iTunes, y esa
    /// distinción ya la maneja <see cref="TrackTagRules"/>.
    /// </summary>
    private static int? Sanitize(int value) => value < 0 ? null : value;

    public override void Write(Utf8JsonWriter writer, int? value, JsonSerializerOptions options)
    {
        if (value is null) writer.WriteNullValue();
        else writer.WriteNumberValue(value.Value);
    }
}
