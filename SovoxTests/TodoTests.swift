import XCTest
@testable import Sovox

/// Phase 9. E27 to E30.
final class TodoTests: XCTestCase {

    private func item(_ text: String, origin: TodoOrigin = .ai, done: Bool = false,
                      priority: TodoPriority = .medium) -> TodoItem {
        TodoItem(text: text, priority: priority, isDone: done, origin: origin)
    }

    // MARK: Parsing

    func testParsesEachOperationForm() {
        let ai = item("existing")
        let raw = """
        ADD | Finalise Q3 pricing model | high | Budget call | We agreed pricing needs a rework. Tom will own it.
        MERGE | \(ai.id.uuidString) | Combined text | duplicate of new item
        DONE | \(ai.id.uuidString) | shipped last week
        """
        let result = TodoOperationParser.parse(raw, knownIDs: [ai.id])
        XCTAssertEqual(result.operations.count, 3)
        XCTAssertTrue(result.unparsedLines.isEmpty)
        XCTAssertFalse(result.isNone)
    }

    func testNoneIsRecognisedExactly() {
        let result = TodoOperationParser.parse("NONE", knownIDs: [])
        XCTAssertTrue(result.isNone)
        XCTAssertTrue(result.operations.isEmpty)
    }

    func testAddsAreCappedAtFivePerRefresh() {
        let lines = (1...8).map { "ADD | item \($0) | low | Call | context here" }.joined(separator: "\n")
        let result = TodoOperationParser.parse(lines, knownIDs: [])
        XCTAssertEqual(result.operations.count, 5)
        XCTAssertEqual(result.unparsedLines.count, 3)
    }

    func testOperationsTargetingUnknownIDsAreDroppedNotGuessed() {
        let raw = "DONE | \(UUID().uuidString) | done\nMERGE | not-a-uuid | text | reason"
        let result = TodoOperationParser.parse(raw, knownIDs: [])
        XCTAssertTrue(result.operations.isEmpty)
        XCTAssertEqual(result.unparsedLines.count, 2)
    }

    func testMalformedLinesAreReportedRatherThanSilentlyIgnored() {
        let result = TodoOperationParser.parse("something the model made up", knownIDs: [])
        XCTAssertTrue(result.operations.isEmpty)
        XCTAssertEqual(result.unparsedLines, ["something the model made up"])
    }

    // MARK: E28, manual to-dos are untouchable

    func testManualItemsCanNeverBeMergedOrAutoCompleted() {
        let manual = item("mine", origin: .manual)
        let ai = item("theirs", origin: .ai)
        let operations: [TodoOperation] = [
            .merge(id: manual.id, text: "x", reason: "r"),
            .done(id: manual.id, reason: "r"),
            .merge(id: ai.id, text: "y", reason: "r"),
            .add(text: "new", priority: .low, sourceTitle: "Call", context: "c")
        ]
        let split = TodoPolicy.rejectingManualTargets(operations, items: [manual, ai])
        XCTAssertEqual(split.blocked.count, 2)
        XCTAssertEqual(split.kept.count, 2)
    }

    @MainActor
    func testApplyIgnoresOperationsAimedAtManualItemsEvenIfTheySlipThrough() {
        let store = TodoStore.shared
        let manual = item("protected", origin: .manual)
        store.add(manual)
        defer { store.delete(manual.id) }

        store.apply([.done(id: manual.id, reason: "should not apply"),
                     .merge(id: manual.id, text: "rewritten", reason: "should not apply")])

        let after = store.item(id: manual.id)
        XCTAssertEqual(after?.text, "protected")
        XCTAssertEqual(after?.isDone, false)
    }

    // MARK: E30, the cap

    func testOverflowIsReportedRatherThanSilentlyDropping() {
        XCTAssertEqual(TodoPolicy.overflow(openCount: 8, acceptedAdds: 2, acceptedDones: 0), 0)
        XCTAssertEqual(TodoPolicy.overflow(openCount: 9, acceptedAdds: 3, acceptedDones: 0), 2)
        XCTAssertEqual(TodoPolicy.overflow(openCount: 10, acceptedAdds: 2, acceptedDones: 2), 0)
        XCTAssertEqual(TodoPolicy.maxOpen, 10)
    }

    // MARK: E29, the watermark

    @MainActor
    func testPendingSourcesExcludeAlreadyIngestedAndUntranscribedRecordings() {
        let store = TodoStore.shared
        var withText = RecordingSession(id: "a", startDate: Date())
        withText.source = .pasted
        withText.transcript = "hello"
        let empty = RecordingSession(id: "b", startDate: Date())

        let pending = store.pendingSources(from: [withText, empty])
        XCTAssertEqual(pending.map(\.id), ["a"], "only transcribed, not yet ingested recordings qualify")
    }

    @MainActor
    func testWatermarkOnlyMovesWhenExplicitlyAdvanced() {
        let store = TodoStore.shared
        let id = "watermark-probe-\(UUID().uuidString)"
        var session = RecordingSession(id: id, startDate: Date())
        session.source = .pasted
        session.transcript = "text"

        XCTAssertTrue(store.pendingSources(from: [session]).contains { $0.id == id })
        store.advanceWatermark(with: [id])
        XCTAssertFalse(store.pendingSources(from: [session]).contains { $0.id == id },
                       "an advanced watermark must exclude the recording")
    }

    // MARK: Prompt

    func testPromptCarriesTheOperationContractAndTheNoneEscape() {
        let text = TodoPromptBuilder.build(open: [], sources: [])
        XCTAssertTrue(text.contains("EXISTING OPEN TO-DOS:\nnone"))
        XCTAssertTrue(text.contains("ADD | <text> | <high|medium|low>"))
        XCTAssertTrue(text.contains("Maximum 5 ADD operations per refresh."))
        XCTAssertTrue(text.contains("Never infer completion from absence of mention."))
        XCTAssertTrue(text.contains("return exactly: NONE"))
    }

    func testOpenItemsAreListedWithTheirIDsSoMergeAndDoneCanTargetThem() {
        let one = item("first", priority: .high)
        let text = TodoPromptBuilder.build(open: [one], sources: [])
        XCTAssertTrue(text.contains(one.id.uuidString))
        XCTAssertTrue(text.contains("first"))
        XCTAssertTrue(text.contains("high"))
    }

    // MARK: Ordering

    @MainActor
    func testOpenItemsAreOrderedByPriority() {
        let store = TodoStore.shared
        let low = item("low", priority: .low)
        let high = item("high", priority: .high)
        store.add(low); store.add(high)
        defer { store.delete(low.id); store.delete(high.id) }
        let ordered = store.open.filter { $0.id == low.id || $0.id == high.id }
        XCTAssertEqual(ordered.first?.id, high.id)
    }
}

/// The list of recordings that went into a refresh lived in view state, and the
/// reply did too. Both are lost if the app is killed during the round trip,
/// which leaves the app entirely.
@MainActor
final class TodoRefreshDurabilityTests: XCTestCase {

    private let responseKey = "sovox.handoff.strandedTodos"
    private let sourcesKey = "sovox.handoff.todoSources"

    private func clear() {
        UserDefaults.standard.removeObject(forKey: responseKey)
        UserDefaults.standard.removeObject(forKey: sourcesKey)
    }

    func testAReplyThatArrivedBeforeTheTabExistedIsStillDelivered() {
        clear()
        defer { clear() }
        // What a relaunch looks like: nothing in memory, the record on disk.
        UserDefaults.standard.set("ADD | finalise pricing | high | Budget call | ctx", forKey: responseKey)
        UserDefaults.standard.set(["sovox-1", "sovox-2"], forKey: sourcesKey)

        let result = HandoffCoordinator.shared.consumeTodoResponse()
        XCTAssertEqual(result?.sourceIDs, ["sovox-1", "sovox-2"],
                       "the watermark has to advance against the set that was actually sent")
        XCTAssertTrue(result?.raw.hasPrefix("ADD |") ?? false)
    }

    func testConsumingClearsBothHalves() {
        clear()
        defer { clear() }
        UserDefaults.standard.set("NONE", forKey: responseKey)
        UserDefaults.standard.set(["sovox-1"], forKey: sourcesKey)

        _ = HandoffCoordinator.shared.consumeTodoResponse()
        XCTAssertNil(HandoffCoordinator.shared.consumeTodoResponse(), "a reply is delivered once")
        XCTAssertNil(UserDefaults.standard.string(forKey: responseKey))
        XCTAssertNil(UserDefaults.standard.stringArray(forKey: sourcesKey))
    }

    func testNothingWaitingReturnsNil() {
        clear()
        XCTAssertNil(HandoffCoordinator.shared.consumeTodoResponse())
    }

    func testAnEmptyReplyIsNotTreatedAsAReply() {
        clear()
        defer { clear() }
        UserDefaults.standard.set("", forKey: responseKey)
        XCTAssertNil(HandoffCoordinator.shared.consumeTodoResponse())
    }
}
