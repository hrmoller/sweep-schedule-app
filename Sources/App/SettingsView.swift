import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var message: String?

    // Explicit so the initializer stays internal: the synthesized memberwise init becomes private
    // because of the private @State properties, which newer Swift toolchains (CI) reject.
    init(model: AppModel) {
        _model = ObservedObject(wrappedValue: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Watched folders")
                .font(.headline)
            Text("Items directly inside these folders are moved to the Trash once they are older than the limit. You get a notification beforehand, with time to move things elsewhere.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach($model.config.folders) { $folder in
                    FolderRow(folder: $folder) { model.removeFolder(id: folder.id) }
                }
            }
            .frame(minHeight: 200)

            HStack {
                Button("Add Folder…", action: addFolder)
                Spacer()
            }

            Divider()

            HStack {
                Picker("Daily check at", selection: $model.config.checkHour) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(String(format: "%02d:00", hour)).tag(hour)
                    }
                }
                .frame(width: 220)

                Spacer()

                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        do { try LoginItem.set(enabled) }
                        catch {
                            message = "Couldn't change the login item: \(error.localizedDescription)"
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
            }

            Text("Age is measured from the newest of the date an item was added to the folder and its last modification. Items go to the Trash, not straight to oblivion, so you can still put them back.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(minWidth: 580, minHeight: 440)
        .alert("Sweep Schedule",
               isPresented: Binding(get: { message != nil },
                                    set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch Folder"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let problem = model.addFolder(url) { message = problem }
    }
}

private struct FolderRow: View {
    @Binding var folder: WatchedFolder
    var onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("Enabled", isOn: $folder.enabled)
                .labelsHidden()
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(folder.displayName).font(.body.weight(.semibold))
                Text(folder.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 20) {
                    Stepper(value: $folder.maxAgeDays, in: 2...3650) {
                        Text("Trash after \(folder.maxAgeDays) days")
                    }
                    Stepper(value: $folder.warnDays, in: 1...30) {
                        Text("Warn \(folder.warnDays) days ahead")
                    }
                }
                .disabled(!folder.enabled)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Stop watching this folder")
        }
        .padding(.vertical, 4)
    }
}
