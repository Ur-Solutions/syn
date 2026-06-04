import SwiftUI

struct CapturePickerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start Recording")
                        .font(.title2)
                        .fontWeight(.semibold)

                    if let lastCaptureMode = appState.lastCaptureMode {
                        Text("Last mode: \(lastCaptureMode.title)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Choose a capture mode")
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    appState.isCapturePickerPresented = false
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(CaptureMode.allCases) { mode in
                    Button {
                        appState.prepareCapture(mode)
                        dismiss()
                    } label: {
                        CaptureModeTile(mode: mode)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Label(appState.microphoneStatusText, systemImage: "mic")
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    appState.showSettingsWindow()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .font(.callout)
        }
        .padding(24)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CaptureModeTile: View {
    let mode: CaptureMode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: mode.systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(mode.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(mode.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        }
    }
}

struct ChromeTabPickerView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Select Chrome Tab")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Google Chrome")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    appState.cancelChromeTabSelection()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }

            if appState.isLoadingChromeTabs {
                ProgressView()
                    .controlSize(.small)
            }

            if let error = appState.chromeTabSelectionError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            if appState.chromeTabCandidates.isEmpty, !appState.isLoadingChromeTabs {
                ContentUnavailableView(
                    "No Chrome Tabs",
                    systemImage: "globe",
                    description: Text("Readable Google Chrome tabs will appear here.")
                )
                .frame(minHeight: 240)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.chromeTabCandidates) { tab in
                            Button {
                                appState.selectChromeTab(tab)
                            } label: {
                                ChromeTabRow(tab: tab)
                            }
                            .buttonStyle(.plain)
                            .disabled(appState.isLoadingChromeTabs)
                        }
                    }
                }
                .frame(minHeight: 260, maxHeight: 430)
            }

            HStack {
                Button {
                    appState.refreshChromeTabs()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(appState.isLoadingChromeTabs)

                Spacer()

                Button("Cancel") {
                    appState.cancelChromeTabSelection()
                }
            }
        }
        .padding(24)
    }
}

private struct ChromeTabRow: View {
    let tab: ChromeTabTarget

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(tab.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                Text(tab.url)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("Window \(tab.windowIndex), Tab \(tab.tabIndex)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        }
    }
}
