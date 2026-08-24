import SwiftUI

/// Every language the recogniser knows, with the only state that matters here:
/// whether it can run with no network. A picker that offers an online only
/// language is a trap, because the request is forced on device, hears nothing,
/// and every recording comes back reading as silence.
struct TranscriptionLanguageView: View {
    @Environment(AppSettings.self) private var settings
    @State private var states: [String: TranscriptionLocale.Availability] = [:]

    private var locales: [Locale] { TranscriptionLocale.supported() }

    private func grouped(_ wanted: TranscriptionLocale.Availability) -> [Locale] {
        locales.filter { states[TranscriptionLocale.normalise($0.identifier)] == wanted }
    }

    var body: some View {
        List {
            section("Ready", .ready,
                    footer: "Runs entirely on this iPhone.")
            section("Needs install", .needsInstall,
                    footer: "Settings, General, Keyboard, Keyboards, Add New Keyboard, then turn on Enable Dictation and tick the language under Dictation Languages.")
            section("Not usable", .notUsable,
                    footer: "Needs an internet connection. Sovox only transcribes on the device.")
        }
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
        // Re-queried on every appearance. Installing a dictation language does
        // not tell the app anything.
        .onAppear(perform: refresh)
    }

    private func refresh() {
        var next: [String: TranscriptionLocale.Availability] = [:]
        for locale in locales {
            let id = TranscriptionLocale.normalise(locale.identifier)
            next[id] = TranscriptionLocale.availability(id)
        }
        states = next
    }

    @ViewBuilder
    private func section(_ title: String,
                         _ availability: TranscriptionLocale.Availability,
                         footer: String) -> some View {
        let items = grouped(availability)
        if !items.isEmpty {
            Section {
                ForEach(items, id: \.identifier) { locale in
                    row(locale, availability: availability)
                }
            } header: {
                Text("\(title), \(items.count)")
            } footer: {
                Text(footer)
            }
        }
    }

    private func row(_ locale: Locale, availability: TranscriptionLocale.Availability) -> some View {
        let id = TranscriptionLocale.normalise(locale.identifier)
        let selected = TranscriptionLocale.normalise(settings.transcriptionLocale) == id
        return Button {
            guard availability.isSelectable else { return }
            settings.transcriptionLocale = id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(TranscriptionLocale.displayName(locale))
                        .foregroundStyle(availability.isSelectable ? SovoxPalette.ink : SovoxPalette.dim)
                    Text(id)
                        .font(.caption.monospaced())
                        .foregroundStyle(SovoxPalette.dim)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(SovoxPalette.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!availability.isSelectable)
    }
}
