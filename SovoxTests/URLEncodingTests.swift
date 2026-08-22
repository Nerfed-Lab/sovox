import XCTest
@testable import Sovox

final class URLEncodingTests: XCTestCase {

    private func roundTrip(_ value: String, file: StaticString = #filePath, line: UInt = #line) {
        let encoded = URLEncoding.encode(value)
        XCTAssertEqual(URLEncoding.decode(encoded), value, file: file, line: line)
    }

    func testReservedCharactersAreEscaped() {
        let expected = ["&": "%26", "#": "%23", "+": "%2B", "=": "%3D", "?": "%3F",
                        "%": "%25", "/": "%2F", ":": "%3A", " ": "%20", "@": "%40",
                        ";": "%3B", ",": "%2C", "$": "%24"]
        for (character, escape) in expected {
            let encoded = URLEncoding.encode(character)
            XCTAssertEqual(encoded, escape, "\(character) encoded as \(encoded)")
            XCTAssertNotEqual(encoded, character)
        }
    }

    func testUnreservedCharactersAreNotEscaped() {
        let unreserved = "abcXYZ019-._~"
        XCTAssertEqual(URLEncoding.encode(unreserved), unreserved)
    }

    func testBodyWithEveryTroublesomeCharacterRoundTrips() {
        roundTrip("a&b#c+d=e?f%g/h:i j")
    }

    func testNewlinesRoundTrip() {
        roundTrip("line one\nline two\r\nline three")
    }

    func testEmojiRoundTrips() {
        roundTrip("shipped it 🚀 and 👍🏽 too")
    }

    func testNonASCIINamesRoundTrip() {
        roundTrip("Zoë Müller, José Álvarez, 田中太郎")
    }

    func testNonASCIIIsActuallyPercentEncodedAndNotPassedThrough() {
        // .urlQueryAllowed would leave these letters intact and produce an
        // unusable URL string. The explicit unreserved set must not.
        XCTAssertEqual(URLEncoding.encode("é"), "%C3%A9")
        XCTAssertFalse(URLEncoding.encode("Zoë").contains("ë"))
    }

    func testFullOutlookURLKeepsTheWholeBody() {
        let body = "Decisions: ship & hold\nOwner = Tom? yes #1 100%"
        let url = URLEncoding.url(scheme: "ms-outlook",
                                  path: "compose",
                                  parameters: [("to", "a@b.com"), ("subject", "S | T"), ("body", body)])
        let string = try! XCTUnwrap(url).absoluteString
        let bodyPart = String(string.split(separator: "body=").last!)
        XCTAssertEqual(URLEncoding.decode(bodyPart), body)
    }

    func testShortcutNameWithSpacesAndHyphenEncodesCorrectly() {
        XCTAssertEqual(URLEncoding.encode("Sovox Bridge - ChatGPT"),
                       "Sovox%20Bridge%20-%20ChatGPT")
    }

    func testCallbackURLsSurviveEncoding() {
        let url = URLEncoding.url(scheme: "shortcuts",
                                  path: "x-callback-url/run-shortcut",
                                  parameters: [("name", "Sovox Bridge - ChatGPT"),
                                               ("x-success", "sovox://done"),
                                               ("x-error", "sovox://failed")])
        let string = try! XCTUnwrap(url).absoluteString
        XCTAssertTrue(string.contains("name=Sovox%20Bridge%20-%20ChatGPT"))
        XCTAssertTrue(string.contains("x-success=sovox%3A%2F%2Fdone"))
        XCTAssertEqual(string.filter { $0 == "?" }.count, 1)
    }
}
