import XCTest
@testable import AuraStudio

/// ST-227 (A7c, cierre 2): **nada decide por el texto que se muestra.**
///
/// Windows revisó sus cinco sitios donde el código comparaba contra una
/// frase en español y cuatro eran bugs reales **ya con la app en
/// español**. Estas pruebas afirman los cuatro sitios hermanos de la Mac:
/// tres no estaban afectados y hay que dejar constancia de por qué, y el
/// cuarto lo estaba y se arregló.
///
/// La forma de todas es la misma: se le da al código el dato que
/// **coincidiría** con el texto centinela y se comprueba que no se
/// confunde.
@MainActor
final class TextAsControlFlowTests: XCTestCase {
    // MARK: - (2) El motivo de no escribir etiquetas: tipado, no texto

    /// Estaba afectado. Dos sitios preguntaban
    /// `reason.hasPrefix("no se pudieron escribir")` para decidir si
    /// avisarle al usuario; traducir ese mensaje --que es justo lo que
    /// hace A7d-- apagaba las dos ramas en silencio: los errores de
    /// escritura dejarían de mostrarse y la migración dejaría de
    /// contarlos, con todo en verde.
    func testOnlyARealWriteFailureCountsAsFailureAndItIsNotDecidedByText() {
        let failure = LocalTagWriter.Result.skipped(.writeFailed("no se pudieron escribir las etiquetas de a.mp3: X"))
        XCTAssertTrue(failure.isFailure)

        for benigno: LocalTagWriter.Skip in [.formatCarriesNoTags("el formato .wav no lleva etiquetas"),
                                             .nothingToWrite("no hay ningún campo que escribir")] {
            XCTAssertFalse(LocalTagWriter.Result.skipped(benigno).isFailure,
                           "\(benigno) no es un fallo: el archivo no se tocó porque no había nada que hacer")
        }
        XCTAssertFalse(LocalTagWriter.Result.wroteFile(changed: true).isFailure)

        // **La prueba de que ya no decide el texto.** Un fallo cuyo
        // mensaje está traducido --o simplemente reescrito-- sigue
        // siendo un fallo. Con el `hasPrefix` viejo, esto era `false`.
        let traducido = LocalTagWriter.Result.skipped(.writeFailed("couldn’t write the tags of a.mp3: X"))
        XCTAssertTrue(traducido.isFailure,
                      "el aviso no puede depender de cómo esté redactado el mensaje")
        XCTAssertEqual(traducido.reason, "couldn’t write the tags of a.mp3: X")
    }

    /// El formato que no lleva etiquetas no es un fallo, pero tampoco se
    /// pierde: el motivo viaja para poder decirlo.
    func testASkippedFormatStillCarriesItsReason() {
        let r = LocalTagWriter.write(AudioTag(title: "T"), toFileAt: URL(fileURLWithPath: "/tmp/x.wav"), as: "wav")
        XCTAssertFalse(r.written)
        XCTAssertFalse(r.isFailure)
        XCTAssertEqual(r.skip, .formatCarriesNoTags("el formato .wav no lleva etiquetas (al importarlo en copia se convierte, ver AudioConversionRule)"))
    }

    // MARK: - (3) El cajón "Sin álbum" no se confunde con un álbum así

    /// No estaba afectado, y conviene que se note por qué: el centinela
    /// es `isUnknown`, un booleano calculado del DATO (la etiqueta de
    /// álbum vacía), y la clave de agrupación usa la etiqueta cruda. El
    /// texto "Sin álbum" solo se dibuja.
    ///
    /// La prueba usa un álbum de verdad llamado exactamente igual que el
    /// cajón, que es el caso que en Windows sí se rompía.
    func testARealAlbumNamedLikeTheUnknownDrawerIsNotTheDrawer() throws {
        let conNombre = item(album: LibraryGrouping.unknownAlbumTitle, artist: "Alguien", title: "A")
        let sinAlbum = item(album: "", artist: "Alguien", title: "B")

        let grupos = LibraryGrouping.albums(from: [conNombre, sinAlbum])

        XCTAssertEqual(grupos.count, 2, "el álbum real y el cajón no pueden ser el mismo grupo")
        let real = try XCTUnwrap(grupos.first { !$0.isUnknown })
        let cajon = try XCTUnwrap(grupos.first { $0.isUnknown })
        XCTAssertEqual(real.title, LibraryGrouping.unknownAlbumTitle,
                       "se sigue llamando como el usuario lo llamó")
        XCTAssertEqual(real.items.count, 1)
        XCTAssertEqual(cajon.items.count, 1)
        XCTAssertNotEqual(real.id, cajon.id, "la clave de grupo sale de la etiqueta, no del título mostrado")
    }

    /// Lo mismo para el artista: un artista llamado "Artista
    /// desconocido" es un artista más.
    func testARealArtistNamedLikeThePlaceholderIsARealArtist() {
        let llamadoAsi = item(album: "Disco", artist: LibraryGrouping.unknownArtistName, title: "A")
        let otro = item(album: "Disco", artist: "Otro", title: "B")

        let artistas = LibraryGrouping.artists(from: [llamadoAsi, otro])

        XCTAssertEqual(artistas.count, 2)
        XCTAssertTrue(artistas.contains { $0.name == LibraryGrouping.unknownArtistName })
    }

    // MARK: - (1) y (4): que sigan sin texto como control

    /// `AlbumCoverSearch` y su puntuación no comparan contra ninguna
    /// frase en español -- se afirma leyendo el fuente, que es donde
    /// volvería a colarse.
    func testCoverSearchNeverBranchesOnSpanishText() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/AuraStudio")
        let acentos = CharacterSet(charactersIn: "áéíóúÁÉÍÓÚñÑ")
        for nombre in ["Services/AlbumCoverSearch.swift", "Services/AlbumCoverScoring.swift"] {
            let texto = try String(contentsOf: sources.appendingPathComponent(nombre), encoding: .utf8)
            for (numero, linea) in texto.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let t = linea.trimmingCharacters(in: .whitespaces)
                guard !t.hasPrefix("//"), !t.hasPrefix("*") else { continue }
                let compara = t.contains("== \"") || t.contains("!= \"")
                    || t.contains(".contains(\"") || t.contains(".hasPrefix(\"")
                guard compara else { continue }
                XCTAssertNil(linea.rangeOfCharacter(from: acentos),
                             "\(nombre):\(numero + 1) vuelve a decidir por un texto en español: \(t)")
            }
        }
    }

    // MARK: - Fixture

    private func item(album: String, artist: String, title: String) -> AuraStudio.LibraryItem {
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).mp3"))
        item.metadata = TrackMetadata(title: title, artist: artist, album: album)
        return item
    }
}
