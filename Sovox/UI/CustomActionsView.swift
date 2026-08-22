import SwiftUI

struct CustomActionsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var editing: CustomAction?
    @State private var isCreating = false

    var body: some View {
        @Bindable var settings = settings

        ZStack {
            SovoxBackdrop()
            List {
                Section {
                    ForEach(settings.customActions) { action in
                        Button {
                            editing = action
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(action.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(SovoxPalette.ink)
                                    Spacer()
                                    if action.includeByDefault {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(SovoxPalette.accent)
                                    }
                                }
                                Text(action.instruction)
                                    .font(.caption)
                                    .foregroundStyle(SovoxPalette.dim)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .onDelete { offsets in
                        settings.customActions.remove(atOffsets: offsets)
                    }
                    .onMove { source, destination in
                        settings.customActions.move(fromOffsets: source, toOffset: destination)
                    }
                } header: {
                    Text("Your actions, \(settings.customActions.count) of \(CustomActionSanitiser.maxActions)")
                } footer: {
                    Text("These appear as extra checkboxes on the Transcript Ready screen, after the built in ones, in this order.")
                }

                if settings.canAddCustomAction {
                    Section("Add") {
                        Button {
                            isCreating = true
                        } label: {
                            Label("New action", systemImage: "plus")
                        }

                        ForEach(availableTemplates, id: \.name) { template in
                            Button {
                                add(template)
                            } label: {
                                HStack {
                                    Label(template.name, systemImage: "sparkles")
                                    Spacer()
                                    Text("Add").font(.caption).foregroundStyle(SovoxPalette.dim)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Custom actions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(isPresented: $isCreating) {
            CustomActionEditor(existing: nil) { save($0, replacing: nil) }
        }
        .sheet(item: $editing) { action in
            CustomActionEditor(existing: action) { save($0, replacing: action.id) }
        }
    }

    /// A template already added is not offered again, so the list cannot fill up
    /// with duplicates of the same starter.
    private var availableTemplates: [CustomAction] {
        let taken = Set(settings.customActions.map { $0.name.lowercased() })
        return CustomActionTemplate.all.filter { !taken.contains($0.name.lowercased()) }
    }

    private func add(_ template: CustomAction) {
        guard settings.canAddCustomAction else { return }
        settings.customActions.append(CustomAction(name: template.name,
                                                   instruction: template.instruction,
                                                   includeByDefault: false))
    }

    private func save(_ result: CustomActionSanitiser.Result, replacing id: UUID?) {
        if let id, let index = settings.customActions.firstIndex(where: { $0.id == id }) {
            settings.customActions[index] = result.action
        } else if settings.canAddCustomAction {
            settings.customActions.append(result.action)
        }
    }
}

/// Editor. Sanitisation runs here, on save, and what it removed is shown before
/// the sheet closes rather than being applied silently.
struct CustomActionEditor: View {
    var existing: CustomAction?
    var onSave: (CustomActionSanitiser.Result) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var instruction = ""
    @State private var includeByDefault = false
    @State private var report: SanitisationReport?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                SovoxBackdrop()
                Form {
                    Section("Name") {
                        TextField("Shown on the checkbox", text: $name)
                        Text("\(name.count) of \(CustomActionSanitiser.maxNameLength)")
                            .font(.caption)
                            .foregroundStyle(name.count > CustomActionSanitiser.maxNameLength ? SovoxPalette.destructive : SovoxPalette.dim)
                    }

                    Section("Instruction") {
                        TextEditor(text: $instruction)
                            .frame(minHeight: 160)
                            .font(.callout)
                        Text("\(instruction.count) of \(CustomActionSanitiser.maxInstructionLength)")
                            .font(.caption)
                            .foregroundStyle(instruction.count > CustomActionSanitiser.maxInstructionLength ? SovoxPalette.destructive : SovoxPalette.dim)
                    }

                    Section {
                        Toggle("Tick by default", isOn: $includeByDefault)
                    } footer: {
                        Text("Pre ticks this action on the Transcript Ready screen.")
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(existing == nil ? "New action" : "Edit action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { attemptSave() }
                }
            }
            .onAppear {
                guard let existing else { return }
                name = existing.name
                instruction = existing.instruction
                includeByDefault = existing.includeByDefault
            }
            .alert("Could not save", isPresented: Binding(get: { errorMessage != nil },
                                                          set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Saved with changes", isPresented: Binding(get: { report != nil },
                                                              set: { if !$0 { report = nil; dismiss() } })) {
                Button("OK") { report = nil; dismiss() }
            } message: {
                Text(report?.notes.joined(separator: "\n") ?? "")
            }
        }
    }

    private func attemptSave() {
        do {
            let result = try CustomActionSanitiser.sanitise(id: existing?.id ?? UUID(),
                                                            name: name,
                                                            instruction: instruction,
                                                            includeByDefault: includeByDefault)
            onSave(result)
            if result.report.isEmpty {
                dismiss()
            } else {
                report = result.report
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
