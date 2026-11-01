import AVFoundation
import MusicKit
import SwiftUI

/// Finds a song in Apple Music for the reveal. Searching the catalog needs the organizer's
/// permission to use Apple Music, not a subscription; tapping a result plays Apple's preview so
/// they can hear it before choosing.
struct SongPicker: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    var onPick: (LinkedSong) -> Void

    @State private var status = MusicAuthorization.currentStatus
    @State private var query = ""
    @State private var results: [Song] = []
    @State private var searching = false
    @State private var failed = false
    @State private var preview: AVPlayer?
    @State private var previewing: MusicItemID?

    var body: some View {
        NavigationStack {
            ZStack {
                Paper()
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "Apple Music")
                    Text("A song for\nwhen it opens.")
                        .font(Typeface.display(34)).displayTracking(34)
                        .foregroundStyle(theme.inkColor)
                        .padding(.top, 8)
                    content.padding(.top, 20)
                }
                .padding(.horizontal, 20)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
        }
        .tint(theme.inkColor)
        .task { if status == .notDetermined { status = await MusicAuthorization.request() } }
        .task(id: query) { await search() }
        .onDisappear { preview?.pause() }
    }

    @ViewBuilder private var content: some View {
        switch status {
        case .authorized:
            VStack(alignment: .leading, spacing: 0) {
                Field(label: "Song or artist", text: $query, placeholder: "Here Comes the Sun")
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if failed {
                    Text("Apple Music didn\u{2019}t answer. Check your connection and try again.")
                        .font(Typeface.caption).foregroundStyle(theme.mutedInkColor).padding(.top, 16)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { song in
                            row(song)
                            Rule()
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .padding(.top, 12)
                Text("Apple Music subscribers hear the whole song. Everyone else hears a 30-second preview.")
                    .font(Typeface.caption).foregroundStyle(theme.faintInkColor)
                    .padding(.vertical, 12)
            }
        case .notDetermined:
            ProgressView().tint(theme.faintInkColor).frame(maxWidth: .infinity).padding(.top, 40)
        default:
            VStack(alignment: .leading, spacing: 14) {
                Text("Sendoff needs your permission to search Apple Music. You can turn it on in Settings.")
                    .font(Typeface.body).foregroundStyle(theme.mutedInkColor)
                SecondaryButton(title: "Open Settings", systemImage: "gear", fill: false) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            Spacer()
        }
    }

    private func row(_ song: Song) -> some View {
        HStack(spacing: 14) {
            Button { togglePreview(song) } label: {
                ZStack {
                    if let art = song.artwork {
                        ArtworkImage(art, width: 52, height: 52)
                    } else {
                        theme.raisedPaperColor
                    }
                    if song.previewAssets?.first?.url != nil {
                        Image(systemName: previewing == song.id ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(previewing == song.id ? "Stop preview" : "Play preview")
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(Typeface.bodyStrong).foregroundStyle(theme.inkColor).lineLimit(1)
                Text(song.artistName).font(Typeface.caption).foregroundStyle(theme.faintInkColor).lineLimit(1)
            }
            Spacer()
            Button("Choose") {
                preview?.pause()
                onPick(LinkedSong(id: song.id.rawValue, title: song.title, artist: song.artistName))
                dismiss()
            }
            .font(Typeface.caption.weight(.semibold))
            .foregroundStyle(theme.inkColor)
        }
        .padding(.vertical, 10)
    }

    private func search() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard status == .authorized, term.count >= 2 else { results = []; return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
        request.limit = 25
        do {
            results = Array(try await request.response().songs)
            failed = false
        } catch {
            failed = !Task.isCancelled
        }
    }

    private func togglePreview(_ song: Song) {
        if previewing == song.id { preview?.pause(); previewing = nil; return }
        guard let url = song.previewAssets?.first?.url else { return }
        ForegroundMedia.activateSession()
        let p = AVPlayer(url: url)
        preview?.pause()
        preview = p
        previewing = song.id
        p.play()
    }
}
