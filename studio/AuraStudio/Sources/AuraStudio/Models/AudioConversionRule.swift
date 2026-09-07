import Foundation

/// ST-223 (PLAN-studio-ajustes-3.md §0.2/§2): **el único lugar** que
/// decide qué le pasa a un archivo de audio al entrar a la biblioteca en
/// modo copia -- si se copia tal cual, se convierte a ALAC o se convierte
/// a MP3.
///
/// Está aparte y es puro a propósito. La misma decisión hace falta en
/// tres sitios que corren en momentos distintos -- importar en modo copia
/// (A3), regenerar el preparado por id en modo referencia (A4) y el texto
/// que Ajustes le promete al usuario -- y tres copias de una regla es
/// como se llega a que la app haga una cosa y la pantalla diga otra.
///
/// **Por qué WAV y AIFF no se copian nunca tal cual.** Son PCM sin
/// comprimir: un disco entero en WAV ocupa lo que ocuparían cinco o seis
/// álbumes, y el formato no aporta nada que el usuario vaya a oír. Pero
/// convertirlos a MP3 bajo un ajuste que se llama "Mantener formato
/// original" era **perder calidad a escondidas** -- el ajuste decía una
/// cosa y el archivo terminaba siendo otra. Con "Original" van a **ALAC**,
/// que es sin pérdida de verdad, lo hace el codificador del sistema (sin
/// ffmpeg) y además queda etiquetable con `MP4TagWriter`.
enum AudioConversionRule {
    /// Por qué se convierte. No es un detalle de registro: es lo que se
    /// le dice al usuario, y las razones se explican distinto.
    enum Reason: Equatable {
        /// WAV o AIFF con "Mantener formato original": a ALAC, que
        /// conserva las muestras exactas.
        case uncompressedFormatKeptLossless
        /// El usuario eligió "Comprimir a MP3 de buena calidad".
        case userChoseCompressed
    }

    enum Decision: Equatable {
        /// El archivo entra a la biblioteca sin tocarlo.
        case copyAsIs
        /// A ALAC dentro de un `.m4a`, con el codificador del sistema.
        case convertToALAC(Reason)
        /// A MP3, que en la Mac necesita ffmpeg (D-038): el sistema
        /// **decodifica** MP3 pero no lo codifica -- comprobado
        /// enumerando los codificadores de AudioToolbox.
        case convertToMP3(Reason)

        var isConversion: Bool { self != .copyAsIs }
    }

    /// Los formatos PCM sin comprimir, que nunca se copian tal cual.
    static let uncompressedExtensions: Set<String> = ["wav", "aiff", "aif"]

    /// El bitrate que se promete en Ajustes. Es **medio**: el codificador
    /// usa VBR, así que ningún texto visible dice "CBR" -- prometer un
    /// bitrate constante que no se entrega es mentirle al usuario sobre
    /// su propia música.
    static let mp3BitrateKbps = 256

    static func decide(sourceExtension: String,
                       audioQuality: AppPreferences.AudioQuality) -> Decision {
        let ext = sourceExtension.lowercased()
        if audioQuality == .compressed { return .convertToMP3(.userChoseCompressed) }
        if uncompressedExtensions.contains(ext) { return .convertToALAC(.uncompressedFormatKeptLossless) }
        return .copyAsIs
    }

    /// La extensión con la que el archivo queda **en la biblioteca**.
    static func destinationExtension(sourceExtension: String,
                                     audioQuality: AppPreferences.AudioQuality) -> String {
        switch decide(sourceExtension: sourceExtension, audioQuality: audioQuality) {
        case .copyAsIs: return sourceExtension.lowercased()
        case .convertToALAC: return "m4a"
        case .convertToMP3: return "mp3"
        }
    }

    /// El aviso que Ajustes muestra bajo el interruptor de calidad, para
    /// que la promesa y el código salgan del mismo sitio.
    static func settingsNotice(audioQuality: AppPreferences.AudioQuality) -> String {
        switch audioQuality {
        case .originalLossless:
            return """
                FLAC, ALAC, M4A y MP3 se copian tal cual -- el iPod con Aura los reproduce sin \
                perder calidad. WAV y AIFF se convierten a ALAC, que también es sin pérdida: \
                sin comprimir ocupan tanto que no es práctico llevarlos.
                """
        case .compressed:
            return """
                Al importar en modo copia, la biblioteca guarda el MP3 de \(mp3BitrateKbps) kbps \
                y no el archivo sin pérdida. Tu archivo original, donde lo tengas, no se toca. \
                Cambiar esto afecta a lo que importes de ahora en adelante: lo que ya está en la \
                biblioteca se queda como está. En Mac, "Comprimido" necesita ffmpeg instalado.
                """
        }
    }
}
