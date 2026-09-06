using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using AuraStudio.Core.Library;

namespace AuraStudio.App.Services;

/// <summary>
/// Una tarea de fondo visible para el usuario (ST-203; paridad con
/// <c>BackgroundTaskCenter.TaskHandle</c> de ST-156).
///
/// <para>Es observable <b>ella</b>, y no solo el centro, para que mover su
/// avance repinte su renglón y no la lista entera: una carga de 12 000
/// elementos avisa decenas de veces, y cada aviso no puede costar redibujar
/// todo lo que esté mirando el centro.</para>
/// </summary>
public sealed partial class BackgroundTaskHandle : ObservableObject
{
    private readonly Action? _onCancelRequested;

    internal BackgroundTaskHandle(string title, BackgroundTaskProgress progress, Action? onCancelRequested)
    {
        Title = title;
        Progress = progress;
        _onCancelRequested = onCancelRequested;
    }

    public Guid Id { get; } = Guid.NewGuid();

    /// <summary>En español y de cara al usuario: "Cargando biblioteca…".</summary>
    public string Title { get; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Fraction))]
    [NotifyPropertyChangedFor(nameof(IsDeterminate))]
    [NotifyPropertyChangedFor(nameof(Detail))]
    public partial BackgroundTaskProgress Progress { get; private set; }

    /// <summary>Detalle bajo el título; si está vacío se usa el "N de M" del avance.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Detail))]
    public partial string StatusText { get; set; } = "";

    /// <summary>
    /// Vacío mientras va bien. Si se llena, la tarea lo muestra y sigue
    /// existiendo hasta que quien la abrió la cierre: <b>un error no dura para
    /// siempre</b>, pero tampoco desaparece antes de que alguien lo lea.
    /// </summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasError))]
    public partial string ErrorText { get; private set; } = "";

    public bool HasError => ErrorText.Length > 0;

    public bool IsCancelled { get; private set; }

    /// <summary>
    /// <c>false</c> cuando la tarea no ofrece cancelar. Hay operaciones que no
    /// se pueden interrumpir a medias sin arriesgar dejar algo corrupto —
    /// escribir el catálogo, por ejemplo—, y ofrecer un botón que no se puede
    /// cumplir es peor que no ofrecerlo.
    /// </summary>
    public bool IsCancellable => _onCancelRequested is not null;

    public double? Fraction => Progress.Fraction;

    public bool IsDeterminate => Progress.IsDeterminate;

    /// <summary>Lo que se lee bajo el título: el detalle propio, o el "N de M".</summary>
    public string Detail => StatusText.Length > 0 ? StatusText : Progress.CountText;

    public void Update(BackgroundTaskProgress progress, string? statusText = null)
    {
        Progress = progress;
        if (statusText is not null) StatusText = statusText;
    }

    public void Fail(string message) => ErrorText = message;

    public void RequestCancel()
    {
        if (IsCancelled) return;

        IsCancelled = true;
        _onCancelRequested?.Invoke();
    }
}

/// <summary>
/// Lo que la app está haciendo por su cuenta, dicho en un solo lugar (ST-203;
/// paridad con <c>BackgroundTaskCenter.swift</c> de ST-156).
///
/// <para>Antes, el trabajo de fondo o no se veía —la biblioteca cargando, los
/// tamaños midiéndose— o se anunciaba pisando <c>StatusMessage</c>, que es el
/// renglón donde se contesta lo que el usuario acaba de pedir. Una tarea que
/// nadie pidió no puede tapar la respuesta a lo que sí se pidió.</para>
///
/// <para><b>Todo acá se toca desde el hilo de interfaz.</b> Quien trabaja en el
/// pool vuelve al despachador para mover el avance, igual que el resto de la
/// app (ST-131).</para>
/// </summary>
public sealed partial class BackgroundTaskCenter : ObservableObject
{
    /// <summary>Las tareas vivas, en el orden en que empezaron.</summary>
    public ObservableCollection<BackgroundTaskHandle> Tasks { get; } = [];

    public bool IsEmpty => Tasks.Count == 0;

    public int Count => Tasks.Count;

    /// <summary>
    /// El avance de todas juntas, para un solo indicador. Las indeterminadas no
    /// promedian —no tienen fracción que aportar—, pero su presencia ya basta
    /// para que el indicador se vea.
    /// </summary>
    public double? AggregateFraction =>
        BackgroundTaskProgress.Aggregate(Tasks.Select(task => task.Progress));

    /// <summary>
    /// La que se muestra cuando hay lugar para una sola: la primera. Con una
    /// tarea es la que hay; con varias, la más vieja — que es la que el usuario
    /// lleva más rato esperando.
    /// </summary>
    public BackgroundTaskHandle? Current => Tasks.Count > 0 ? Tasks[0] : null;

    /// <summary>
    /// Registra una tarea y la deja visible ya. Quien llama se queda con lo
    /// devuelto para mover el avance y <b>tiene que llamar a
    /// <see cref="Finish"/></b> cuando termine — con <c>try/finally</c>, para
    /// que un error a mitad no deje la tarea pegada para siempre.
    /// </summary>
    public BackgroundTaskHandle Begin(
        string title, BackgroundTaskProgress progress = default, Action? onCancelRequested = null)
    {
        var handle = new BackgroundTaskHandle(title, progress, onCancelRequested);
        handle.PropertyChanged += OnTaskChanged;
        Tasks.Add(handle);
        Changed();
        return handle;
    }

    public void Finish(BackgroundTaskHandle handle)
    {
        handle.PropertyChanged -= OnTaskChanged;
        if (Tasks.Remove(handle)) Changed();
    }

    private void OnTaskChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(BackgroundTaskHandle.Progress)) OnPropertyChanged(nameof(AggregateFraction));
    }

    private void Changed()
    {
        OnPropertyChanged(nameof(IsEmpty));
        OnPropertyChanged(nameof(Count));
        OnPropertyChanged(nameof(Current));
        OnPropertyChanged(nameof(AggregateFraction));
    }
}
