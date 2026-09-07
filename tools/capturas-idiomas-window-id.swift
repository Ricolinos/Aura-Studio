// Compañero de tools/capturas-idiomas.sh. `screencapture -l <id>` pide
// un CGWindowID -- System Events (AppleScript) no lo expone en esta
// versión de macOS (ni `id of window`, comprobado, ni `AXWindowNumber`,
// tampoco expuesto): la única lista de atributos real del window es
// AXFocused/AXFullScreen/AXTitle/AXFrame/AXPosition/AXChildren/... sin
// nada que sea un CGWindowID. `CGWindowListCopyWindowInfo` (Quartz) sí
// lo tiene, y no depende de PyObjC (que no está instalado acá) -- un
// Swift de una pantalla, mismo lenguaje que el resto del repo.
import CoreGraphics
import Foundation

guard CommandLine.arguments.count > 1, let pid = Int32(CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("uso: capturas-idiomas-window-id.swift <pid>\n".utf8))
    exit(1)
}

guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}

// `layer == 0` es la ventana de aplicación normal -- descarta paneles/
// tooltips/otras capas que CGWindowListCopyWindowInfo también reporta
// para el mismo proceso.
for info in list {
    guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32, ownerPID == pid else { continue }
    guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
    if let windowID = info[kCGWindowNumber as String] as? Int {
        print(windowID)
        exit(0)
    }
}
exit(1)
