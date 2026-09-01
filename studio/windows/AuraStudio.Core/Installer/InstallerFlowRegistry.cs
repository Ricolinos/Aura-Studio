namespace AuraStudio.Core.Installer;

/// <summary>
/// Punto único de verdad sobre si el instalador está activo. Port de
/// `InstallerFlowRegistry` de macOS (D-185).
///
/// <para><b>De dónde sale esta clase.</b> En macOS, el 2026-08-13, dos
/// instancias del instalador terminaron extrayendo el árbol `.rockbox` al mismo
/// tiempo sobre el mismo volumen: el disparo automático de un segundo
/// instalador ocurrió *en medio* del primero, aprovechando la ventana en la que
/// el volumen desaparece mientras corre nuestro propio formateo. Dos
/// extracciones en carrera sobre el mismo destino abortaron la instalación. La
/// lección quedó cara y es la razón de las dos banderas de acá.</para>
///
/// <list type="bullet">
/// <item><see cref="FlowActive"/> — hay un flujo iniciado (asistente abierto o
/// recorrido automático). **Ningún disparo automático puede tomar la pantalla
/// mientras esté encendida.**</item>
/// <item><see cref="BeginWriting"/>/<see cref="EndWriting"/> — cinturón y
/// tirantes por debajo: aunque dos flujos llegaran a coexistir, solo uno puede
/// estar escribiendo en el disco.</item>
/// </list>
///
/// Se registra como singleton en la DI (no es un estático global: así se puede
/// probar y no hay estado compartido entre pruebas).
/// </summary>
public sealed class InstallerFlowRegistry
{
    private readonly Lock _gate = new();
    private bool _writing;

    /// <summary>
    /// Hay un flujo de instalación o restauración en curso, iniciado por el
    /// usuario o por el reconocimiento automático. Mientras esté en `true`,
    /// nada automático puede interrumpir la pantalla.
    /// </summary>
    public bool FlowActive { get; set; }

    /// <summary>Alguna parte de la app está escribiendo en el disco del iPod ahora mismo.</summary>
    public bool IsWritingToDisk
    {
        get { lock (_gate) return _writing; }
    }

    /// <summary>
    /// Toma el candado de escritura. `false` significa que otro flujo ya está
    /// escribiendo y **quien llama no debe tocar el disco**.
    /// </summary>
    public bool BeginWriting()
    {
        lock (_gate)
        {
            if (_writing) return false;
            _writing = true;
            return true;
        }
    }

    public void EndWriting()
    {
        lock (_gate) _writing = false;
    }

    /// <summary>
    /// `true` si un disparo automático puede tomar la pantalla ahora: no hay
    /// flujo activo ni escritura en curso.
    /// </summary>
    public bool CanInterrupt => !FlowActive && !IsWritingToDisk;
}
