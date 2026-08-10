import XCTest
@testable import AuraStudio

/// Tests de la logica pura de armado de scripts -- deliberadamente NO
/// ejecutan `runElevated` de verdad (eso mostraria el dialogo real de
/// autorizacion de macOS, no es apto para correr en CI/tests
/// automaticos). Lo que se puede y debe testear sin tocar el sistema:
/// que los scripts generados contienen exactamente los comandos
/// esperados, con los argumentos bien escapados.
final class PrivilegedExecutorTests: XCTestCase {
    func testPauseAMPAgentsScriptTargetsBothAgentsByExactName() {
        let script = PrivilegedExecutor.pauseAMPAgentsScript()

        // Los nombres se recorren con un loop de shell (`for name in
        // "A" "B"; do pkill -STOP -x "$name"`), asi que el nombre del
        // agente no queda pegado al comando -- se verifica que ambos
        // nombres esten en la lista del loop, y que el comando use
        // `-x` (match exacto de nombre de proceso, no substring).
        XCTAssertTrue(script.contains("\"AMPDevicesAgent\""))
        XCTAssertTrue(script.contains("\"AMPDeviceDiscoveryAgent\""))
        XCTAssertTrue(script.contains("pkill -STOP -x \"$name\""))
    }

    func testPauseAMPAgentsScriptIncludesWatchdogResume() {
        let script = PrivilegedExecutor.pauseAMPAgentsScript()

        // El watchdog debe reactivar los MISMOS dos agentes, en
        // segundo plano, como red de seguridad ante un crash de la app.
        XCTAssertTrue(script.contains("sleep \(PrivilegedExecutor.ampWatchdogTimeoutSeconds)"))
        XCTAssertTrue(script.contains("pkill -CONT -x \"$name\""))
        XCTAssertTrue(script.contains("&"), "el watchdog debe correr en segundo plano, no bloquear")
    }

    func testResumeAMPAgentsScriptTargetsBothAgents() {
        let script = PrivilegedExecutor.resumeAMPAgentsScript()

        XCTAssertTrue(script.contains("\"AMPDevicesAgent\""))
        XCTAssertTrue(script.contains("\"AMPDeviceDiscoveryAgent\""))
        XCTAssertTrue(script.contains("pkill -CONT -x \"$name\""))
        XCTAssertFalse(script.contains("-STOP"), "resumir nunca debe pausar nada")
    }

    func testAppleScriptSourceEscapesDoubleQuotes() {
        let shellScript = #"echo "hola""#
        let source = PrivilegedExecutor.appleScriptSource(for: shellScript)

        XCTAssertTrue(source.contains(#"\"hola\""#))
        XCTAssertTrue(source.contains("with administrator privileges"))
    }

    func testAppleScriptSourceEscapesBackslashes() {
        let shellScript = #"echo "a\b""#
        let source = PrivilegedExecutor.appleScriptSource(for: shellScript)

        // El backslash original debe quedar escapado (\\) ademas de
        // las comillas, para que AppleScript no lo interprete como
        // inicio de una secuencia de escape propia.
        XCTAssertTrue(source.contains(#"a\\b"#))
    }

    func testAppleScriptSourceAlwaysRequestsAdministratorPrivileges() {
        let source = PrivilegedExecutor.appleScriptSource(for: "true")
        XCTAssertTrue(source.hasPrefix("do shell script \""))
        XCTAssertTrue(source.hasSuffix("with administrator privileges"))
    }
}
