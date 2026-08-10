import Foundation

/// Ejecuta operaciones privilegiadas especificas y auditadas -- nunca
/// una API generica de "correr este string como root". Cada funcion
/// publica de este archivo arma internamente un script con plantillas
/// fijas y argumentos validados/escapados, jamas interpolando texto no
/// confiable directo en el shell.
///
/// Mecanismo: `do shell script "..." with administrator privileges`
/// via NSAppleScript, que muestra el dialogo nativo de autorizacion de
/// macOS (contraseña o Touch ID). NO es SMAppService.daemon (el
/// mecanismo moderno recomendado por Apple) -- ver D-042 en
/// DECISIONS.md para la razon tecnica concreta (firma ad-hoc sin Team
/// Identifier) y el plan de migracion cuando el proyecto tenga firma
/// real. macOS cachea la autorizacion unos minutos: agrupar varios
/// comandos en un solo script (una llamada a `runElevated`) es lo que
/// minimiza cuantos dialogos de contraseña ve el usuario, en vez de
/// pedir autorizacion por cada comando individual.
struct PrivilegedExecutor: Sendable {
    enum ExecutorError: Error, LocalizedError, Equatable, Sendable {
        case userCancelled
        case scriptFailed(message: String)
        case safetyAbort(reason: String)

        var errorDescription: String? {
            switch self {
            case .userCancelled:
                return "Cancelaste la autorización. Este paso no puede continuar sin ese permiso."
            case .scriptFailed(let message):
                return message
            case .safetyAbort(let reason):
                return "Aura Studio se detuvo por seguridad antes de tocar el disco: \(reason)"
            }
        }
    }

    private let log: PrivilegedOperationLog?

    init(log: PrivilegedOperationLog? = PrivilegedOperationLog()) {
        self.log = log
    }

    // MARK: - Primitiva de ejecucion elevada

    /// AppleScript real que se ejecuta: `do shell script "<script
    /// escapado>" with administrator privileges`. `-128` es el codigo
    /// de error estandar de AppleEvents para "el usuario cancelo el
    /// dialogo" -- se distingue explicitamente para que la UI pueda
    /// mostrar un mensaje distinto a una falla real.
    static func appleScriptSource(for shellScript: String) -> String {
        let escaped = shellScript
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }

    private func runElevated(_ shellScript: String, operationName: String) async throws {
        let source = Self.appleScriptSource(for: shellScript)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async { [log] in
                guard let script = NSAppleScript(source: source) else {
                    let error = ExecutorError.scriptFailed(message: "No se pudo construir el script de autorización.")
                    log?.append(operation: operationName, result: "error: no se pudo construir el script")
                    continuation.resume(throwing: error)
                    return
                }

                var errorDict: NSDictionary?
                script.executeAndReturnError(&errorDict)

                if let errorDict {
                    let number = (errorDict[NSAppleScript.errorNumber] as? Int) ?? 0
                    let message = (errorDict[NSAppleScript.errorMessage] as? String) ?? "Error desconocido"

                    if number == -128 {
                        log?.append(operation: operationName, result: "cancelado por el usuario")
                        continuation.resume(throwing: ExecutorError.userCancelled)
                    } else if message.hasPrefix("AURA_SAFETY_ABORT") {
                        log?.append(operation: operationName, result: "abortado por seguridad: \(message)")
                        continuation.resume(throwing: ExecutorError.safetyAbort(reason: message))
                    } else {
                        log?.append(operation: operationName, result: "error \(number): \(message)")
                        continuation.resume(throwing: ExecutorError.scriptFailed(message: message))
                    }
                    return
                }

                log?.append(operation: operationName, result: "ok")
                continuation.resume(returning: ())
            }
        }
    }

    // MARK: - Agentes AMP (pausa/reanuda)

    static let ampAgentNames = ["AMPDevicesAgent", "AMPDeviceDiscoveryAgent"]
    /// Red de seguridad si la app crashea con los agentes pausados: se
    /// reactivan solos despues de este tiempo aunque nadie mas lo pida.
    /// Independiente de la reactivacion explicita normal (que
    /// `InstallerViewModel` siempre dispara, exito o error).
    static let ampWatchdogTimeoutSeconds = 600

    static func pauseAMPAgentsScript() -> String {
        let names = ampAgentNames.map { "\"\($0)\"" }.joined(separator: " ")
        return """
        for name in \(names); do pkill -STOP -x "$name" 2>/dev/null || true; done
        nohup /bin/sh -c 'sleep \(ampWatchdogTimeoutSeconds); for name in \(names); do pkill -CONT -x "$name" 2>/dev/null || true; done' >/dev/null 2>&1 &
        disown
        exit 0
        """
    }

    static func resumeAMPAgentsScript() -> String {
        let names = ampAgentNames.map { "\"\($0)\"" }.joined(separator: " ")
        return "for name in \(names); do pkill -CONT -x \"$name\" 2>/dev/null || true; done; exit 0"
    }

    /// Pausa AMPDevicesAgent/AMPDeviceDiscoveryAgent, que en algunas
    /// Mac interfieren con la deteccion DFU del iPod (ver referencia a
    /// `deviceinterfaced` en D-041/hallazgos de esta sesion). Nota de
    /// honestidad: en la sesion real de flasheo de este proyecto,
    /// pausar estos agentes especificos NO fue lo que resolvio el
    /// bloqueo real que tuvimos (los causantes fueron dos bugs de
    /// firmware) -- se implementa igual porque es una interferencia
    /// documentada y real en otras configuraciones, barata y
    /// reversible, no porque este verificado que sea necesaria en
    /// todos los casos.
    func pauseAMPAgents() async throws {
        try await runElevated(Self.pauseAMPAgentsScript(), operationName: "pausar agentes AMP")
    }

    func resumeAMPAgents() async throws {
        try await runElevated(Self.resumeAMPAgentsScript(), operationName: "reanudar agentes AMP")
    }

    // MARK: - Formateo del disco del iPod

    /// Reformatea la particion de datos a FAT32 con sectores de 4096
    /// bytes (la capa USB del iPod expone el disco con bloques de
    /// 4096 bytes; un FAT32 escrito con el tamaño de sector por
    /// defecto de macOS, 512, queda en el disco pero macOS no logra
    /// montarlo de vuelta).
    ///
    /// Reverifica identidad DENTRO del script, en el mismo contexto
    /// privilegiado que va a ejecutar el borrado -- nunca confia en
    /// que el identificador que le paso el codigo Swift siga siendo
    /// valido/correcto en el momento de la ejecucion real, porque
    /// `diskN` puede cambiar entre una consulta y la siguiente si hubo
    /// reconexiones (confirmado en esta sesion: el mismo iPod aparecio
    /// como disk9 y como disk7 en reconexiones distintas). Si algo no
    /// coincide, el script sale con un mensaje `AURA_SAFETY_ABORT` que
    /// `runElevated` reconoce y traduce a `.safetyAbort`, sin ejecutar
    /// ningun comando destructivo.
    func eraseAndFormatDisk(candidate: DiskCandidateInfo, volumeName: String) async throws {
        guard candidate.matchesIPodCriteria else {
            throw ExecutorError.safetyAbort(reason: "el candidato no cumple los criterios de identificacion del iPod")
        }

        let disk = shellSafe(candidate.bsdName)
        let name = shellSafe(volumeName)
        let minSize = candidate.sizeBytes - IPodDiskIdentifier.sizeToleranceBytes
        let maxSize = candidate.sizeBytes + IPodDiskIdentifier.sizeToleranceBytes

        let script = """
        set -e
        DISK="\(disk)"
        PLIST=$(diskutil info -plist "$DISK")
        VENDOR=$(echo "$PLIST" | plutil -extract MediaName raw -o - - 2>/dev/null || echo "")
        SIZE=$(echo "$PLIST" | plutil -extract TotalSize raw -o - - 2>/dev/null || echo "0")
        REMOVABLE=$(echo "$PLIST" | plutil -extract Removable raw -o - - 2>/dev/null || echo "false")
        INTERNAL=$(echo "$PLIST" | plutil -extract Internal raw -o - - 2>/dev/null || echo "true")
        if [ "$REMOVABLE" != "true" ] && [ "$REMOVABLE" != "1" ]; then
          echo "AURA_SAFETY_ABORT: el disco ya no aparece como removible"; exit 90
        fi
        if [ "$INTERNAL" = "true" ] || [ "$INTERNAL" = "1" ]; then
          echo "AURA_SAFETY_ABORT: el disco aparece como interno"; exit 91
        fi
        if [ "$SIZE" -lt \(minSize) ] || [ "$SIZE" -gt \(maxSize) ]; then
          echo "AURA_SAFETY_ABORT: el tamaño del disco ya no coincide ($SIZE bytes)"; exit 92
        fi
        diskutil eraseDisk FAT32 "\(name)" MBR "$DISK"
        newfs_msdos -F 32 -S 4096 -v "\(name)" "/dev/r${DISK}s1"
        exit 0
        """
        try await runElevated(script, operationName: "formatear disco \(candidate.bsdName)")
    }

    /// Nunca se debe interpolar texto no confiable directo en un
    /// script de shell -- esto rechaza cualquier caracter fuera de un
    /// alfabeto seguro conocido (identificadores de disco tipo "disk7"
    /// y nombres de volumen simples), en vez de intentar escapar casos
    /// arbitrarios.
    private func shellSafe(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_- "))
        precondition(value.unicodeScalars.allSatisfy { allowed.contains($0) },
                     "valor con caracteres no seguros para interpolar en shell: \(value)")
        return value
    }
}
