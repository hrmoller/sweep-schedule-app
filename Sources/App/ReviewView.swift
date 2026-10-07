import AppKit
import SwiftUI

/// Lists everything that is inside its warning period, with "Reveal" and "Keep".
struct ReviewView: View {
    @ObservedObject var model: AppModel

    private struct FolderGroup: Identifiable {
        let id: UUID
        let name: String
        let items: [Evaluation]
    }

    private var groups: [FolderGroup] {
        Dictionary(grouping: model.pending, by: { $0.folderID })
            .map { FolderGroup(id: $0.key,
                         name: $0.value.first?.folderName ?? "",
                         items: $0.value.sorted { $0.deadline < $1.deadline }) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.pending.isEmpty
                         ? "Nothing is about to be trashed"
                         : "\(model.pending.count) item\(model.pending.count == 1 ? "" : "s") will be moved to the Trash soon")
                        .font(.headline)
                    Text("Move anything you want to keep to another folder, or press Keep to restart its clock.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let total = Summary.totalSizeText(for: model.pending) {
                        Label("Moving \(total) to the Trash", systemImage: "internaldrive")
                            .font(.callout.weight(.medium))
                            .padding(.top, 2)
                            .help("Disk space is freed once the Trash is emptied")
                    }
                }
                Spacer()
                Button("Refresh") { Task { await model.preview() } }
                    .disabled(model.isRunning)
            }
            .padding()

            Divider()

            if model.pending.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("All clear").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups) { group in
                        Section(group.name) {
                            ForEach(group.items) { ev in row(ev) }
                        }
                    }
                }
            }

            if !model.errors.isEmpty {
                Divider()
                Text(model.errors.joined(separator: "\n"))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        }
        .frame(minWidth: 560, minHeight: 360)
    }

    private func row(_ ev: Evaluation) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: ev.item.url.path))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(ev.name).lineLimit(1).truncationMode(.middle)
                Text(whenText(ev))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Reveal") {
                NSWorkspace.shared.activateFileViewerSelecting([ev.item.url])
            }
            Button("Keep") { model.keep(ev) }
                .disabled(model.isRunning)
        }
        .padding(.vertical, 2)
    }

    private func whenText(_ ev: Evaluation) -> String {
        let size = ev.size > 0 ? " · \(Summary.sizeText(ev.size))" : ""
        if ev.verdict == .trash { return "Due now — moves to the Trash at the next check" + size }
        let days = ev.daysLeft(now: Date())
        let date = ev.deadline.formatted(date: .abbreviated, time: .omitted)
        return "Moves to the Trash in \(days) day\(days == 1 ? "" : "s") (\(date))" + size
    }
}
