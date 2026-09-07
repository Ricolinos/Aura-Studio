import SwiftUI

/// PLAN-studio-rendimiento.md Fase 4 punto 4: indicador en la barra de
/// herramientas de la ventana (anillo de progreso agregado + "N tareas")
/// con un popover que lista cada una, su progreso y Cancelar -- mismo
/// patrón que la ventana de copia del Finder / la actividad de Xcode.
/// Invisible sin ninguna tarea corriendo (nunca ocupa espacio de más).
struct BackgroundTaskCenterIndicator: View {
    @ObservedObject var center: BackgroundTaskCenter
    @State private var showingPopover = false

    var body: some View {
        if !center.isEmpty {
            Button {
                showingPopover = true
            } label: {
                HStack(spacing: 6) {
                    if let fraction = center.aggregateFraction {
                        ProgressView(value: fraction).controlSize(.small).frame(width: 16)
                    } else {
                        ProgressView().controlSize(.small).frame(width: 16)
                    }
                    Text(LSf("background-task-center.plural.tareas", center.count))
                        .font(.callout)
                }
            }
            .buttonStyle(.plain)
            .help(LS("background-task-center-indicator.ver-lo-que-esta-corriendo-segundo"))
            .popover(isPresented: $showingPopover) {
                BackgroundTaskCenterPopover(center: center)
            }
        }
    }
}

private struct BackgroundTaskCenterPopover: View {
    @ObservedObject var center: BackgroundTaskCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(LS("background-task-center-indicator.actividad-segundo-plano"))
                .font(.headline)
                .padding([.horizontal, .top], 14)
                .padding(.bottom, 8)
            if center.isEmpty {
                Text(LS("background-task-center-indicator.nada-corriendo-ahora-mismo"))
                    .foregroundStyle(.secondary)
                    .padding([.horizontal, .bottom], 14)
            } else {
                Divider()
                ForEach(center.tasks) { task in
                    BackgroundTaskRow(task: task)
                    if task.id != center.tasks.last?.id { Divider() }
                }
            }
        }
        .frame(width: 320)
    }
}

private struct BackgroundTaskRow: View {
    @ObservedObject var task: BackgroundTaskCenter.TaskHandle

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title).font(.callout)
                if let statusText = task.statusText {
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
                if let errorText = task.errorText {
                    Text(errorText).font(.caption).foregroundStyle(.red)
                } else if let fraction = task.progress.fraction {
                    ProgressView(value: fraction).controlSize(.small)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            Spacer()
            if task.isCancellable {
                Button(LS("background-task-center-indicator.cancelar")) { task.requestCancel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(AuraColors.light.accent)
                    .font(.caption)
                    .disabled(task.isCancelled)
            }
        }
        .padding(12)
    }
}
