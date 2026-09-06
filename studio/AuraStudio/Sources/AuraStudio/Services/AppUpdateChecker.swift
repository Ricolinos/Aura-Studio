import Foundation

/// ST-193: consulta si hay una versión más nueva de Aura Studio y
/// recuerda lo justo para no molestar.
///
/// Toda la DECISIÓN vive en `AppUpdateDecision`, que es pura. Acá está
/// lo que no se puede probar sin red ni sin reloj: cuándo se pregunta,
/// qué se recuerda y qué se le muestra al usuario.
///
/// Reglas de trato, fijadas por la sesión maestra:
/// - automático **una vez cada 24 h**, al arrancar, en segundo plano;
/// - a pedido, **ignora el intervalo** y siempre contesta algo;
/// - **sin red, el automático calla**; el manual distingue "no pude
///   preguntar" de "no hay novedades" -- son cosas distintas y decirlas
///   igual es el defecto que Windows arregló en ST-210;
/// - **un aviso por versión**: descartada una, no vuelve hasta que haya
///   otra más nueva;
/// - **nada modal, y nunca auto-actualiza**.
@MainActor
final class AppUpdateChecker: ObservableObject {
    /// La versión nueva que hay que anunciar ahora mismo. `nil` = no hay
    /// nada que decir (o el usuario ya descartó ésta).
    @Published private(set) var pendingAnnouncement: AppUpdateDecision.Available?
    /// `true` mientras una consulta está en curso -- lo usa el botón de
    /// Ajustes para su spinner.
    @Published private(set) var isChecking = false
    /// El resultado del último chequeo **a pedido**, para mostrarlo en
    /// Ajustes. El automático no lo toca: si calla, calla del todo.
    @Published private(set) var lastManualOutcome: AppUpdateDecision.Outcome?

    private let preferences: AppPreferences
    /// Inyectable para las pruebas: devuelve los Releases publicados.
    private let fetch: @Sendable () async throws -> [GitHubRelease]
    private let now: () -> Date

    static let automaticInterval: TimeInterval = 24 * 60 * 60

    /// `preferences` es opcional y no `= .shared` por el mismo motivo
    /// que en `LibraryViewModel`: un valor por omisión se evalúa en
    /// contexto nonisolated, y `.shared` está aislado al actor principal
    /// -- error en modo Swift 6, que es el que compila `xcodebuild`.
    init(preferences: AppPreferences? = nil,
         now: @escaping () -> Date = Date.init,
         fetch: (@Sendable () async throws -> [GitHubRelease])? = nil) {
        self.preferences = preferences ?? .shared
        self.now = now
        self.fetch = fetch ?? {
            try await GitHubReleaseChecker.fetchReleases(repository: AppUpdateDecision.repository)
        }
    }

    /// Al arrancar. No dice nada si no toca todavía, si no hay red, o si
    /// lo que encuentra ya fue descartado.
    func checkAutomaticallyIfDue() {
        guard shouldCheckAutomatically else { return }
        Task { await check(manual: false) }
    }

    private var shouldCheckAutomatically: Bool {
        guard let last = preferences.lastAppUpdateCheckAt else { return true }
        return now().timeIntervalSince(last) >= Self.automaticInterval
    }

    /// "Buscar actualizaciones de Aura Studio…". Siempre consulta y
    /// siempre deja un resultado en `lastManualOutcome`.
    func checkNow() async {
        await check(manual: true)
    }

    private func check(manual: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let releases: [GitHubRelease]
        do {
            releases = try await fetch()
        } catch {
            // El automático calla: preguntar y no poder no es noticia.
            if manual {
                lastManualOutcome = .couldNotCheck(error.localizedDescription)
            }
            return
        }

        // Solo se anota la fecha cuando la consulta SALIÓ BIEN: si no,
        // el próximo arranque vuelve a intentarlo en vez de esperar 24 h
        // por una pregunta que nunca llegó a hacerse.
        preferences.lastAppUpdateCheckAt = now()

        let available = AppUpdateDecision.decide(
            installedVersion: AppVersion.current,
            releases: releases,
            includePrereleases: preferences.appUpdatesIncludePrereleases)

        if manual {
            lastManualOutcome = available.map(AppUpdateDecision.Outcome.available) ?? .upToDate
        }

        guard let available else {
            pendingAnnouncement = nil
            return
        }
        // A pedido se muestra siempre; automáticamente, solo si no se
        // descartó esta misma versión.
        if manual || preferences.dismissedAppUpdateTag != available.tag {
            pendingAnnouncement = available
        }
    }

    /// "No me lo recuerdes": esta versión no vuelve a anunciarse sola.
    /// La siguiente sí, porque el tag será otro.
    func dismissAnnouncement() {
        if let tag = pendingAnnouncement?.tag {
            preferences.dismissedAppUpdateTag = tag
        }
        pendingAnnouncement = nil
    }
}
