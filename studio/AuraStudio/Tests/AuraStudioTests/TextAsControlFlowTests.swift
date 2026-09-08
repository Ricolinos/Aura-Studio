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

    // MARK: - Lo que se guarda nunca es lo que se muestra

    /// ST-224 (addendum): **`localizedName` no se guarda nunca.**
    ///
    /// `MediaCategory` tiene dos nombres a propósito (D-283):
    /// `displayName` es el valor que va a `item.category` --español
    /// siempre-- y `localizedName` es lo que se dibuja. Añadir archivos
    /// desde el panel guardaba `localizedName`: con la app en alemán
    /// habría escrito "Filme" donde `LibraryStatusSummary`,
    /// `LibraryGrouping` y `LibrarySync` comparan contra "Películas", y
    /// el video habría desaparecido de Películas justo al soltarlo ahí.
    ///
    /// Hoy no mordía porque solo se ofrecen español e inglés --y el
    /// inglés está contemplado en las comparaciones-- pero habría
    /// mordido en cuanto A7d encienda los cuatro idiomas. El patrón
    /// correcto está en `SeriesView`/`MoviesView`:
    /// `Button(category.localizedName)` para mostrar,
    /// `setCategory(category.displayName)` para guardar.
    func testTheStoredCategoryNeverComesFromTheDisplayedName() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/AuraStudio")
        // Dos formas de guardarlo, y hay que distinguirlas de MOSTRARLO:
        // el mismo `localizedName` en el título de la barra lateral es
        // correcto. Por eso no vale con buscar la palabra.
        //
        //  1. pasarlo directo a algo que guarda (`setCategory(…)`,
        //     `category:` como argumento);
        //  2. asignarlo a algo que se LLAMA `category` -- que es la forma
        //     exacta que tenía el bug: un `let category: String? = { …
        //     return MediaCategory.movies.localizedName … }()`.
        var offenders: [String] = []
        let walker = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let texto = try String(contentsOf: url, encoding: .utf8)
            let lineas = texto.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var dentroDeCategory = 0
            for (numero, linea) in lineas.enumerated() {
                let t = linea.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("//") || t.hasPrefix("*") { continue }
                if t.contains("let category") || t.contains("var category") { dentroDeCategory = 14 }
                else if dentroDeCategory > 0 { dentroDeCategory -= 1 }
                guard t.contains("localizedName") else { continue }
                let guardaDirecto = t.contains("setCategory(") || t.contains("category:")
                if guardaDirecto || dentroDeCategory > 0 {
                    offenders.append("\(url.lastPathComponent):\(numero + 1)  \(t.prefix(90))")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "se guarda el nombre MOSTRADO como categoría; tiene que ser displayName (D-283):\n"
                        + offenders.joined(separator: "\n"))
    }

    /// Y que los dos nombres sean de verdad distintos conceptos: si
    /// alguien los unificara, la prueba de arriba dejaría de proteger
    /// nada sin decirlo.
    func testTheStoredNameIsSpanishWhateverTheAppLanguageIs() throws {
        for categoria in MediaCategory.videoCategories {
            XCTAssertEqual(categoria.displayName, categoria.displayNameSpanish,
                           "lo que se guarda es el español, siempre")
        }
        let english = try XCTUnwrap(
            AuraBundle.strings.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)))
        AuraBundle.overrideForTests = english
        defer { AuraBundle.overrideForTests = nil }
        XCTAssertEqual(MediaCategory.movies.displayName, "Películas",
                       "con la app en inglés, lo GUARDADO sigue siendo español")
        XCTAssertEqual(MediaCategory.movies.localizedName, "Movies",
                       "y lo MOSTRADO sigue el idioma")
    }

    // MARK: - El texto que viene de fuera del proceso

    /// ST-227 (A7c, cierre 4). Windows encontró que su proceso elevado
    /// hablaba en el idioma del sistema dentro de una pantalla en otro
    /// idioma. En la Mac el reparto es distinto y conviene dejarlo
    /// escrito:
    ///
    /// - **No hay proceso aparte que hable.** `PrivilegedExecutor` corre
    ///   `do shell script … with administrator privileges` **desde este
    ///   mismo proceso**, y el diálogo de autorización lo dibuja macOS.
    /// - **No hay ventana antes del idioma.** `AuraStudioApp.init()`
    ///   aplica `AppleLanguages` antes de que exista `body`, y el sistema
    ///   lo lee una sola vez al arrancar -- por eso cambiar de idioma
    ///   pide volver a abrir la app.
    /// - **No hay cultura por hilo.** A diferencia de .NET, el idioma es
    ///   del proceso: un `LocalizedError` construido en cualquier actor o
    ///   cola resuelve contra la misma tabla.
    ///
    /// Lo que sí viene de fuera es la SALIDA de las herramientas
    /// (`diskutil`, `dd`, `ipodpatcher`, `ditto`, `ffmpeg`), que habla el
    /// idioma del sistema. La regla es envolverla en una frase nuestra;
    /// esta prueba afirma que ninguna llega desnuda.
    func testExternalToolOutputIsAlwaysWrappedInOurOwnSentence() {
        let crudo = "Unable to find disk for disk4s2"

        let instalador = InstallerError.processFailed(exitCode: 1, output: crudo).errorDescription ?? ""
        XCTAssertTrue(instalador.contains(crudo), "la salida cruda no se pierde: es el único diagnóstico que el usuario puede reenviar")
        XCTAssertGreaterThan(instalador.count, crudo.count + 10,
                             "no puede llegar desnuda: va dentro de una frase nuestra -- «\(instalador)»")
        XCTAssertFalse(instalador.hasPrefix(crudo), "la frase nuestra va primero")
    }

    // MARK: - Lo que se le promete al usuario antes de pedirle la contraseña

    /// ST-227 (A7c, cierre 5): **la pantalla nombra TODOS los servicios
    /// que se van a pausar.**
    ///
    /// Decía "dos servicios de macOS (AMPDevicesAgent y
    /// AMPDeviceDiscoveryAgent)" y se pausan tres: falta
    /// `deviceinterfaced`. Esa pantalla existe para decir exactamente qué
    /// se va a hacer con permisos de administrador **antes** de que macOS
    /// pida la contraseña (`PermissionsView` se lo promete al usuario con
    /// todas las letras), así que nombrar dos de tres es justo lo que no
    /// puede pasar ahí.
    ///
    /// La prueba no compara contra una lista escrita a mano: recorre la
    /// que de verdad se pausa. Agregar un servicio al código y olvidarse
    /// de la pantalla vuelve a fallar acá.
    func testTheExplanationNamesEveryServiceThatWillBePaused() throws {
        let explicacion = PendingAuthorization.pauseAMPAgents().explanationBody

        XCTAssertFalse(PrivilegedExecutor.ampAgentNames.isEmpty)
        for servicio in PrivilegedExecutor.ampAgentNames {
            XCTAssertTrue(explicacion.contains(servicio),
                          "la pantalla no nombra «\(servicio)», que sí se pausa: \(explicacion)")
        }
        XCTAssertFalse(explicacion.contains("dos servicios"),
                       "un número escrito a mano vuelve a quedar viejo en cuanto cambie la lista")
    }

    /// Toda la familia del permiso de administrador dice lo mismo: dos
    /// redacciones para la misma situación se leen como dos cosas
    /// distintas. Decisión común con Windows.
    func testTheAdminPermissionFamilySpeaksWithOneVoice() {
        let delInstalador = InstallerError.authorizationCancelled.errorDescription ?? ""
        XCTAssertTrue(delInstalador.contains("permiso de administrador"),
                      "la familia usa «permiso de administrador» como raíz: \(delInstalador)")
        XCTAssertFalse(delInstalador.contains("autorización"),
                       "no se mezcla «autorización» con «permiso» en la misma familia")
    }

    /// ST-227 (A7c, cierre 6): **la explicación de los separadores nombra
    /// los que el código usa de verdad, las dos listas.**
    ///
    /// La mitad de "sí agrupan" ya salía de `collaborationSeparators`;
    /// la de "nunca agrupan" estaba escrita a mano en el texto y **ya se
    /// había desfasado**: decía «vs.» y «versus», y `neverSeparators`
    /// tiene tres entradas -- también el «vs» sin punto. Mismo defecto
    /// que Windows encontró de su lado, y el mismo arreglo: armarla desde
    /// el código.
    func testTheSeparatorExplanationNamesEverySeparatorTheCodeUses() {
        let texto = LSf("music-settings-view.separadores-que-agrupan-vs-versus-nunca",
                        Sentence.commaList(ArtistNameNormalizer.collaborationSeparators),
                        Sentence.list(ArtistNameNormalizer.neverSeparators))

        XCTAssertFalse(ArtistNameNormalizer.collaborationSeparators.isEmpty)
        XCTAssertFalse(ArtistNameNormalizer.neverSeparators.isEmpty)
        for separador in ArtistNameNormalizer.collaborationSeparators {
            XCTAssertTrue(texto.contains(separador), "la explicación no nombra «\(separador)», que sí agrupa: \(texto)")
        }
        for separador in ArtistNameNormalizer.neverSeparators {
            XCTAssertTrue(texto.contains(separador), "la explicación no nombra «\(separador)», que nunca agrupa: \(texto)")
        }
    }

    // MARK: - Fixture

    private func item(album: String, artist: String, title: String) -> AuraStudio.LibraryItem {
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).mp3"))
        item.metadata = TrackMetadata(title: title, artist: artist, album: album)
        return item
    }
}
