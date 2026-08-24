import SwiftUI

/// Every language the recogniser knows, with the only state that matters here:
/// whether it can run with no network. A picker that offers an online only
/// language is a trap, because the request is forced on device, hears nothing,
/// and every recording comes back reading as silence.
struct TranscriptionLanguageView: View {
    enum Slot { case primary, secondary }
    var selecting: Slot = .primary

    @Environment(AppSettings.self) private var settings
    @State private var states: [String: TranscriptionLocale.Availability] = [:]
    @State private var installing: String?

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
        .sheet(item: Binding(get: { installing.map { LocaleBox(id: $0) } },
                             set: { installing = $0?.id })) { box in
            LanguageInstallView(identifier: box.id) { chosen in
                switch selecting {
                case .primary: settings.transcriptionLocale = chosen
                case .secondary: settings.secondaryLocale = chosen
                }
                installing = nil
                refresh()
            }
        }
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
        let current = selecting == .primary ? settings.transcriptionLocale : settings.secondaryLocale
        let selected = TranscriptionLocale.normalise(current) == id
        return Button {
            guard availability.isSelectable else { return }
            // Needs install is selectable, but the steps come first: choosing it
            // silently would produce nothing until the asset arrives.
            if availability == .needsInstall { installing = id; return }
            switch selecting {
            case .primary: settings.transcriptionLocale = id
            case .secondary: settings.secondaryLocale = id
            }
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

/// Identifiable wrapper so a locale identifier can drive a sheet.
struct LocaleBox: Identifiable, Equatable { var id: String }
