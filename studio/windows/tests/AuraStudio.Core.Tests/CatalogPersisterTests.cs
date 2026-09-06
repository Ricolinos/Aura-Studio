using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-204: el catálogo se guarda una vez por ráfaga y fuera del hilo de
/// interfaz. Lo que se prueba acá es la coalescencia, cuándo se arma la
/// instantánea y qué pasa al cerrar con algo pendiente — no el formato del
/// archivo, que ya tiene sus pruebas.
/// </summary>
public class CatalogPersisterTests : IDisposable
{
    private readonly string _root =
        Path.Combine(Path.GetTempPath(), "aura-persist-" + Guid.NewGuid().ToString("N"));

    public CatalogPersisterTests() => Directory.CreateDirectory(_root);

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* limpieza best-effort */ }
        GC.SuppressFinalize(this);
    }

    /// <summary>
    /// Un anfitrión de mentira: el temporizador no corre solo, salta cuando la
    /// prueba lo dice. Es lo que permite probar medio segundo de coalescencia
    /// sin esperar medio segundo.
    /// </summary>
    private sealed class FakeHost : ICatalogPersisterHost
    {
        private Action? _scheduled;

        public int ScheduleCount { get; private set; }
        public int CancelCount { get; private set; }
        public int BackgroundCount { get; private set; }
        public TimeSpan LastDelay { get; private set; }
        public bool HasScheduled => _scheduled is not null;

        public void ScheduleAfter(TimeSpan delay, Action work)
        {
            ScheduleCount++;
            LastDelay = delay;
            _scheduled = work;
        }

        public void CancelScheduled()
        {
            CancelCount++;
            _scheduled = null;
        }

        public void RunInBackground(Action work)
        {
            BackgroundCount++;
            work();
        }

        /// <summary>Hace saltar el temporizador, si hay algo armado.</summary>
        public void Fire()
        {
            Action? work = _scheduled;
            _scheduled = null;
            work?.Invoke();
        }
    }

    private static PersistedLibrary CatalogWith(int items)
    {
        var catalog = new PersistedLibrary();
        for (int i = 0; i < items; i++)
        {
            catalog.Items.Add(new PersistedLibraryItem
            {
                Id = Guid.NewGuid(),
                SourceRelativePath = $"Música/{i}.mp3",
                Kind = "song",
            });
        }

        return catalog;
    }

    [Fact]
    public void UnaRafagaDeCambiosEsUnSoloGuardado()
    {
        var host = new FakeHost();
        int builds = 0;
        var persister = new CatalogPersister(
            host,
            () =>
            {
                builds++;
                return new CatalogSnapshotRequest(false, _root, () => CatalogWith(1));
            });

        // "Aplicar la tapa recomendada a 200 álbumes".
        for (int i = 0; i < 200; i++) persister.Schedule();

        Assert.Equal(0, builds);
        Assert.True(persister.HasPending);

        host.Fire();

        Assert.Equal(1, builds);
        Assert.Equal(1, persister.WriteCount);
        Assert.False(persister.HasPending);
    }

    [Fact]
    public void CadaPedidoReemplazaAlAnteriorEnVezDeApilarse()
    {
        var host = new FakeHost();
        var persister = new CatalogPersister(
            host, () => new CatalogSnapshotRequest(false, _root, () => CatalogWith(1)));

        persister.Schedule();
        persister.Schedule();
        persister.Schedule();

        // Se pidió tres veces —cada una reinicia el reloj— pero solo queda una
        // escritura armada: al saltar escribe una vez y se queda sin nada.
        Assert.Equal(3, host.ScheduleCount);

        host.Fire();
        host.Fire();

        Assert.Equal(1, persister.WriteCount);
    }

    [Fact]
    public void LaInstantaneaSeArmaAlGuardarNoAlPedirlo()
    {
        var host = new FakeHost();
        int itemsAlArmar = -1;
        int live = 0;

        var persister = new CatalogPersister(
            host,
            () => new CatalogSnapshotRequest(false, _root, () =>
            {
                itemsAlArmar = live;
                return CatalogWith(live);
            }));

        live = 1;
        persister.Schedule();

        // Entre el pedido y el guardado siguieron entrando cambios: lo que se
        // escribe es el estado final, no el de cuando alguien pidió guardar.
        live = 7;
        host.Fire();

        Assert.Equal(7, itemsAlArmar);
    }

    [Fact]
    public void LaEscrituraProgramadaNoCorreEnElHiloDeInterfaz()
    {
        var host = new FakeHost();
        var persister = new CatalogPersister(
            host, () => new CatalogSnapshotRequest(false, _root, () => CatalogWith(3)));

        persister.Schedule();
        host.Fire();

        Assert.Equal(1, host.BackgroundCount);
    }

    [Fact]
    public void CerrarConAlgoPendienteLoEscribeAntesDeSalir()
    {
        var host = new FakeHost();
        var persister = new CatalogPersister(
            host, () => new CatalogSnapshotRequest(false, _root, () => CatalogWith(2)));

        persister.Schedule();
        Assert.True(persister.HasPending);

        persister.Flush();

        Assert.Equal(1, persister.WriteCount);
        Assert.False(persister.HasPending);
        Assert.Equal(1, host.CancelCount);
        Assert.False(host.HasScheduled);

        // Sin volver: el guardado de salida es sincrónico, porque después de
        // cerrar la ventana ya no hay hilo de fondo al que volver.
        Assert.Equal(0, host.BackgroundCount);

        LibraryCatalogStore.CatalogLoad saved = LibraryCatalogStore.TryLoad(_root);
        Assert.Null(saved.Error);
        Assert.Equal(2, saved.Catalog.Items.Count);
    }

    [Fact]
    public void CerrarSinNadaPendienteNoEscribeNada()
    {
        var host = new FakeHost();
        int builds = 0;
        var persister = new CatalogPersister(
            host,
            () =>
            {
                builds++;
                return new CatalogSnapshotRequest(false, _root, () => CatalogWith(1));
            });

        persister.Flush();

        Assert.Equal(0, builds);
        Assert.Equal(0, persister.WriteCount);
        Assert.False(File.Exists(Path.Combine(_root, PersistedLibrary.CatalogFileName)));
    }

    [Fact]
    public void SinBibliotecaDelanteNoSeEscribeNada()
    {
        var host = new FakeHost();
        var persister = new CatalogPersister(host, () => CatalogSnapshotRequest.None);

        persister.Schedule();
        host.Fire();

        // ST-171: lo que hay en memoria no es el catálogo del usuario, es lo
        // que quedó de no haberlo podido leer. Guardarlo lo reemplazaría.
        Assert.Equal(0, persister.WriteCount);
        Assert.False(File.Exists(Path.Combine(_root, PersistedLibrary.CatalogFileName)));
    }

    [Fact]
    public void SiElDiscoSeFueLoDiceYNoRompe()
    {
        var host = new FakeHost();
        const string missing = @"Q:\no\existe\biblioteca";
        var persister = new CatalogPersister(
            host, () => new CatalogSnapshotRequest(false, missing, () => CatalogWith(1)));

        string? reported = null;
        persister.Failed += (_, message) => reported = message;

        persister.Schedule();
        host.Fire();

        Assert.NotNull(reported);
        Assert.Contains("no está disponible", reported);
        Assert.Equal(0, persister.WriteCount);
    }

    [Fact]
    public void LaEsperaPredeterminadaNoPasaDeMedioSegundo()
    {
        var host = new FakeHost();
        var persister = new CatalogPersister(
            host, () => new CatalogSnapshotRequest(false, _root, () => CatalogWith(1)));

        persister.Schedule();

        Assert.True(host.LastDelay <= TimeSpan.FromMilliseconds(500));
        Assert.Equal(CatalogPersister.DefaultDelay, host.LastDelay);
    }
}
