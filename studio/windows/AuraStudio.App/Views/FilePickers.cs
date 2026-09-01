using System.Diagnostics;
using Windows.Storage;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace AuraStudio.App.Views;

/// <summary>
/// Los diálogos de archivo y "mostrar en el Explorador".
///
/// <para>En una app <b>sin empaquetar</b> los selectores de WinRT no saben a qué
/// ventana pertenecen y lanzan si no se les dice: hay que darles el
/// <c>HWND</c> de la ventana principal con <c>InitializeWithWindow</c>. Es el
/// detalle que hace que "abrir un diálogo" falle solo en Release o solo fuera
/// del depurador si se olvida, así que está en un solo lugar.</para>
/// </summary>
public static class FilePickers
{
    public static async Task<IReadOnlyList<string>> PickFilesAsync(IEnumerable<string> extensions)
    {
        var picker = new FileOpenPicker { ViewMode = PickerViewMode.List };
        foreach (string extension in extensions) picker.FileTypeFilter.Add("." + extension);
        if (picker.FileTypeFilter.Count == 0) picker.FileTypeFilter.Add("*");

        Attach(picker);

        IReadOnlyList<StorageFile> files = await picker.PickMultipleFilesAsync();
        return [.. files.Select(file => file.Path)];
    }

    public static async Task<string?> PickFolderAsync()
    {
        var picker = new FolderPicker();
        picker.FileTypeFilter.Add("*");
        Attach(picker);

        StorageFolder? folder = await picker.PickSingleFolderAsync();
        return folder?.Path;
    }

    /// <summary>Abre una carpeta en el Explorador. Nunca lanza.</summary>
    public static void OpenFolder(string path)
    {
        try
        {
            if (!Directory.Exists(path)) return;
            Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
        }
        catch (Exception)
        {
            // Sin Explorador disponible no hay nada que hacer.
        }
    }

    /// <summary>
    /// Abre el Explorador con el archivo seleccionado. Nunca lanza: no poder
    /// mostrar dónde está algo no puede tumbar la app.
    /// </summary>
    public static void RevealInExplorer(string path)
    {
        try
        {
            if (!File.Exists(path) && !Directory.Exists(path)) return;

            Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{path}\"")
            {
                UseShellExecute = true
            });
        }
        catch (Exception)
        {
            // Sin Explorador disponible no hay nada que hacer, y tampoco nada
            // que romper.
        }
    }

    public static void Attach(object picker)
    {
        if (App.MainWindowHandle == IntPtr.Zero) return;
        InitializeWithWindow.Initialize(picker, App.MainWindowHandle);
    }
}
