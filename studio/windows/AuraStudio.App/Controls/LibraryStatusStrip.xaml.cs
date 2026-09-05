using AuraStudio.App.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace AuraStudio.App.Controls;

/// <summary>Ver <c>LibraryStatusStrip.xaml</c>.</summary>
public sealed partial class LibraryStatusStrip : UserControl
{
    public static readonly DependencyProperty LibraryProperty = DependencyProperty.Register(
        nameof(Library), typeof(LibraryViewModel), typeof(LibraryStatusStrip), new PropertyMetadata(null));

    public LibraryViewModel? Library
    {
        get => (LibraryViewModel?)GetValue(LibraryProperty);
        set => SetValue(LibraryProperty, value);
    }

    public LibraryStatusStrip() => InitializeComponent();

    private void Cancel_Click(object sender, RoutedEventArgs e) => Library?.CancelCoverNormalization();
}
