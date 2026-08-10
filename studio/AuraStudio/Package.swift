// swift-tools-version: 5.9
import PackageDescription

// NOTA: el entregable real de Aura Studio es AuraStudio.xcodeproj
// (generado por XcodeGen desde project.yml -- ahi se definen los
// recursos embebidos de firmware/dist/, el Info.plist con los permisos
// de volumenes removibles, etc). Este Package.swift es un camino de
// verificacion secundario: `swift build`/`swift test` compilan y
// corren los tests sin pasar por el mecanismo de plugins de xcodebuild
// (que en este entorno sandboxed falla por falta de
// /Library/Developer/PrivateFrameworks/CoreSimulator.framework -- un
// componente de plataforma que se instala solo al abrir Xcode.app por
// primera vez, no algo especifico de este proyecto). Ver D-034 en
// DECISIONS.md. No reemplaza abrir/compilar AuraStudio.xcodeproj en un
// Mac con Xcode completo.
let package = Package(
    name: "AuraStudio",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AuraStudio",
            path: "Sources/AuraStudio"
        ),
        .testTarget(
            name: "AuraStudioTests",
            dependencies: ["AuraStudio"],
            path: "Tests/AuraStudioTests"
        ),
    ]
)
