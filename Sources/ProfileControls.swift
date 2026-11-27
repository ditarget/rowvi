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
            Picker(model.language.text("Profile"), selection: Binding(
                get: { model.library.selectedID },
                set: { model.selectProfile($0) }
            )) {
                ForEach(model.library.profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: pickerWidth)
            .help(model.language.text("Select and apply a profile"))

            Menu {
                Button(model.language.text("New Profile…")) { action = NameAction(kind: .create, profile: model.library.selected) }
                Button(model.language.text("Duplicate Profile…")) { action = NameAction(kind: .duplicate, profile: model.library.selected) }
                Button(model.language.text("Rename…")) { action = NameAction(kind: .rename, profile: model.library.selected) }
                Divider()
                Toggle(model.language.text("Remove extra desktops and apps"), isOn: Binding(
                    get: { model.library.selected.cleanupOnApply },
                    set: { model.updateCleanup($0) }
                ))
                Divider()
                Button(model.language.text("Delete Profile…"), role: .destructive) { removing = model.library.selected }
                    .disabled(model.library.profiles.count < 2)
            } label: {
                Label(model.language.text("Manage Profiles"), systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .fixedSize(horizontal: true, vertical: false)
        .disabled(model.applying || model.storageError != nil)
        .sheet(item: $action) { action in
            ProfileNameSheet(
                model: model,
                titleKey: action.kind.titleKey,
                name: action.kind == .rename ? action.profile.name : ""
            ) { name in
                switch action.kind {
                case .create: try model.createProfile(named: name)
                case .duplicate: try model.createProfile(named: name, copying: action.profile)
                case .rename: try model.renameProfile(action.profile.id, to: name)
                }
            }
        }
        .alert(model.language.text("Delete profile “%@”?", removing?.name ?? ""), isPresented: Binding(
            get: { removing != nil },
            set: { if !$0 { removing = nil } }
        ), presenting: removing) { profile in
            Button(model.language.text("Cancel"), role: .cancel) {}
            Button(model.language.text("Delete"), role: .destructive) { model.removeProfile(profile.id) }
        }
    }

    private struct NameAction: Identifiable {
        let id = UUID()
        let kind: NameActionKind
        let profile: LayoutProfile
    }

    private enum NameActionKind {
        case create, duplicate, rename
        var titleKey: String {
            switch self {
            case .create: "New Profile"
            case .duplicate: "Duplicate Profile"
            case .rename: "Rename Profile"
            }
        }
    }
}

private struct ProfileNameSheet: View {
    @ObservedObject var model: RowviModel
    let titleKey: String
    @ViewState var name: String
    let save: (String) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @ViewState private var issue: Error?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.language.text(titleKey)).font(.headline)
            TextField(model.language.text("Profile Name"), text: $name)
                .focused($focused)
            if let issue {
                Text(issue.localizedDescription)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(model.language.text("Cancel"), role: .cancel) { dismiss() }
                Button(model.language.text("Save"), action: submit)
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
            issue = error
        }
    }
}

struct RowviMenu: View {
    @ObservedObject var model: RowviModel
    let updates: SPUStandardUpdaterController?
    let openWindow: (String) -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button(model.language.text("Open Rowvi")) {
                dismiss()
                openWindow("layout")
            }
            Button(model.language.text("Settings…")) {
                dismiss()
                openWindow("preferences")
            }
            if let updates {
                CheckForUpdatesButton(updates: updates, language: model.language, beforeCheck: dismiss)
            }
            Divider()
            Text(model.applying ? model.language.text("Applying profile…") : model.language.text("Profiles"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.library.profiles) { profile in
                        Button {
                            dismiss()
                            model.selectProfile(profile.id)
                        } label: {
                            Label {
                                Text(profile.name).lineLimit(1)
                            } icon: {
                                Image(systemName: "checkmark")
                                    .opacity(profile.id == model.library.selectedID ? 1 : 0)
                            }
                        }
                        .disabled(model.applying || model.storageError != nil)
                    }
                }
            }
            .frame(height: CGFloat(min(model.library.profiles.count, 8)) * 25)
            .scrollBounceBehavior(.basedOnSize)
            Divider()
            Button(model.language.text("Quit Rowvi")) {
                dismiss()
                NSApp.terminate(nil)
            }
        }
        .buttonStyle(StatusMenuButtonStyle())
        .padding(6)
        .frame(width: 245)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
    }
}

private struct StatusMenuButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @ViewState private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .frame(height: 25)
            .contentShape(.rect)
            .background {
                if isEnabled && (hovered || configuration.isPressed) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.selection)
                }
            }
            .foregroundStyle(isEnabled ? .primary : .secondary)
            .onHover { hovered = $0 }
    }
}

struct CheckForUpdatesButton: View {
    let updates: SPUStandardUpdaterController
    let language: AppLanguage
    var beforeCheck: () -> Void = {}
    @ViewState private var canCheck = false

    var body: some View {
        Button(language.text("Check for Updates…")) {
            beforeCheck()
            updates.checkForUpdates(nil)
        }
            .disabled(!canCheck)
            .onReceive(updates.updater.publisher(for: \.canCheckForUpdates)) { canCheck = $0 }
    }
}
