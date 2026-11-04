import XCTest
@testable import Sendoff

/// When the app asks for an App Store rating: once per Sendoff, and not if the screen goes away
/// before the pause is up.
@MainActor
final class ReviewPromptTests: XCTestCase {
    private final class Count { var asks = 0 }

    func testAsksOncePerSendoff() async {
        let id = UUID(), count = Count()
        await ReviewPrompt.ask(about: id, after: .zero) { count.asks += 1 }
        await ReviewPrompt.ask(about: id, after: .zero) { count.asks += 1 }
        XCTAssertEqual(count.asks, 1)
        XCTAssertTrue(ReviewPrompt.wasAsked(about: id))
        XCTAssertFalse(ReviewPrompt.wasAsked(about: UUID()), "another Sendoff can still ask")
    }

    func testLeavingDuringThePauseAsksNextTime() async {
        let id = UUID(), count = Count()
        let leaving = Task { await ReviewPrompt.ask(about: id, after: .seconds(5)) { count.asks += 1 } }
        leaving.cancel()
        await leaving.value
        XCTAssertEqual(count.asks, 0)
        XCTAssertFalse(ReviewPrompt.wasAsked(about: id))
        await ReviewPrompt.ask(about: id, after: .zero) { count.asks += 1 }
        XCTAssertEqual(count.asks, 1)
    }
}
