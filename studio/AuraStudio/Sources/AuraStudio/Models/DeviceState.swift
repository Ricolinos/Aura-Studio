import Foundation

/// Estado detectado del iPod conectado. `detecting` es el estado inicial
/// mientras `IPodMonitor` corre su primer ciclo de deteccion; `unknown`
/// es un dispositivo USB Apple presente que no se pudo clasificar (por
/// ejemplo, un iPhone conectado en vez de un iPod).
///
/// `diskModeNoFilesystem` cubre el caso en que el disco entero del iPod
/// es identificable (mismo tamano/fabricante que usa el instalador para
/// decidir "es un iPod") pero no tiene NINGUN volumen montable -- ni
/// FAT32 ni HFS+ -- asi que DiskArbitration nunca dispara el evento de
/// volumen que arma un `DiskModeInfo` normal. Pasa con un disco en
/// blanco de fabrica o, en la practica real de esta sesion, con una
/// tabla de particiones que quedo invalida por una instalacion
/// interrumpida (bootloader ya flasheado, particion de datos rota) --
/// el iPod queda mostrando "Bootloader USB mode" en pantalla, pero
/// sigue siendo un disco USB removible normal para macOS. Sin este
/// caso, Aura Studio no podia ver el dispositivo en absoluto y la unica
/// salida era reformatear a mano desde Terminal.
enum DeviceState: Equatable {
    case notConnected
    case detecting
    case diskMode(DiskModeInfo)
    case diskModeNoFilesystem(DiskCandidateInfo)
    case dfuMode(DFUModeInfo)
    case unknown
}

struct DiskModeInfo: Equatable {
    let volumeName: String
    let mountPath: String
    let bsdName: String
    let isFAT32: Bool
}

struct DFUModeInfo: Equatable {
    let productID: Int
}

extension DeviceState {
    var isReadyForInstall: Bool {
        if case .diskMode(let info) = self {
            return info.isFAT32
        }
        return false
    }

    var isDFU: Bool {
        if case .dfuMode = self { return true }
        return false
    }
}
