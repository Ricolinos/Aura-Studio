import Foundation

/// Estado detectado del iPod conectado. `detecting` es el estado inicial
/// mientras `IPodMonitor` corre su primer ciclo de deteccion; `unknown`
/// es un dispositivo USB Apple presente que no se pudo clasificar (por
/// ejemplo, un iPhone conectado en vez de un iPod).
enum DeviceState: Equatable {
    case notConnected
    case detecting
    case diskMode(DiskModeInfo)
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
