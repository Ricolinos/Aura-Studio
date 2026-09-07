// ST-247 (B7a, ensayo en seco): recorre AppStrings.cs y los literales de
// interfaz inventariados en la auditoría de B0 (studio/windows/docs/
// auditoria-idiomas.md) y produce claves estables + un borrador de revisión.
// NUNCA toca la app: solo lee AuraStudio.Core/AuraStudio.App y escribe en
// docs/extraccion-cadenas/ (Windows). Mismo criterio que
// tools/extraer-cadenas.py (Mac, ST-227): heurístico, para revisar a mano.
//
// Uso: dotnet run --project studio/windows/tools/ExtraerCadenasWindows

using AuraStudio.Tools.ExtraerCadenasWindows;

string repoRoot = FindRepoRoot(AppContext.BaseDirectory);
string windowsRoot = Path.Combine(repoRoot, "studio", "windows");
string appDir = Path.Combine(windowsRoot, "AuraStudio.App");
string coreDir = Path.Combine(windowsRoot, "AuraStudio.Core");
string outDir = Path.Combine(windowsRoot, "docs", "extraccion-cadenas");
Directory.CreateDirectory(outDir);

var keys = new KeyRegistry();
var allSites = new List<Site>();
var allPlurals = new List<PluralSite>();
var fixedCulture = new List<Site>();

// --- AppStrings.cs ---

string appStringsPath = Path.Combine(appDir, "Resources", "AppStrings.cs");
string appStringsText = CommentStripper.Strip(File.ReadAllText(appStringsPath));
int appStringsMemberCount = MemberBodyFinder.FindAll(appStringsText).Count;
(List<Site> appStringsSites, List<PluralSite> appStringsPlurals) =
    AppStringsExtractor.Extract(RelativePath(repoRoot, appStringsPath), appStringsText, keys);
allSites.AddRange(appStringsSites);
allPlurals.AddRange(appStringsPlurals);

// --- XAML ---

string[] xamlFiles = [.. Directory.EnumerateFiles(appDir, "*.xaml", SearchOption.AllDirectories)
    .Where(path => !path.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")
                && !path.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}"))
    .OrderBy(path => path, StringComparer.Ordinal)];

foreach (string xaml in xamlFiles)
{
    string text = File.ReadAllText(xaml);
    allSites.AddRange(XamlExtractor.Extract(RelativePath(repoRoot, xaml), text, keys));
}

// --- MenuEntry (ContextMenu.cs) ---

string contextMenuPath = Path.Combine(coreDir, "Library", "ContextMenu.cs");
string contextMenuText = CommentStripper.Strip(File.ReadAllText(contextMenuPath));
string contextMenuRelative = RelativePath(repoRoot, contextMenuPath);
allSites.AddRange(CSharpLiteralExtractor.ExtractMenuEntries(contextMenuRelative, contextMenuText, keys));
allPlurals.AddRange(PluralTernaryScan.Extract(contextMenuRelative, contextMenuText));

// --- StatusMessage / ContentDialog / ayudantes con texto de usuario /
// cultura fija, en todo AuraStudio.App ---

string[] appCsFiles = [.. Directory.EnumerateFiles(appDir, "*.cs", SearchOption.AllDirectories)
    .Where(path => !path.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")
                && !path.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}")
                && Path.GetFileName(path) != "AppStrings.cs")
    .OrderBy(path => path, StringComparer.Ordinal)];

foreach (string csFile in appCsFiles)
{
    string text = CommentStripper.Strip(File.ReadAllText(csFile));
    string relative = RelativePath(repoRoot, csFile);

    allSites.AddRange(CSharpLiteralExtractor.ExtractStatusMessages(relative, text, keys));
    allSites.AddRange(CSharpLiteralExtractor.ExtractContentDialogText(relative, text, keys));
    allSites.AddRange(CSharpLiteralExtractor.ExtractHelperFirstArgument(relative, text, keys));
    allPlurals.AddRange(PluralTernaryScan.Extract(relative, text));
    fixedCulture.AddRange(FixedCultureExtractor.Extract(relative, text, keys));
}

// El propio Core también puede declarar una cultura fija (MediaTableRow.cs
// vive ahí, no en App).
string[] coreCsFiles = [.. Directory.EnumerateFiles(coreDir, "*.cs", SearchOption.AllDirectories)
    .Where(path => !path.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")
                && !path.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}"))
    .OrderBy(path => path, StringComparer.Ordinal)];

foreach (string csFile in coreCsFiles)
{
    string text = CommentStripper.Strip(File.ReadAllText(csFile));
    string relative = RelativePath(repoRoot, csFile);

    fixedCulture.AddRange(FixedCultureExtractor.Extract(relative, text, keys));
    fixedCulture.AddRange(CatalogDataExtractor.Extract(relative, text, keys));
    if (Path.GetFileName(csFile) != "ContextMenu.cs") // ya se contó en su propio pase, con los ids de menú fuera
        allPlurals.AddRange(PluralTernaryScan.Extract(relative, text));
}

// --- Salidas ---

ResourceWriter.WriteRevisionCsv(Path.Combine(outDir, "revision.csv"), allSites, fixedCulture);
ResourceWriter.WritePluralsCsv(Path.Combine(outDir, "plurales-ternario.csv"), allPlurals);

Dictionary<string, string> spanish = allSites
    .GroupBy(s => s.Key)
    .ToDictionary(g => g.Key, g => g.First().TextWithMarkers, StringComparer.Ordinal);

ResourceWriter.WriteResw(Path.Combine(outDir, "Strings", "es", "Resources.resw"), spanish, english: false);
ResourceWriter.WriteResw(Path.Combine(outDir, "Strings", "en", "Resources.resw"), spanish, english: true);

// claves-compartidas.csv es co-propiedad con la Mac (ST-247, addendum):
// esto NUNCA lo regenera entero, solo actualiza la columna "sitio Windows"
// de las claves que ya cita, sin tocar "sitio Mac" ni "estado". Si el
// archivo no existe todavía, no hay nada que actualizar.
Dictionary<string, Site> sitesByKey = allSites
    .GroupBy(s => s.Key)
    .ToDictionary(g => g.Key, g => g.First(), StringComparer.Ordinal);
(int sharedUpdated, List<string> sharedMissingKeys) = ClavesCompartidasCsv.UpdateSitioWindows(
    Path.Combine(outDir, "claves-compartidas.csv"), sitesByKey);

// --- Conteos ---

int appStringsCount = allSites.Count(s => s.Kind == "AppStrings");
int xamlCount = allSites.Count(s => s.Kind == "XAML");
int menuEntryCount = allSites.Count(s => s.Kind == "MenuEntry");
int statusMessageCount = allSites.Count(s => s.Kind == "StatusMessage");
int contentDialogCount = allSites.Count(s => s.Kind == "ContentDialog");
int helperArgumentCount = allSites.Count(s => s.Kind == "HelperArgument");
int uniqueKeys = allSites.Select(s => s.Key).Distinct(StringComparer.Ordinal).Count();
int culturaFijaCount = fixedCulture.Count(s => s.Kind == "CulturaFija");
int datoCount = fixedCulture.Count(s => s.Kind == "Dato");

Console.WriteLine($"Archivos XAML recorridos: {xamlFiles.Length}");
Console.WriteLine($"Archivos .cs de AuraStudio.App recorridos: {appCsFiles.Length}");
Console.WriteLine($"Miembros de AppStrings.cs reconocidos: {appStringsMemberCount}");
Console.WriteLine();
Console.WriteLine($"Sitios AppStrings.cs: {appStringsCount}");
Console.WriteLine($"Sitios XAML: {xamlCount}");
Console.WriteLine($"Sitios MenuEntry (ContextMenu.cs): {menuEntryCount}");
Console.WriteLine($"Sitios StatusMessage: {statusMessageCount}");
Console.WriteLine($"Sitios ContentDialog: {contentDialogCount}");
Console.WriteLine($"Sitios HelperArgument: {helperArgumentCount}");
Console.WriteLine($"Total de sitios: {allSites.Count}");
Console.WriteLine($"Claves únicas: {uniqueKeys}");
Console.WriteLine($"Ternarios de plural encontrados: {allPlurals.Count}");
Console.WriteLine($"Sitios de cultura fija: {culturaFijaCount}");
Console.WriteLine($"Sitios de dato (no traducir): {datoCount}");
Console.WriteLine();
Console.WriteLine($"-> {Path.Combine(outDir, "revision.csv")}");
Console.WriteLine($"-> {Path.Combine(outDir, "plurales-ternario.csv")}");
Console.WriteLine($"-> {Path.Combine(outDir, "Strings", "es", "Resources.resw")}");
Console.WriteLine($"-> {Path.Combine(outDir, "Strings", "en", "Resources.resw")}");
Console.WriteLine();
Console.WriteLine($"claves-compartidas.csv: {sharedUpdated} cita(s) de sitio Windows actualizada(s).");
if (sharedMissingKeys.Count > 0)
{
    Console.WriteLine(
        $"  Claves citadas en claves-compartidas.csv que ya no existen en revision.csv ({sharedMissingKeys.Count}), " +
        "no tocadas -- revisar si es un renombre pendiente de reconciliar:");
    foreach (string key in sharedMissingKeys.Distinct(StringComparer.Ordinal)) Console.WriteLine($"    {key}");
}

static string RelativePath(string repoRoot, string absolute) =>
    Path.GetRelativePath(repoRoot, absolute).Replace('\\', '/');

static string FindRepoRoot(string startDirectory)
{
    DirectoryInfo? dir = new(startDirectory);
    while (dir is not null)
    {
        if (File.Exists(Path.Combine(dir.FullName, "studio", "windows", "AuraStudio.Windows.slnx")))
            return dir.FullName;

        dir = dir.Parent;
    }

    throw new InvalidOperationException(
        "No se encontró la raíz del repo (buscando studio/windows/AuraStudio.Windows.slnx hacia arriba).");
}
