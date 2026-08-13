import SwiftUI
import UniformTypeIdentifiers

/// The single entry point for getting audio into the app: drop a file, drop a
/// link, paste a URL, or click to browse.
struct DragDropView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var isDragging = false
    @State private var isHovering = false
    @FocusState private var isURLFieldFocused: Bool

    private var isHighlighted: Bool { isDragging || isHovering }

    /// Only complain once the user has moved on. Flagging an invalid link while
    /// they are still typing it would mark every partially typed URL as wrong.
    private var showsValidationError: Bool {
        !isURLFieldFocused && appViewModel.urlValidation.message != nil
    }

    private var fieldBorderColor: Color {
        if showsValidationError { return .appWarning }
        if isURLFieldFocused { return .appAccent }
        return colorScheme == .dark ? .appBorder : .appBorderLight
    }

    var body: some View {
        ZStack {
            // Background and the click-to-browse target live behind the content,
            // so the URL field on top keeps its own clicks instead of fighting a
            // tap gesture spanning the whole zone.
            backgroundLayers

            VStack(spacing: AppStyle.spacing) {
                icon
                if appViewModel.isLoadingAudioFile {
                    // Reading a file is asynchronous and can take a moment on a
                    // long track, so say so rather than looking idle.
                    loadingState
                } else {
                    headings
                    urlField
                    validationMessage
                    clipboardSuggestion
                    formatChips
                }
            }
            .padding(AppStyle.largeSpacing)
            .opacity(appViewModel.isIngestingMedia && !appViewModel.isLoadingAudioFile ? 0.5 : 1)
        }
        // Refuse further input while a file is being read or a download runs:
        // the zone stays on screen during both, and a second drop would race the
        // first.
        .onDrop(of: [.audio, .fileURL, .url, .plainText], isTargeted: $isDragging) { providers in
            guard !appViewModel.isIngestingMedia else { return false }
            handleDrop(providers: providers)
            return true
        }
        .disabled(appViewModel.isIngestingMedia)
        .onHover { hovering in
            isHovering = hovering && !appViewModel.isIngestingMedia
            if hovering { appViewModel.checkClipboardForURL() }
        }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .padding(.horizontal, 2)
    }

    // MARK: - Layers

    private var backgroundLayers: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppStyle.largeCornerRadius)
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                .fill(isHighlighted ? Color.appAccent : (colorScheme == .dark ? Color.appBorder : Color.appBorderLight))

            RoundedRectangle(cornerRadius: AppStyle.largeCornerRadius)
                .fill(isDragging ? Color.appAccent.opacity(0.05)
                                 : (isHovering ? Color.appAccent.opacity(0.02) : Color.clear))
        }
        .contentShape(RoundedRectangle(cornerRadius: AppStyle.largeCornerRadius))
        .onTapGesture { appViewModel.openFileDialog() }
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(
                    colors: [Color.appPrimary, Color.appPrimary.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 64, height: 64)

            Image(systemName: "music.note.list")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    private var loadingState: some View {
        VStack(spacing: AppStyle.smallSpacing) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
            Text("Reading audio file...")
                .font(.system(size: AppStyle.headingFontSize, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)
            Text("Just a moment")
                .font(.system(size: AppStyle.bodyFontSize))
                .foregroundColor(colorScheme == .dark ? .appTextSecondary : .appTextSecondaryLight)
        }
    }

    private var headings: some View {
        VStack(spacing: 4) {
            Text("Drop an audio file or a link here")
                .font(.system(size: AppStyle.headingFontSize, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .appText : .appTextLight)

            Text("or paste a URL below — or click to browse")
                .font(.system(size: AppStyle.bodyFontSize))
                .foregroundColor(colorScheme == .dark ? .appTextSecondary : .appTextSecondaryLight)
        }
    }

    // MARK: - URL entry

    private var urlField: some View {
        HStack(spacing: AppStyle.smallSpacing) {
            Image(systemName: "link")
                .foregroundColor(.appAccentSecondary)

            TextField("Paste a video URL", text: $appViewModel.downloadURLString)
                .textFieldStyle(.plain)
                .font(.system(size: AppStyle.bodyFontSize))
                .focused($isURLFieldFocused)
                .disabled(appViewModel.downloadState.isActive)
                .onSubmit {
                    if appViewModel.canStartDownload { appViewModel.startDownload() }
                }

            if !appViewModel.downloadURLString.isEmpty && !appViewModel.downloadState.isActive {
                Button {
                    appViewModel.downloadURLString = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.appTextTertiary)
                }
                .buttonStyle(.plain)
                .hoverHighlight(cornerRadius: 10, padding: 2)
                .help("Clear")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.smallCornerRadius)
                .fill(colorScheme == .dark ? Color.appSurfaceLight : Color.appSurfaceLightLight)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppStyle.smallCornerRadius)
                .stroke(fieldBorderColor, lineWidth: isURLFieldFocused || showsValidationError ? 2 : 1)
        )
        // A plain TextField only occupies its text, so clicks on the surrounding
        // padding would otherwise fall through to the browse gesture behind it.
        .contentShape(Rectangle())
        .onTapGesture { isURLFieldFocused = true }
        .cursor(.iBeam)
        .frame(maxWidth: 460)
    }

    @ViewBuilder
    private var validationMessage: some View {
        if showsValidationError, let message = appViewModel.urlValidation.message {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: AppStyle.captionFontSize))
                Text(message)
                    .font(.system(size: AppStyle.captionFontSize))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundColor(.appWarning)
            .frame(maxWidth: 460, alignment: .leading)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var clipboardSuggestion: some View {
        if let suggestion = appViewModel.clipboardSuggestion {
            HStack(spacing: AppStyle.smallSpacing) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: AppStyle.captionFontSize))
                    .foregroundColor(.appAccentSecondary)

                Text(suggestion)
                    .font(.system(size: AppStyle.captionFontSize))
                    .foregroundColor(.appTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Button("Use") { appViewModel.acceptClipboardSuggestion() }
                    .buttonStyle(.glass(compact: true))

                Button {
                    appViewModel.dismissClipboardSuggestion()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: AppStyle.captionFontSize, weight: .semibold))
                        .foregroundColor(.appTextTertiary)
                }
                .buttonStyle(.plain)
                .hoverHighlight(padding: 3)
                .help("Dismiss")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: AppStyle.smallCornerRadius)
                    .fill(Color.appAccentSecondary.opacity(0.08))
            )
            .frame(maxWidth: 460)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var formatChips: some View {
        HStack(spacing: 12) {
            ForEach(["WAV", "MP3", "M4A", "AIFF", "FLAC"], id: \.self) { format in
                Text(format)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .appTextTertiary : .appTextSecondaryLight)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(colorScheme == .dark ? Color.appSurfaceLight : Color.appSurfaceLightLight)
                    )
            }
        }
    }

    // MARK: - Drop handling

    private func handleDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }

        // A dropped web link arrives as .url or plain text; a dropped file as
        // .audio or .fileURL. Both surface as URLs, so route on the scheme.
        if provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
            load(provider, typeIdentifier: UTType.audio.identifier)
        } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            load(provider, typeIdentifier: UTType.fileURL.identifier)
        } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            load(provider, typeIdentifier: UTType.url.identifier)
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                var text: String?
                if let data = item as? Data { text = String(data: data, encoding: .utf8) }
                if let string = item as? String { text = string }
                guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let url = URL(string: trimmed) else { return }
                DispatchQueue.main.async { self.appViewModel.acceptDroppedURL(url) }
            }
        }
    }

    private func load(_ provider: NSItemProvider, typeIdentifier: String) {
        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
            guard let url = self.extractURL(from: item) else { return }
            DispatchQueue.main.async {
                if url.isFileURL {
                    self.appViewModel.loadAudioFile(url: url)
                } else {
                    self.appViewModel.acceptDroppedURL(url)
                }
            }
        }
    }

    private func extractURL(from item: NSSecureCoding?) -> URL? {
        if let data = item as? Data,
           let url = URL(dataRepresentation: data, relativeTo: nil) {
            return url
        } else if let url = item as? URL {
            return url
        }
        return nil
    }
}
