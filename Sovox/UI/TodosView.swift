import SwiftUI

struct TodosView: View {
    @Environment(RecordingStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(HandoffCoordinator.self) private var handoff
    @State private var todos = TodoStore.shared
    @State private var showCompleted = false
    @State private var editing: TodoItem?
    @State private var isCreating = false
    @State private var review: TodoReview?
    @State private var message: String?
    /// Captured when Refresh is tapped. Recomputing this at callback time let a
    /// recording that finished transcribing during the round trip be marked
    /// ingested without ever having been in the prompt, losing its to-dos for
    /// good since there is no way to rewind the watermark.
    @State private var sentSourceIDs: [String] = []

    var body: some View {
        NavigationStack {
            ZStack {
                SovoxBackdrop()
                List {
                    Section {
                        if todos.open.isEmpty {
                            Text("Nothing open.").foregroundStyle(SovoxPalette.dim)
                        }
                        ForEach(todos.open) { todo in
                            row(todo)
                        }
                    } header: {
                        Text("Open, \(todos.openCount) of \(TodoPolicy.maxOpen)")
                    }

                    Section(isExpanded: $showCompleted) {
                        ForEach(todos.completed) { todo in
                            row(todo)
                        }
                    } header: {
                        Text("Completed, \(todos.completed.count)")
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("To-dos")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { isCreating = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") { refresh() }
                        .disabled(handoff.isInFlight)
                }
            }
            .navigationDestination(item: $editing) { todo in
                TodoDetailView(todo: todo)
            }
            .sheet(isPresented: $isCreating) {
                TodoEditor(existing: nil) { todos.add($0) }
            }
            .sheet(item: $review) { pending in
                TodoReviewSheet(review: pending) { accepted in
                    todos.apply(accepted, sources: store.sessions.filter { pending.sourceIDs.contains($0.id) })
                    // The watermark advances only now, after the review has
                    // actually completed.
                    todos.advanceWatermark(with: pending.sourceIDs)
                    review = nil
                }
            }
            .alert("To-dos", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
            .onChange(of: handoff.pendingTodoResponse) { _, _ in
                guard let raw = handoff.consumeTodoResponse() else { return }
                receive(raw)
            }
        }
    }

    private func row(_ todo: TodoItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                todos.toggleDone(todo.id)
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.isDone ? SovoxPalette.accent : SovoxPalette.dim)
            }
            .buttonStyle(.plain)

            Button {
                editing = todo
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(todo.text)
                        .foregroundStyle(SovoxPalette.ink)
                        .strikethrough(todo.isDone)
                    HStack(spacing: 6) {
                        Text(todo.priority.title).foregroundStyle(tint(todo.priority))
                        if let source = todo.sourceRecordingTitle {
                            Text(source).foregroundStyle(SovoxPalette.dim).lineLimit(1)
                        }
                        if todo.origin == .manual {
                            Text("manual").foregroundStyle(SovoxPalette.dim)
                        }
                    }
                    .font(.caption)
                }
            }
            .buttonStyle(.plain)
        }
        .swipeActions {
            Button(role: .destructive) { todos.delete(todo.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func tint(_ priority: TodoPriority) -> Color {
        switch priority {
        case .high: return SovoxPalette.pauseAmber
        case .medium: return SovoxPalette.dim
        case .low: return SovoxPalette.dim
        }
    }

    // MARK: Refresh

    private func refresh() {
        let sources = todos.pendingSources(from: store.sessions)
        guard !sources.isEmpty else {
            message = "No new recordings since last refresh."
            return
        }
        sentSourceIDs = sources.map(\.id)
        let prompt = TodoPromptBuilder.build(open: todos.open, sources: sources)
        handoff.refreshTodos(prompt: prompt, destination: settings.destination)
    }

    private func receive(_ raw: String) {
        let consumed = sentSourceIDs
        let parsed = TodoOperationParser.parse(raw, knownIDs: todos.items.map(\.id))

        if parsed.isNone {
            todos.advanceWatermark(with: consumed)
            message = "Nothing new to propose."
            return
        }

        let split = TodoPolicy.rejectingManualTargets(parsed.operations, items: todos.items)
        guard !split.kept.isEmpty else {
            message = "The model proposed nothing that can be applied."
            return
        }
        review = TodoReview(operations: split.kept,
                            blocked: split.blocked,
                            unparsed: parsed.unparsedLines,
                            openCount: todos.openCount,
                            sourceIDs: consumed)
    }
}

struct TodoReview: Identifiable {
    let id = UUID()
    var operations: [TodoOperation]
    var blocked: [TodoOperation]
    var unparsed: [String]
    var openCount: Int
    var sourceIDs: [String]
}

/// Nothing changes without approval. Accepting past the cap is refused rather
/// than silently dropping the overflow.
struct TodoReviewSheet: View {
    var review: TodoReview
    var onAccept: ([TodoOperation]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var accepted: Set<String> = []

    private var acceptedOps: [TodoOperation] {
        review.operations.filter { accepted.contains($0.id) }
    }

    private var overflow: Int {
        let adds = acceptedOps.filter { if case .add = $0 { return true }; return false }.count
        let dones = acceptedOps.filter { if case .done = $0 { return true }; return false }.count
        return TodoPolicy.overflow(openCount: review.openCount, acceptedAdds: adds, acceptedDones: dones)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SovoxBackdrop()
                List {
                    Section("Proposed") {
                        ForEach(review.operations) { operation in
                            Button {
                                if accepted.contains(operation.id) { accepted.remove(operation.id) }
                                else { accepted.insert(operation.id) }
                            } label: {
                                HStack(alignment: .top) {
                                    Image(systemName: accepted.contains(operation.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(accepted.contains(operation.id) ? SovoxPalette.accent : SovoxPalette.dim)
                                    Text(operation.summary).foregroundStyle(SovoxPalette.ink)
                                }
                            }
                        }
                    }

                    if overflow > 0 {
                        Section {
                            Label("\(overflow) over the \(TodoPolicy.maxOpen) item cap. Complete or delete something first, or accept fewer.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(SovoxPalette.destructive)
                        }
                    }

                    if !review.blocked.isEmpty {
                        Section("Not offered") {
                            Text("\(review.blocked.count) operation\(review.blocked.count == 1 ? "" : "s") targeted a to-do you created by hand. Manual items are never merged or auto completed.")
                                .font(.footnote)
                                .foregroundStyle(SovoxPalette.dim)
                        }
                    }

                    if !review.unparsed.isEmpty {
                        Section("Ignored lines") {
                            ForEach(review.unparsed, id: \.self) { line in
                                Text(line).font(.caption.monospaced()).foregroundStyle(SovoxPalette.dim)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reject all") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Accept all") { accepted = Set(review.operations.map(\.id)) }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Apply \(acceptedOps.count)") {
                        onAccept(acceptedOps)
                        dismiss()
                    }
                    .disabled(acceptedOps.isEmpty || overflow > 0)
                }
            }
        }
    }
}

struct TodoDetailView: View {
    var todo: TodoItem
    @Environment(RecordingStore.self) private var store

    var body: some View {
        ZStack {
            SovoxBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(todo.text).font(.title3.weight(.semibold))

                    LabeledContent("Priority", value: todo.priority.title)
                    LabeledContent("Created", value: todo.createdAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Origin", value: todo.origin == .ai ? "From a recording" : "Added by you")

                    if let title = todo.sourceRecordingTitle {
                        if let session = todo.source(in: store.sessions) {
                            NavigationLink {
                                HistoryDetailView(sessionID: session.id)
                            } label: {
                                Label(title, systemImage: "waveform")
                            }
                        } else {
                            Label(title, systemImage: "waveform").foregroundStyle(SovoxPalette.dim)
                        }
                    }

                    if !todo.contextExcerpt.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Context").font(.headline)
                            Text(todo.contextExcerpt)
                                .font(.callout)
                                .foregroundStyle(SovoxPalette.dim)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(cornerRadius: 18)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("To-do")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TodoEditor: View {
    var existing: TodoItem?
    var onSave: (TodoItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var priority: TodoPriority = .medium

    var body: some View {
        NavigationStack {
            ZStack {
                SovoxBackdrop()
                Form {
                    Section("What needs doing") {
                        TextField("Short and actionable", text: $text, axis: .vertical)
                            .lineLimit(1...4)
                    }
                    Section("Priority") {
                        Picker("Priority", selection: $priority) {
                            ForEach(TodoPriority.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(existing == nil ? "New to-do" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        var item = existing ?? TodoItem(text: "", origin: .manual)
                        item.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        item.priority = priority
                        guard !item.text.isEmpty else { return }
                        onSave(item)
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard let existing else { return }
                text = existing.text
                priority = existing.priority
            }
        }
    }
}
