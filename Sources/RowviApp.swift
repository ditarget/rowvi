import AppKit
import SwiftUI
import UniformTypeIdentifiers

typealias ViewState<Value> = SwiftUI.State<Value>

@main
struct RowviApp: App {
    @NSApplicationDelegateAdaptor(LayoutAppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Rowvi", id: "layout") {
            LayoutPanel(model: appDelegate.model) { appDelegate.openWindow = $0 }
        }
        .defaultSize(width: 800, height: 220)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)

        Window("Настройки Rowvi", id: "preferences") {
            PreferencesView(model: appDelegate.model, updates: appDelegate.updates)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)
    }
}

struct LayoutPanel: View {
    @ObservedObject var model: RowviModel
    let registerOpenWindow: (OpenWindowAction) -> Void
    @Environment(\.openWindow) private var openWindow
    @FocusState private var focusedTile: UUID?
    @ViewState private var selection: UUID?
    @ViewState private var editor: UUID?
    @ViewState private var issue: String?

    private var layout: Layout {
        get { model.library.selected.layout }
        nonmutating set { model.updateLayout(newValue) }
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = PanelMetrics(width: geometry.size.width, height: geometry.size.height, count: layout.spaces.count)
            VStack(spacing: 0) {
                if let error = model.storageError {
                    Text(error)
                        .padding()
                        .frame(maxHeight: .infinity)
                } else {
                    strip(metrics)
                        .frame(maxHeight: .infinity)
                        .disabled(model.applying)
                }
                footer(metrics)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 340, minHeight: 166)
        .background { WindowMaterial().ignoresSafeArea() }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Применить") { model.applySelected() }
                    .buttonStyle(.glassProminent)
                    .disabled(layout.spaces.isEmpty || model.applying || model.storageError != nil)
            }
        }
        .alert("Rowvi", isPresented: Binding(
            get: { issue != nil },
            set: { if !$0 { issue = nil } }
        )) {
            Button("OK") { issue = nil }
        } message: {
            Text(issue ?? "")
        }
        .onAppear { registerOpenWindow(openWindow) }
        .onChange(of: model.library.selectedID) {
            editor = nil
            selection = nil
        }
    }

    private func strip(_ metrics: PanelMetrics) -> some View {
        VStack(spacing: 7) {
            GlassEffectContainer(spacing: min(3, metrics.spacing / 2)) {
                HStack(spacing: metrics.spacing) {
                    ForEach(layout.spaces) { space in
                        tile(space, metrics).id(space.id)
                    }
                    .reorderable()
                }
                .reorderContainer(for: SpaceRule.self) { difference in
                    switch difference.destination.position {
                    case .before(let target): layout.move(difference.sources, before: target)
                    case .end: layout.move(difference.sources, before: nil)
                    }
                }
                .padding(.horizontal, metrics.inset)
                .frame(width: metrics.contentWidth)
            }
            if !metrics.showsLabels && !layout.spaces.isEmpty {
                let title = layout.spaces.first { $0.id == selection }?.title
                Text(title ?? " ")
                    .font(.system(size: metrics.interfaceFontSize, weight: .medium))
                    .lineLimit(1)
                    .padding(.horizontal, metrics.inset)
                    .accessibilityHidden(title == nil)
            }
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
    }

    private func footer(_ metrics: PanelMetrics) -> some View {
        HStack(spacing: 12) {
            footerButton("gearshape", label: "Настройки", size: metrics.actionSize) {
                openWindow(id: "preferences")
            }
            ProfileControls(model: model, pickerWidth: min(162, metrics.width * 0.3))
                .controlSize(metrics.actionSize > 36 ? .regular : .small)
            if model.applying {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Применение профиля")
            }
            Spacer(minLength: 12)
            GlassEffectContainer(spacing: 7) {
                HStack(spacing: 7) {
                    footerButton("minus", label: "Удалить выбранное пространство", size: metrics.actionSize, action: remove)
                        .disabled(selection == nil)
                    footerButton("plus", label: "Добавить рабочий стол", size: metrics.actionSize, action: add)
                }
            }
            .disabled(model.applying || model.storageError != nil)
        }
        .padding(.horizontal, metrics.inset)
        .padding(.bottom, 12)
        .padding(.top, 5)
    }

    private func footerButton(_ symbol: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.43, weight: .medium))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .help(label)
        .accessibilityLabel(label)
    }

    private func tile(_ space: SpaceRule, _ metrics: PanelMetrics) -> some View {
        let isSelected = selection == space.id
        let isFocused = focusedTile == space.id
        return Button {
            selection = space.id
            editor = space.id
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    if space.windows.isEmpty {
                        Image(systemName: "macwindow")
                            .font(.system(size: metrics.iconSize * 0.71, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: min(3, metrics.spacing / 2)) {
                            ForEach(Array(space.windows.prefix(3).enumerated()), id: \.offset) { _, rule in
                                appIcon(rule, size: min(metrics.iconSize, metrics.tileWidth / CGFloat(min(space.windows.count, 3) + 1)))
                            }
                        }
                    }
                }
                .frame(width: metrics.tileWidth, height: metrics.previewHeight)
                .glassEffect(
                    .regular.tint(isSelected ? Color.accentColor.opacity(0.58) : nil).interactive(),
                    in: .rect(cornerRadius: metrics.cornerRadius)
                )
                .overlay {
                    if isSelected || isFocused {
                        RoundedRectangle(cornerRadius: metrics.cornerRadius)
                            .strokeBorder(
                                Color.accentColor.opacity(isFocused ? 1 : 0.8),
                                style: StrokeStyle(lineWidth: isFocused ? 2 : 1.5, dash: isFocused ? [4, 3] : [])
                            )
                            .allowsHitTesting(false)
                    }
                }
                if metrics.showsLabels {
                    Text(space.title)
                        .font(.system(size: metrics.labelSize, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                        .frame(width: metrics.tileWidth)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusedTile, equals: space.id)
        .focusEffectDisabled()
        .help(space.title)
        .accessibilityLabel(space.title)
        .accessibilityAddTraits(selection == space.id ? .isSelected : [])
        .popover(isPresented: Binding(
            get: { editor == space.id },
            set: { if !$0 && editor == space.id { editor = nil } }
        ), arrowEdge: .bottom) {
            if let current = layout.spaces.first(where: { $0.id == space.id }) {
                spaceEditor(current, metrics)
            }
        }
    }

    private func appIcon(_ rule: WindowRule, size: CGFloat = 32) -> some View {
        let workspace = NSWorkspace.shared
        let icon = workspace.urlForApplication(withBundleIdentifier: rule.bundleID)
            .map { workspace.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
        return Image(nsImage: icon ?? NSImage())
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }

    private func spaceEditor(_ space: SpaceRule, _ metrics: PanelMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(space.title).font(.headline)
                Spacer()
                let index = layout.spaces.firstIndex { $0.id == space.id } ?? 0
                Button { shift(space.id, offset: -1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Переместить влево")
                    .disabled(index == 0)
                Button { shift(space.id, offset: 1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Переместить вправо")
                    .disabled(index + 1 == layout.spaces.count)
            }
            ForEach(space.windows.indices, id: \.self) { index in
                let rule = space.windows[index]
                HStack {
                    appIcon(rule).frame(width: 34, height: 34)
                    Text(rule.name).lineLimit(1).help(rule.name)
                    Spacer()
                    Button {
                        removeWindow(at: index, from: space.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .accessibilityLabel("Убрать \(rule.name)")
                }
                Picker("Режим окна \(rule.name)", selection: Binding(
                    get: { rule.mode },
                    set: { setMode($0, of: index, in: space.id) }
                )) {
                    ForEach(space.windows.count == 1 ? WindowMode.allCases : [.normal, .maximized]) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
            }
            if !space.isFullscreen {
                Button(space.windows.isEmpty ? "Выбрать приложение…" : "Добавить приложение…") {
                    chooseApplication(for: space.id)
                }
            }
        }
        .padding(13)
        .font(.system(size: max(13, metrics.interfaceFontSize)))
        .controlSize(metrics.actionSize > 36 ? .large : .regular)
        .frame(width: metrics.editorWidth)
    }

    private func add() {
        editor = nil
        selection = layout.addDesktop()
    }

    private func remove() {
        guard let selection, let index = layout.spaces.firstIndex(where: { $0.id == selection }) else { return }
        editor = nil
        layout.remove(selection)
        self.selection = layout.spaces.isEmpty ? nil : layout.spaces[min(index, layout.spaces.count - 1)].id
    }

    private func shift(_ id: UUID, offset: Int) {
        guard let index = layout.spaces.firstIndex(where: { $0.id == id }),
              layout.spaces.indices.contains(index + offset) else { return }
        let insertion = offset < 0 ? index - 1 : index + 2
        layout.move([id], before: layout.spaces.indices.contains(insertion) ? layout.spaces[insertion].id : nil)
    }

    private func chooseApplication(for id: UUID) {
        editor = nil
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
        panel.prompt = "Выбрать"
        let profileID = model.library.selectedID
        let complete: @MainActor (NSApplication.ModalResponse) -> Void = { result in
            guard result == .OK, profileID == model.library.selectedID, let url = panel.url,
                  let bundleID = Bundle(url: url)?.bundleIdentifier,
                  let index = layout.spaces.firstIndex(where: { $0.id == id }) else { return }
            guard !layout.spaces.flatMap(\.windows).contains(where: { $0.bundleID == bundleID }) else {
                issue = "Это приложение уже есть в раскладке."
                return
            }
            let name = FileManager.default.displayName(atPath: url.path)
            layout.spaces[index].windows.append(WindowRule(
                bundleID: bundleID, name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name, mode: .normal
            ))
        }
        if let window = NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: complete)
        } else {
            panel.begin(completionHandler: complete)
        }
    }

    private func setMode(_ mode: WindowMode, of window: Int, in id: UUID) {
        guard let index = layout.spaces.firstIndex(where: { $0.id == id }),
              layout.spaces[index].windows.indices.contains(window) else { return }
        if mode != .fullscreen && layout.spaces[index].desktop == nil {
            layout.spaces[index].desktop = layout.nextDesktop
        }
        layout.spaces[index].windows[window].mode = mode
    }

    private func removeWindow(at window: Int, from id: UUID) {
        guard let index = layout.spaces.firstIndex(where: { $0.id == id }),
              layout.spaces[index].windows.indices.contains(window) else { return }
        if layout.spaces[index].desktop == nil { layout.spaces[index].desktop = layout.nextDesktop }
        layout.spaces[index].windows.remove(at: window)
    }
}
