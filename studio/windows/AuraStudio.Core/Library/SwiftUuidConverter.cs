using System.Text.Json;
using System.Text.Json.Serialization;

namespace AuraStudio.Core.Library;

/// <summary>
/// Escribe un identificador con el mismo formato que <c>UUID</c> de Swift:
/// <b>mayúsculas</b> con guiones. Al leer acepta las dos formas.
///
/// <para>La biblioteca es compartida entre las dos apps, y aunque
/// <c>UUID(uuidString:)</c> de Foundation no distingue mayúsculas, escribir
/// igual que macOS mantiene el archivo idéntico venga de donde venga: una
/// diferencia de formato en 2809 líneas convierte cualquier comparación entre
/// las dos apps en ruido.</para>
/// </summary>
public sealed class SwiftUuidConverter : JsonConverter<Guid>
{
    public override Guid Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
        Guid.TryParse(reader.GetString(), out Guid value) ? value : Guid.Empty;

    public override void Write(Utf8JsonWriter writer, Guid value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value.ToString("D").ToUpperInvariant());
}
