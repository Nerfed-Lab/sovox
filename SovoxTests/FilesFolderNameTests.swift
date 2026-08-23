import XCTest
@testable import Sovox

/// The app tells the user which folder to pick in the Shortcuts editor and in
/// the Files app. iOS names that folder from CFBundleDisplayName, so the two
/// have to agree. They did not: the display name became "Sovox Notes" and
/// every instruction still said "Sovox", which sent the user looking for a
/// folder that does not exist.
final class FilesFolderNameTests: XCTestCase {

    private var displayName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? ""
    }

    func testFolderNameMatchesTheDisplayNameFilesActuallyUses() {
        XCTAssertFalse(displayName.isEmpty, "CFBundleDisplayName is what names the folder, it cannot be blank")
        XCTAssertEqual(RecordingPaths.filesFolderName, displayName)
    }

    func testFilesLocationIsPhrasedForInstructionText() {
        XCTAssertEqual(RecordingPaths.filesLocation, "On My iPhone, \(displayName)")
    }

    func testEveryBridgeStepPointsAtTheRealFolder() {
        for destination in AIDestination.allCases {
            let steps = BridgeShortcutRecipe.steps(for: destination)
            let mentioning = steps.filter { $0.contains(RecordingPaths.filesLocation) }
            XCTAssertEqual(mentioning.count, 2, "the get step and the save step must both name the real folder")
        }
    }

    /// Guards the exact regression. Every "On My iPhone," in the instructions
    /// must be followed by the folder Files actually shows, so a future rename
    /// cannot leave the text pointing at a folder that does not exist.
    func testEveryFolderReferenceNamesTheLiveDisplayName() {
        let prefix = "On My iPhone, "
        for destination in AIDestination.allCases {
            for step in BridgeShortcutRecipe.steps(for: destination) {
                var cursor = step.startIndex
                while let found = step.range(of: prefix, range: cursor..<step.endIndex) {
                    let remainder = step[found.upperBound...]
                    XCTAssertTrue(remainder.hasPrefix(RecordingPaths.filesFolderName),
                                  "folder reference does not match \(RecordingPaths.filesFolderName) in: \(step)")
                    cursor = found.upperBound
                }
            }
        }
    }

    func testShortcutNamesCarryNothingThatCanBeMangled() {
        // This used to require a plain hyphen. On device, iOS smart punctuation
        // turned the hyphen the user typed into an en dash, the name matched
        // nothing, and the app blamed a missing shortcut. A name with no
        // punctuation at all cannot be mangled by anything.
        for destination in AIDestination.allCases {
            let name = BridgeShortcutRecipe.name(for: destination)
            XCTAssertFalse(name.contains("-"), "\(name) still has a hyphen")
            XCTAssertFalse(name.contains(" "), "\(name) still has a space")
            XCTAssertFalse(name.contains("\u{2013}"), "\(name) contains an en dash")
            XCTAssertFalse(name.contains("\u{2014}"), "\(name) contains an em dash")
            XCTAssertTrue(name.allSatisfy { $0.isASCII && $0.isLetter }, "\(name) is not letters only")
        }
    }
}
