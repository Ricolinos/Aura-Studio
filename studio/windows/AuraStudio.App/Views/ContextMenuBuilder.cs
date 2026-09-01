using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using AuraStudio.Core.Library;

namespace AuraStudio.App.Views;

/// <summary>
/// Convierte los menús que decide Core (<see cref="LibraryContextMenus"/>,
/// <see cref="MediaTableContextMenu"/>) en un <see cref="MenuFlyout"/> de WinUI.
///
/// <para>Acá <b>no se decide nada</b>: ni qué ítems hay, ni en qué orden, ni
/// cuáles van deshabilitados. Todo eso está en Core, comparado renglón por
/// renglón contra <c>docs/paridad-menus-contextuales.md</c> (ST-105). Esto solo
/// dibuja.</para>
/// </summary>
public static class ContextMenuBuilder
{
    /// <summary>
    /// El menú, o <c>null</c> si no hay ítems — que es un caso real y no un
    /// error: el tema por omisión no muestra menú ninguno, y mostrar uno vacío
    /// no es lo mismo.
    /// </summary>
    public static MenuFlyout? Build(IReadOnlyList<MenuEntry> entries, Action<string> onInvoke)
    {
        if (entries.Count == 0) return null;

        var menu = new MenuFlyout();

        foreach (MenuFlyoutItemBase item in Items(entries, onInvoke)) menu.Items.Add(item);

        return menu;
    }

    private static IEnumerable<MenuFlyoutItemBase> Items(IReadOnlyList<MenuEntry> entries, Action<string> onInvoke)
    {
        foreach (MenuEntry entry in entries)
        {
            if (entry.IsSeparator)
            {
                yield return new MenuFlyoutSeparator();
                continue;
            }

            if (entry.Submenu is { Count: > 0 } submenu)
            {
                var sub = new MenuFlyoutSubItem { Text = entry.Text, IsEnabled = entry.Enabled };
                foreach (MenuFlyoutItemBase child in Items(submenu, onInvoke)) sub.Items.Add(child);

                yield return sub;
                continue;
            }

            if (entry.Checked)
            {
                var toggle = new ToggleMenuFlyoutItem { Text = entry.Text, IsChecked = true, IsEnabled = entry.Enabled };
                string toggleId = entry.Id;
                toggle.Click += (_, _) => onInvoke(toggleId);

                yield return toggle;
                continue;
            }

            var item = new MenuFlyoutItem { Text = entry.Text, IsEnabled = entry.Enabled };

            // Lo destructivo va marcado (regla 0.3 del documento): en macOS es
            // rojo; acá, el estilo de acción destructiva del sistema.
            if (entry.Role == MenuRole.Destructive
                && Application.Current.Resources.TryGetValue("MenuFlyoutItemStyle", out object? _))
            {
                item.Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current
                    .Resources["SystemFillColorCriticalBrush"];
            }

            string id = entry.Id;
            item.Click += (_, _) => onInvoke(id);

            yield return item;
        }
    }
}
