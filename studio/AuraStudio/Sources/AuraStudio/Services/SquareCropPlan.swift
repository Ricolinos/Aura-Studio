import Foundation

/// Dónde recortar una imagen para dejarla cuadrada, y de qué lado sale.
/// Es aritmética pura, separada del codificador para poder verificarla
/// sin ImageIO -- el equivalente exacto de
/// `AuraStudio.Core/Library/SquareCropPlan.cs` en el port de Windows:
/// mismos casos de prueba, mismos números.
///
/// "Cuadrada" significa siempre **rellenar y recortar al centro** (fill +
/// center-crop): se conserva el cuadrado central del lado corto y se tira
/// la mitad sobrante del lado largo, repartida en los dos extremos. Nunca
/// se estira ni se agregan bandas -- CONTRATO-firmware-studio.md §A.1 de
/// la ronda de carátulas cuadradas (contrato v18) y §D.5, donde el
/// firmware describe la misma primitiva para su caché maestra.
struct SquareCropPlan: Equatable {
    /// Medidas de la imagen de origen **ya orientadas** (una foto vertical
    /// de cámara viene guardada horizontal con la rotación en EXIF; el
    /// plan se calcula sobre lo que se ve, no sobre lo que está guardado).
    let sourceWidth: Int
    let sourceHeight: Int

    /// Esquina superior izquierda del cuadrado que se conserva, en píxeles
    /// de la imagen de origen.
    let cropX: Int
    let cropY: Int

    /// Lado del cuadrado que se conserva: el lado corto del origen.
    let cropSide: Int

    /// Lado de la imagen final: `min(lado corto, maxSide)`. Nunca se
    /// escala hacia arriba -- una fuente más chica que `maxSide` sale con
    /// su propio tamaño, igual que en `ImageResizer.resizeToLCDOptimal`.
    let outputSide: Int

    /// El plan vacío: la fuente no tiene un tamaño utilizable (o el lado
    /// pedido no lo es). El llamador falla con un mensaje claro en vez de
    /// mandarle al codificador una imagen de cero píxeles.
    static let empty = SquareCropPlan(sourceWidth: 0, sourceHeight: 0,
                                      cropX: 0, cropY: 0, cropSide: 0, outputSide: 0)

    private init(sourceWidth: Int, sourceHeight: Int,
                 cropX: Int, cropY: Int, cropSide: Int, outputSide: Int) {
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.cropX = cropX
        self.cropY = cropY
        self.cropSide = cropSide
        self.outputSide = outputSide
    }

    init(width: Int, height: Int, maxSide: Int) {
        guard width > 0, height > 0, maxSide > 0 else {
            self = .empty
            return
        }

        let side = min(width, height)
        // La división entera reparte el sobrante de forma determinista: con
        // un margen impar el píxel de más se descarta del lado DERECHO (o
        // INFERIOR), nunca "el que toque". Que las dos plataformas recorten
        // el mismo píxel es lo que hace comparables sus pruebas.
        self = SquareCropPlan(sourceWidth: width, sourceHeight: height,
                              cropX: (width - side) / 2,
                              cropY: (height - side) / 2,
                              cropSide: side,
                              outputSide: min(side, maxSide))
    }

    var isEmpty: Bool { cropSide <= 0 || outputSide <= 0 }

    /// `false` cuando la fuente ya era cuadrada: no hay nada que tirar.
    var needsCrop: Bool { !isEmpty && (cropSide != sourceWidth || cropSide != sourceHeight) }

    /// `false` cuando el cuadrado recortado ya mide lo pedido: no hay que
    /// remuestrear (y remuestrear de gratis solo pierde definición).
    var needsResize: Bool { !isEmpty && outputSide != cropSide }
}
