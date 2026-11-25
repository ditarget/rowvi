import AppKit
import Sparkle
import SwiftUI

struct ProfileControls: View {
    @ObservedObject var model: RowviModel
    let pickerWidth: CGFloat
    @ViewState private var action: NameAction?
    @ViewState private var removing: LayoutProfile?

    var body: some View {
        HStack(spacing: 6) {
            Picker("Профиль", selection: Binding(
                get: { model.library.selectedID },
                set: { model.selectProfile($0) }
            )) {
                ForEach(model.library.profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: pickerWidth)
            .help("Выбрать и применить профиль")

            Menu {
                Button("Новый профиль…") { action = NameAction(kind: .create, profile: model.library.selected) }
                Button("Дублировать профиль…") { action = NameAction(kind: .duplicate, profile: model.library.selected) }
                Button("Переименовать…") { action = NameAction(kind: .rename, profile: model.library.selected) }
                Divider()
                Toggle("Убирать лишние рабочие столы и приложения", isOn: Binding(
                    get: { model.library.selected.cleanupOnApply },
                    set: { model.updateCleanup($0) }
                ))
                Divider()
                Button("Удалить профиль…", role: .destructive) { removing = model.library.selected }
                    .disabled(model.library.profiles.count < 2)
            } label: {
                Label("Управление профилями", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .fixedSize(horizontal: true, vertical: false)
        .disabled(model.applying || model.storageError != nil)
        .sheet(item: $action) { action in
            ProfileNameSheet(
                title: action.kind.title,
                name: action.kind == .rename ? action.profile.name : ""
            ) { name in
                switch action.kind {
                case .create: try model.createProfile(named: name)
                case .duplicate: try model.createProfile(named: name, copying: action.profile)
                case .rename: try model.renameProfile(action.profile.id, to: name)
                }
            }
        }
        .alert("Удалить профиль «\(removing?.name ?? "")»?", isPresented: Binding(
            get: { removing != nil },
            set: { if !$0 { removing = nil } }
        ), presenting: removing) { profile in
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) { model.removeProfile(profile.id) }
        }
    }

    private struct NameAction: Identifiable {
        let id = UUID()
        let kind: NameActionKind
        let profile: LayoutProfile
    }

    private enum NameActionKind {
        case create, duplicate, rename
        var title: String {
            switch self {
            case .create: "Новый профиль"
            case .duplicate: "Дублировать профиль"
            case .rename: "Переименовать профиль"
            }
        }
    }
}

private struct ProfileNameSheet: View {
    let title: String
    @ViewState var name: String
    let save: (String) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @ViewState private var issue: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            TextField("Имя профиля", text: $name)
                .focused($focused)
            if let issue {
                Text(issue)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Отмена", role: .cancel) { dismiss() }
                Button("Сохранить", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 310)
        .onAppear { focused = true }
    }

    private func submit() {
        do {
            try save(name)
            dismiss()
        } catch {
            issue = error.localizedDescription
        }
    }
}

struct RowviMenu: View {
    @ObservedObject var model: RowviModel
    let updates: SPUStandardUpdaterController?
    let openWindow: (String) -> Void

    var body: some View {
        Button("Открыть Rowvi") { openWindow("layout") }
        Button("Настройки…") { openWindow("preferences") }
            .keyboardShortcut(",", modifiers: .command)
        if let updates {
            CheckForUpdatesButton(updates: updates)
        }

        Divider()
        Section(model.applying ? "Применение профиля…" : "Профили") {
            ForEach(model.library.profiles) { profile in
                Button {
                    model.selectProfile(profile.id)
                } label: {
                    if profile.id == model.library.selectedID {
                        Label(profile.name, systemImage: "checkmark")
                    } else {
                        Text(profile.name)
                    }
                }
                .disabled(model.applying || model.storageError != nil)
            }
        }

        Divider()
        Button("Завершить Rowvi") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}

struct CheckForUpdatesButton: View {
    let updates: SPUStandardUpdaterController
    @ViewState private var canCheck = false

    var body: some View {
        Button("Проверить обновления…") { updates.checkForUpdates(nil) }
            .disabled(!canCheck)
            .onReceive(updates.updater.publisher(for: \.canCheckForUpdates)) { canCheck = $0 }
    }
}
