import Foundation

/// Qué tan seguro está el detector de que un grupo son "lo mismo".
enum SimilarityConfidence: Int, Comparable, CaseIterable, Identifiable {
    /// Metadata que solo difiere en formato/números de pista, misma
    /// duración (±2 s) o mismo tamaño exacto -- casi seguro duplicados.
    case duplicate = 3
    /// Título y artista equivalentes tras normalizar; duración cercana
    /// o desconocida.
    case probable = 2
    /// Parecidos, pero con una diferencia que puede ser legítima (una
    /// versión en vivo, un remix, un artista escrito muy distinto...).
    case possible = 1

    var id: Int { rawValue }
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .duplicate: return "Duplicado"
        case .probable: return "Probable"
        case .possible: return "Posible"
        }
    }

    var detail: String {
        switch self {
        case .duplicate: return "Casi seguro es el mismo archivo dos veces."
        case .probable: return "Probablemente es la misma canción con la metadata escrita distinto."
        case .possible: return "Se parecen, pero podrían ser versiones distintas. Conviene revisar."
        }
    }
}

/// Un cambio de metadata que el detector sugiere para dejar el grupo
/// consistente (por ejemplo, unificar "SodaStereo"/"Soda-Stereo" al
/// nombre que más se usa en la biblioteca). Nunca se aplica solo: la
/// hoja de revisión lo muestra y el usuario decide.
struct SimilarityProposedEdit: Equatable, Identifiable {
    enum Field: String { case title, artist, album }
    let itemID: UUID
    let field: Field
    let currentValue: String
    let proposedValue: String

    var id: String { "\(itemID.uuidString)/\(field.rawValue)" }

    var fieldTitle: String {
        switch field {
        case .title: return "Título"
        case .artist: return "Artista"
        case .album: return "Álbum"
        }
    }
}

/// Un conjunto de elementos sospechosamente parecidos, con la
/// explicación de POR QUÉ el detector los juntó, cuál sugiere conservar
/// y qué ediciones propone para el resto.
struct SimilarItemsGroup: Identifiable, Equatable {
    /// Estable entre corridas mientras no cambien los miembros -- es lo
    /// que se guarda en `AppPreferences.ignoredSimilarGroups`.
    let id: String
    let kind: LibraryItemKind
    /// Ordenados con el sugerido a conservar primero.
    let items: [LibraryItem]
    let confidence: SimilarityConfidence
    let reasons: [String]
    let suggestedKeepID: UUID
    let suggestion: String
    let proposedEdits: [SimilarityProposedEdit]

    static func key(for ids: [UUID]) -> String {
        ids.map(\.uuidString).sorted().joined(separator: "+")
    }
}

/// Detector de elementos "sospechosamente similares" (ST-063, encargo
/// del dueño, 2026-08-23): "01 Amor"/"SodaStereo" contra "Amor"/
/// "Soda-Stereo" tiene que aparecer como un posible duplicado, con la
/// sugerencia de cuál conservar. Todo es puro y sincrónico sobre
/// `[LibraryItem]`; la única lectura de disco es el tamaño de archivo,
/// que se hace una sola vez por elemento al arrancar.
///
/// Nunca borra ni edita nada: devuelve grupos con evidencia
/// (`reasons`), una confianza y una propuesta -- la hoja de revisión
/// (`SimilarItemsView`) es la que ejecuta lo que el usuario elija.
enum SimilarItemsDetector {
    // MARK: - Normalización

    /// Palabras que distinguen versiones legítimas de una misma
    /// canción -- si solo una de las dos las tiene, el grupo baja a
    /// "posible" en vez de "probable".
    static let versionQualifiers: Set<String> = [
        "live", "envivo", "vivo", "remix", "mix", "acoustic", "acustico", "acustica", "unplugged",
        "demo", "instrumental", "karaoke", "radioedit", "edit", "version", "cover", "remaster",
        "remastered", "remasterizado", "remasterizada", "extended", "single", "mono", "stereo",
        "bonus", "outtake", "alternate", "alt", "reprise", "intro", "outro", "feat", "ft",
    ]

    /// Sufijos que agregan Finder/macOS al duplicar un archivo.
    private static let copySuffixPattern = try! NSRegularExpression(
        pattern: #"(\s*(copia|copy)(\s*\d+)?|\s*\(\d+\)|[\s_-]+\d{1,2})$"#, options: [.caseInsensitive])
    private static let leadingTrackNumberPattern = try! NSRegularExpression(
        pattern: #"^\s*(\d{1,2}[\s._-]+)?\d{1,3}\s*([.\-_)]\s*|\s+)"#)
    private static let bracketPattern = try! NSRegularExpression(pattern: #"[\(\[\{][^\)\]\}]*[\)\]\}]"#)
    private static let yearSuffixPattern = try! NSRegularExpression(pattern: #"\s*[\(\[]?(19|20)\d{2}[\)\]]?\s*$"#)

    /// Minúsculas, sin acentos, solo letras y números.
    static func alnum(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// Quita "01 ", "1. ", "01 - ", "1-01 " al frente de un título.
    static func stripLeadingTrackNumber(_ title: String) -> String {
        let range = NSRange(title.startIndex..., in: title)
        let stripped = leadingTrackNumberPattern.stringByReplacingMatches(in: title, range: range, withTemplate: "")
        // Si el título ERA solo un número ("7", "99"), no lo vacíes.
        return stripped.trimmingCharacters(in: .whitespaces).isEmpty ? title : stripped
    }

    /// Título comparable: sin número de pista, sin nada entre
    /// paréntesis/corchetes, sin acentos ni puntuación. Devuelve también
    /// los calificadores de versión que se encontraron (en el paréntesis
    /// o sueltos en el título) para saber si es "otra versión".
    static func normalizedTitle(_ raw: String) -> (core: String, qualifiers: Set<String>) {
        var text = stripLeadingTrackNumber(raw)
        var qualifiers = Set<String>()
        let range = NSRange(text.startIndex..., in: text)
        for match in bracketPattern.matches(in: text, range: range).reversed() {
            if let r = Range(match.range, in: text) {
                let inside = String(text[r]).dropFirst().dropLast()
                for word in tokens(String(inside)) where versionQualifiers.contains(word) { qualifiers.insert(word) }
                text.removeSubrange(r)
            }
        }
        // "Amor - Live", "Amor (live)" ya cubierto; también sueltos al final.
        var words = tokens(text)
        while let last = words.last, versionQualifiers.contains(last), words.count > 1 {
            qualifiers.insert(last)
            words.removeLast()
        }
        return (words.joined(), qualifiers)
    }

    static func tokens(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Nombre de archivo comparable para fotos/videos: sin extensión,
    /// sin " copia"/"(1)"/"-1", sin año final.
    static func normalizedStem(_ url: URL) -> String {
        var stem = url.deletingPathExtension().lastPathComponent
        var range = NSRange(stem.startIndex..., in: stem)
        stem = copySuffixPattern.stringByReplacingMatches(in: stem, range: range, withTemplate: "")
        range = NSRange(stem.startIndex..., in: stem)
        stem = yearSuffixPattern.stringByReplacingMatches(in: stem, range: range, withTemplate: "")
        return alnum(stem)
    }

    /// 1.0 = idénticas, 0.0 = nada que ver (Levenshtein normalizada).
    static func similarity(_ a: String, _ b: String) -> Double {
        similarity(Array(a.unicodeScalars), Array(b.unicodeScalars))
    }

    static func similarity(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar]) -> Double {
        if a == b { return 1 }
        if a.isEmpty || b.isEmpty { return 0 }
        // La diferencia de largo ya acota la distancia por debajo: si
        // solo por eso quedan lejos, no vale la pena el DP completo.
        let la = a.count, lb = b.count
        if Double(abs(la - lb)) / Double(max(la, lb)) > 0.5 { return 0 }
        let distance = levenshtein(a, b)
        return 1 - Double(distance) / Double(max(la, lb))
    }

    static func levenshtein(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    // MARK: - Huella por elemento

    struct Fingerprint {
        let item: LibraryItem
        let rawTitle: String
        let titleCore: String
        let qualifiers: Set<String>
        let artist: String
        let album: String
        let stem: String
        /// Escalares precomputados para Levenshtein (se comparan miles de pares).
        let titleScalars: [Unicode.Scalar]
        let artistScalars: [Unicode.Scalar]
        let albumScalars: [Unicode.Scalar]
        let stemScalars: [Unicode.Scalar]
        let duration: Double?
        let fileSize: Int64
        let ext: String
        let episodeKey: String?

        init(item: LibraryItem, fileSize: Int64) {
            self.item = item
            let title = item.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            rawTitle = (title?.isEmpty == false ? title : nil) ?? item.sourceURL.deletingPathExtension().lastPathComponent
            let normalized = SimilarItemsDetector.normalizedTitle(rawTitle)
            titleCore = normalized.core
            qualifiers = normalized.qualifiers
            artist = SimilarItemsDetector.alnum(item.metadata?.artist ?? "")
            album = SimilarItemsDetector.alnum(item.metadata?.album ?? "")
            stem = SimilarItemsDetector.normalizedStem(item.sourceURL)
            titleScalars = Array(titleCore.unicodeScalars)
            artistScalars = Array(artist.unicodeScalars)
            albumScalars = Array(album.unicodeScalars)
            stemScalars = Array(stem.unicodeScalars)
            duration = (item.metadata?.durationSeconds).flatMap { $0 > 0 ? $0 : nil }
            self.fileSize = fileSize
            ext = item.sourceURL.pathExtension.lowercased()
            if let series = item.seriesName, !series.isEmpty, let season = item.season, let episode = item.episode {
                episodeKey = "\(SimilarItemsDetector.alnum(series))/\(season)/\(episode)"
            } else {
                episodeKey = nil
            }
        }
    }

    static func fileSize(of url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    // MARK: - Detección

    private struct PairVerdict {
        let confidence: SimilarityConfidence
        let reasons: [String]
    }

    /// Corre el detector sobre toda la biblioteca. `ignoredGroupIDs`
    /// son grupos que el usuario ya dijo "no son lo mismo".
    static func detect(in items: [LibraryItem], ignoredGroupIDs: Set<String> = [],
                       fileSize: (URL) -> Int64 = fileSize(of:)) -> [SimilarItemsGroup] {
        var groups: [SimilarItemsGroup] = []
        for kind in [LibraryItemKind.music, .video, .photo] {
            let prints = items.filter { $0.kind == kind }.map { Fingerprint(item: $0, fileSize: fileSize($0.sourceURL)) }
            groups += detect(prints: prints, kind: kind, allItems: items)
        }
        return groups
            .filter { !ignoredGroupIDs.contains($0.id) }
            .sorted { a, b in
                if a.confidence != b.confidence { return a.confidence > b.confidence }
                return a.items[0].sourceURL.lastPathComponent.localizedStandardCompare(b.items[0].sourceURL.lastPathComponent) == .orderedAscending
            }
    }

    private static func detect(prints: [Fingerprint], kind: LibraryItemKind, allItems: [LibraryItem]) -> [SimilarItemsGroup] {
        guard prints.count > 1 else { return [] }
        // Bloqueo por las 3 primeras letras del título (y del nombre de
        // archivo) para no comparar todos contra todos; un título con
        // una letra cambiada al frente se pierde, a cambio de que una
        // biblioteca de miles de canciones se procese al instante.
        // Además, mismo tamaño exacto de archivo forma su propio bloque
        // (duplicados byte a byte con nombres distintos).
        var blocks: [String: [Int]] = [:]
        for (index, print) in prints.enumerated() {
            let key = String((kind == .photo ? print.stem : print.titleCore).prefix(3))
            blocks[key, default: []].append(index)
            if kind != .photo, !print.stem.isEmpty {
                blocks["f:" + String(print.stem.prefix(3)), default: []].append(index)
            }
            if print.fileSize > 0 {
                blocks["s:\(print.fileSize)", default: []].append(index)
            }
        }
        var parent = Array(0..<prints.count)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
            return x
        }
        let n = prints.count
        var pairVerdicts: [Int: PairVerdict] = [:]
        var compared = Set<Int>()
        var involved = Set<Int>()
        for indices in blocks.values where indices.count > 1 {
            for i in 0..<indices.count {
                for j in (i + 1)..<indices.count {
                    let a = min(indices[i], indices[j]), b = max(indices[i], indices[j])
                    let pairKey = a * n + b
                    if !compared.insert(pairKey).inserted { continue }
                    guard let verdict = compare(prints[a], prints[b], kind: kind) else { continue }
                    pairVerdicts[pairKey] = verdict
                    involved.insert(a)
                    involved.insert(b)
                    let ra = find(a), rb = find(b)
                    if ra != rb { parent[ra] = rb }
                }
            }
        }
        var clusters: [Int: [Int]] = [:]
        for index in involved.sorted() {
            clusters[find(index), default: []].append(index)
        }
        return clusters.values.compactMap { members -> SimilarItemsGroup? in
            guard members.count > 1 else { return nil }
            var confidence = SimilarityConfidence.possible
            var reasons: [String] = []
            for (pair, verdict) in pairVerdicts where members.contains(pair / n) && members.contains(pair % n) {
                confidence = max(confidence, verdict.confidence)
                for reason in verdict.reasons where !reasons.contains(reason) { reasons.append(reason) }
            }
            let memberPrints = members.map { prints[$0] }
            return buildGroup(memberPrints, kind: kind, confidence: confidence, reasons: reasons, allItems: allItems)
        }
    }

    // MARK: - Comparación de a pares

    private static func durationMatch(_ a: Double?, _ b: Double?) -> Double? {
        guard let a, let b else { return nil }
        let delta = abs(a - b)
        if delta <= 2 { return 1 }
        if delta <= 5 { return 0.7 }
        if delta <= 15 { return 0.3 }
        return 0
    }

    private static func compare(_ a: Fingerprint, _ b: Fingerprint, kind: LibraryItemKind) -> PairVerdict? {
        switch kind {
        case .music: return compareMusic(a, b)
        case .video: return compareVideo(a, b)
        case .photo: return comparePhoto(a, b)
        case .unsupported: return nil
        }
    }

    private static func compareMusic(_ a: Fingerprint, _ b: Fingerprint) -> PairVerdict? {
        var reasons: [String] = []
        let sameFileSize = a.fileSize > 0 && a.fileSize == b.fileSize
        // Descartes rápidos (antes de Levenshtein): duraciones lejanas,
        // o títulos distintos sin ser el mismo archivo.
        let duration = durationMatch(a.duration, b.duration)
        if let duration, duration == 0, !sameFileSize { return nil }
        let titleSim = similarity(a.titleScalars, b.titleScalars)
        if titleSim < 0.8 && !(sameFileSize && titleSim >= 0.6) { return nil }
        let artistSim: Double
        if a.artist.isEmpty && b.artist.isEmpty { artistSim = 0.6 }
        else if a.artist.isEmpty || b.artist.isEmpty { artistSim = 0.65 }
        else { artistSim = similarity(a.artistScalars, b.artistScalars) }
        let albumSim = (a.album.isEmpty || b.album.isEmpty) ? 0.5 : similarity(a.albumScalars, b.albumScalars)
        if artistSim < 0.6 && albumSim < 0.85 && !sameFileSize { return nil }

        if titleSim >= 0.999 {
            if a.rawTitle != b.rawTitle {
                reasons.append("Mismo título sin contar el número de pista o los paréntesis: «\(a.rawTitle)» / «\(b.rawTitle)»")
            } else {
                reasons.append("Mismo título: «\(a.rawTitle)»")
            }
        } else if titleSim >= 0.8 {
            reasons.append("Título casi igual: «\(a.rawTitle)» / «\(b.rawTitle)»")
        }
        if !a.artist.isEmpty, !b.artist.isEmpty {
            if a.artist == b.artist {
                if (a.item.metadata?.artist ?? "") != (b.item.metadata?.artist ?? "") {
                    reasons.append("Artista escrito distinto: «\(a.item.metadata?.artist ?? "")» / «\(b.item.metadata?.artist ?? "")»")
                }
            } else if artistSim >= 0.6 {
                reasons.append("Artista parecido: «\(a.item.metadata?.artist ?? "")» / «\(b.item.metadata?.artist ?? "")»")
            }
        } else if a.artist.isEmpty || b.artist.isEmpty {
            reasons.append("A uno le falta el artista")
        }
        if let duration {
            if duration == 1 { reasons.append("Misma duración (\(clock(a.duration)))") }
            else if duration >= 0.3 { reasons.append("Duración parecida (\(clock(a.duration)) / \(clock(b.duration)))") }
        }
        if sameFileSize { reasons.append("Mismo tamaño exacto de archivo (\(ByteCountFormatter.string(fromByteCount: a.fileSize, countStyle: .file)))") }
        if a.ext != b.ext { reasons.append("Formatos distintos: \(a.ext.uppercased()) / \(b.ext.uppercased())") }
        let qualifierDiff = a.qualifiers.symmetricDifference(b.qualifiers)
        if !qualifierDiff.isEmpty {
            reasons.append("Una parece otra versión (\(qualifierDiff.sorted().joined(separator: ", ")))")
        }

        let confidence: SimilarityConfidence
        if sameFileSize && titleSim >= 0.8 {
            confidence = .duplicate
        } else if titleSim >= 0.92 && artistSim >= 0.85 && qualifierDiff.isEmpty {
            if duration == 1 { confidence = .duplicate }
            else if duration == nil || duration! >= 0.7 { confidence = .probable }
            else { confidence = .possible }
        } else if titleSim >= 0.8 && (artistSim >= 0.6 || albumSim >= 0.85) {
            if let duration, duration < 0.3 { return nil }
            confidence = .possible
        } else {
            return nil
        }
        return PairVerdict(confidence: confidence, reasons: reasons)
    }

    private static func compareVideo(_ a: Fingerprint, _ b: Fingerprint) -> PairVerdict? {
        var reasons: [String] = []
        let sameFileSize = a.fileSize > 0 && a.fileSize == b.fileSize
        let duration = durationMatch(a.duration, b.duration)
        if let ea = a.episodeKey, let eb = b.episodeKey, ea == eb {
            reasons.append("Mismo episodio: \(a.item.seriesName ?? "") T\(a.item.season ?? 0)E\(a.item.episode ?? 0)")
            if let duration, duration == 1 { reasons.append("Misma duración (\(clock(a.duration)))") }
            if sameFileSize { reasons.append("Mismo tamaño exacto de archivo") }
            return PairVerdict(confidence: (duration == 1 || sameFileSize) ? .duplicate : .probable, reasons: reasons)
        }
        let titleSim = max(similarity(a.titleScalars, b.titleScalars), similarity(a.stemScalars, b.stemScalars))
        if titleSim < 0.85 && !sameFileSize { return nil }
        if let duration, duration == 0, !sameFileSize { return nil }
        reasons.append(titleSim >= 0.999 ? "Mismo título: «\(a.rawTitle)»" : "Título casi igual: «\(a.rawTitle)» / «\(b.rawTitle)»")
        if let duration {
            if duration == 1 { reasons.append("Misma duración (\(clock(a.duration)))") }
            else if duration >= 0.3 { reasons.append("Duración parecida (\(clock(a.duration)) / \(clock(b.duration)))") }
        }
        if sameFileSize { reasons.append("Mismo tamaño exacto de archivo") }
        if a.ext != b.ext { reasons.append("Formatos distintos: \(a.ext.uppercased()) / \(b.ext.uppercased())") }
        if (a.item.category ?? "") != (b.item.category ?? "") {
            reasons.append("Categorías distintas: \(a.item.category ?? "sin categoría") / \(b.item.category ?? "sin categoría")")
        }
        let confidence: SimilarityConfidence
        if sameFileSize || (titleSim >= 0.95 && duration == 1) { confidence = .duplicate }
        else if titleSim >= 0.92 && (duration == nil || duration! >= 0.7) { confidence = .probable }
        else { confidence = .possible }
        return PairVerdict(confidence: confidence, reasons: reasons)
    }

    private static func comparePhoto(_ a: Fingerprint, _ b: Fingerprint) -> PairVerdict? {
        var reasons: [String] = []
        let sameFileSize = a.fileSize > 0 && a.fileSize == b.fileSize
        let stemSim = similarity(a.stemScalars, b.stemScalars)
        // Fotos: el nombre tiene que ser EQUIVALENTE (IMG_0001 vs
        // "IMG_0001 copia"), no solo parecido -- IMG_0001/IMG_0002 son
        // tomas consecutivas, no duplicados. Nombre distinto solo cuenta
        // con el mismo tamaño exacto.
        guard stemSim >= 0.999 || sameFileSize else { return nil }
        if stemSim >= 0.999 {
            reasons.append("Mismo nombre de archivo sin contar «copia»/«(1)»: \(a.item.sourceURL.lastPathComponent) / \(b.item.sourceURL.lastPathComponent)")
        } else if stemSim >= 0.85 {
            reasons.append("Nombre de archivo casi igual: \(a.item.sourceURL.lastPathComponent) / \(b.item.sourceURL.lastPathComponent)")
        }
        if sameFileSize {
            reasons.append("Mismo tamaño exacto de archivo (\(ByteCountFormatter.string(fromByteCount: a.fileSize, countStyle: .file)))")
        }
        if a.ext != b.ext { reasons.append("Formatos distintos: \(a.ext.uppercased()) / \(b.ext.uppercased())") }
        let confidence: SimilarityConfidence
        if sameFileSize && stemSim >= 0.85 { confidence = .duplicate }
        else if stemSim >= 0.999 { confidence = .probable }
        else { confidence = .possible }
        return PairVerdict(confidence: confidence, reasons: reasons)
    }

    private static func clock(_ seconds: Double?) -> String {
        guard let seconds else { return "--" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Sugerencia

    private static let losslessExtensions: Set<String> = ["flac", "wav", "aiff", "aif"]

    /// Puntaje de "cuál conservar": más metadata, mejor formato, más
    /// grande, corregido a mano, con carátula/letra. Público para que
    /// las pruebas puedan afirmar el criterio.
    static func keepScore(_ item: LibraryItem, fileSize: Int64, largestSize: Int64) -> Double {
        var score = 0.0
        let ext = item.sourceURL.pathExtension.lowercased()
        let meta = item.metadata
        if item.kind == .music && losslessExtensions.contains(ext) { score += 3 }
        if fileSize > 0 && fileSize == largestSize { score += 1 }
        if meta?.hasCover == true { score += 1 }
        if meta?.syncedLyrics != nil { score += 1 }
        if item.metadataEditedByUser { score += 2 }
        if meta?.trackNumber != nil { score += 0.5 }
        if (meta?.album ?? "").isEmpty == false { score += 0.5 }
        if (meta?.artist ?? "").isEmpty == false { score += 0.5 }
        if (meta?.year ?? "").isEmpty == false { score += 0.25 }
        if (meta?.genre ?? "").isEmpty == false { score += 0.25 }
        if meta?.isFavorite == true { score += 1 }
        if let rating = meta?.rating, rating > 0 { score += 0.5 }
        if let title = meta?.title, stripLeadingTrackNumber(title) == title { score += 0.5 }
        if item.status == .ready { score += 0.5 }
        return score
    }

    /// Nombre "canónico" de un artista/álbum: la forma en que más
    /// veces está escrito en toda la biblioteca entre las que
    /// normalizan igual; a igualdad, la que tiene más caracteres
    /// (espacios y acentos incluidos, "Soda Stereo" antes que
    /// "SodaStereo").
    static func canonicalSpelling(of value: String, in allItems: [LibraryItem], field: SimilarityProposedEdit.Field) -> String {
        let key = alnum(value)
        guard !key.isEmpty else { return value }
        var counts: [String: Int] = [:]
        for item in allItems {
            let candidate: String?
            switch field {
            case .artist: candidate = item.metadata?.artist
            case .album: candidate = item.metadata?.album
            case .title: candidate = nil
            }
            guard let candidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty,
                  alnum(candidate) == key else { continue }
            counts[candidate, default: 0] += 1
        }
        guard !counts.isEmpty else { return value }
        return counts.max { a, b in
            if a.value != b.value { return a.value < b.value }
            if a.key.count != b.key.count { return a.key.count < b.key.count }
            return a.key > b.key
        }!.key
    }

    private static func buildGroup(_ prints: [Fingerprint], kind: LibraryItemKind, confidence: SimilarityConfidence,
                                   reasons: [String], allItems: [LibraryItem]) -> SimilarItemsGroup {
        let largest = prints.map(\.fileSize).max() ?? 0
        let ordered = prints.sorted { a, b in
            let sa = keepScore(a.item, fileSize: a.fileSize, largestSize: largest)
            let sb = keepScore(b.item, fileSize: b.fileSize, largestSize: largest)
            if sa != sb { return sa > sb }
            return (a.item.addedAt ?? .distantFuture) < (b.item.addedAt ?? .distantFuture)
        }
        let keep = ordered[0]
        var edits: [SimilarityProposedEdit] = []
        var suggestion: String

        let keepDescription: String = {
            var bits: [String] = [keep.ext.uppercased()]
            if kind == .music && losslessExtensions.contains(keep.ext) { bits[0] += " sin pérdida" }
            if keep.item.metadata?.hasCover == true { bits.append(kind == .music ? "con carátula" : "con póster") }
            if keep.item.metadata?.syncedLyrics != nil { bits.append("con letra") }
            if keep.item.metadataEditedByUser { bits.append("corregido a mano") }
            if keep.fileSize > 0 && keep.fileSize == largest && prints.contains(where: { $0.fileSize != largest }) { bits.append("el más grande") }
            return bits.joined(separator: ", ")
        }()

        switch confidence {
        case .duplicate:
            suggestion = "Parecen el mismo archivo repetido. Sugerencia: conservar «\(keep.rawTitle)» (\(keepDescription)) y eliminar el resto."
        case .probable:
            suggestion = "Probablemente es el mismo elemento con la metadata escrita distinto. Sugerencia: conservar «\(keep.rawTitle)» (\(keepDescription)) y eliminar el resto, o unificar la metadata si prefieres quedarte con ambos."
        case .possible:
            suggestion = "Podrían ser versiones distintas. Sugerencia: revisar antes de eliminar. Si resultan ser la misma, conservar «\(keep.rawTitle)» (\(keepDescription))."
        }

        if kind == .music {
            // Unificar artista/álbum al nombre canónico de la biblioteca.
            let artistValues = prints.compactMap { $0.item.metadata?.artist?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if Set(artistValues).count > 1 {
                let canonical = canonicalSpelling(of: keep.item.metadata?.artist ?? artistValues[0], in: allItems, field: .artist)
                for print in prints {
                    if let current = print.item.metadata?.artist, !current.isEmpty, current != canonical {
                        edits.append(SimilarityProposedEdit(itemID: print.item.id, field: .artist, currentValue: current, proposedValue: canonical))
                    }
                }
                suggestion += " El artista que más se usa en tu biblioteca es «\(canonical)»."
            }
            let albumValues = prints.compactMap { $0.item.metadata?.album?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if Set(albumValues).count > 1, Set(albumValues.map(alnum)).count == 1 {
                let canonical = canonicalSpelling(of: keep.item.metadata?.album ?? albumValues[0], in: allItems, field: .album)
                for print in prints {
                    if let current = print.item.metadata?.album, !current.isEmpty, current != canonical {
                        edits.append(SimilarityProposedEdit(itemID: print.item.id, field: .album, currentValue: current, proposedValue: canonical))
                    }
                }
            }
            // Títulos con número de pista al frente: proponer el limpio.
            for print in prints {
                if let title = print.item.metadata?.title {
                    let clean = stripLeadingTrackNumber(title).trimmingCharacters(in: .whitespaces)
                    if clean != title, !clean.isEmpty {
                        edits.append(SimilarityProposedEdit(itemID: print.item.id, field: .title, currentValue: title, proposedValue: clean))
                    }
                }
            }
        }

        return SimilarItemsGroup(id: SimilarItemsGroup.key(for: prints.map(\.item.id)),
                                 kind: kind,
                                 items: ordered.map(\.item),
                                 confidence: confidence,
                                 reasons: reasons,
                                 suggestedKeepID: keep.item.id,
                                 suggestion: suggestion,
                                 proposedEdits: edits)
    }
}
