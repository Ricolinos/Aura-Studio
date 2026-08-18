import SwiftUI

/// "Opciones de visualización" de la tabla de Canciones (ST-030): la
/// ventana que Music.app abre desde el menu de encabezado. Todo lo que
/// se toca aca se aplica en vivo (las propiedades de `AppPreferences`
/// publican y persisten solas) -- no hay "Guardar", solo "Listo".
struct MusicViewOptionsView: View {
    @ObservedObject var preferences: AppPreferences
    let onDone: () -> Void

    private let checkboxColumns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Opciones de visualización")
                .font(.title2.bold())
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sortSection
                    Divider()
                    filterSection
                    Divider()
                    ForEach(MusicTableColumn.Group.allCases) { group in
                        columnGroup(group)
                    }
                    Divider()
                    columnOrderSection
                }
                .padding(.trailing, 8)
            }

            HStack {
                Button("Restablecer") {
                    preferences.musicVisibleColumns = MusicTableColumn.defaultVisible
                    preferences.musicSortField = .title
                    preferences.musicSortAscending = true
                    preferences.musicShowOnlyFavorites = false
                }
                Spacer()
                Button("Listo", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(width: 520, height: 620)
    }

    private var sortSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ordenar por:")
                Picker("", selection: $preferences.musicSortField) {
                    ForEach(MusicSortField.menuFields, id: \.self) { field in
                        Text(field.title).tag(field)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
            }
            Picker("", selection: $preferences.musicSortAscending) {
                Text("Ascendente").tag(true)
                Text("Descendente").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)
        }
    }

    private var filterSection: some View {
        Toggle("Mostrar solo favoritos", isOn: $preferences.musicShowOnlyFavorites)
    }

    private func columnGroup(_ group: MusicTableColumn.Group) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.title)
                .font(.headline)
            LazyVGrid(columns: checkboxColumns, alignment: .leading, spacing: 6) {
                ForEach(group.columns) { column in
                    Toggle(column.title, isOn: Binding(
                        get: { preferences.musicVisibleColumns.contains(column) },
                        set: { _ in preferences.toggleMusicColumn(column) }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    /// El orden de la tabla es el orden de esta lista: arrastra para
    /// reacomodar. Título siempre va primero y no aparece aca.
    private var columnOrderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Orden de las columnas")
                .font(.headline)
            Text("Arrastra para cambiar el orden. \"Título\" siempre va primero.")
                .font(.caption)
                .foregroundStyle(.secondary)
            List {
                ForEach(preferences.musicVisibleColumns) { column in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                        Text(column.title)
                    }
                }
                .onMove { source, destination in
                    preferences.musicVisibleColumns.move(fromOffsets: source, toOffset: destination)
                }
            }
            .frame(height: max(60, CGFloat(preferences.musicVisibleColumns.count) * 26 + 12))
        }
    }
}
