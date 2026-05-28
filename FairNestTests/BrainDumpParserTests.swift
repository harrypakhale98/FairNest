import XCTest
@testable import FairNest

final class BrainDumpParserTests: XCTestCase {
    func testRuleBasedParserCreatesReviewableCards() async throws {
        let parser = RuleBasedBrainDumpParser()
        let result = try await parser.parse(
            "laundry every Sunday. decide grocery budget. thank partner for dishes",
            context: BrainDumpContext(today: Date(timeIntervalSince1970: 1_800_000_000))
        )

        XCTAssertNil(result.safetyNotice)
        XCTAssertEqual(result.source, .ruleBased)
        XCTAssertTrue(result.suggestions.contains { $0.type == .recurringResponsibility })
        XCTAssertTrue(result.suggestions.contains { $0.type == .decision })
        XCTAssertTrue(result.suggestions.contains { $0.type == .appreciation })
        XCTAssertTrue(result.suggestions.allSatisfy { !$0.title.isEmpty })
    }

    func testSafetyLanguageDoesNotBecomeNormalTasks() async throws {
        let parser = RuleBasedBrainDumpParser()
        let result = try await parser.parse("I am afraid of my partner and they threatened me", context: BrainDumpContext())

        XCTAssertTrue(result.suggestions.isEmpty)
        XCTAssertNotNil(result.safetyNotice)
    }

    func testFoundationParserFallsBackDeterministicallyForOrdinaryInput() async throws {
        let parser = FoundationModelsBrainDumpParser()
        let result = try await parser.parse("remember appointment tomorrow", context: BrainDumpContext())

        XCTAssertFalse(result.suggestions.isEmpty)
        XCTAssertTrue([ParserSource.ruleBased, ParserSource.foundationModels].contains(result.source))
    }
}
