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

    func testWeekdayResponsibilityCreatesRealRecurrence() async throws {
        let parser = RuleBasedBrainDumpParser()
        let result = try await parser.parse(
            "laundry every Monday",
            context: BrainDumpContext(today: Date(timeIntervalSince1970: 1_800_000_000))
        )

        let suggestion = try XCTUnwrap(result.suggestions.first)
        XCTAssertEqual(suggestion.type, .recurringResponsibility)
        XCTAssertEqual(suggestion.recurrence, .weekly(weekday: 2))
        XCTAssertNotNil(suggestion.dueDate)
    }

    func testBareWeekdayCreatesOneOffDueDate() async throws {
        let parser = RuleBasedBrainDumpParser()
        let result = try await parser.parse(
            "appointment on Monday",
            context: BrainDumpContext(today: Date(timeIntervalSince1970: 1_800_000_000))
        )

        let suggestion = try XCTUnwrap(result.suggestions.first)
        XCTAssertEqual(suggestion.type, .reminder)
        XCTAssertEqual(suggestion.recurrence, .none)
        XCTAssertNotNil(suggestion.dueDate)
    }

    func testSafetyLanguageDoesNotBecomeNormalTasks() async throws {
        let parser = RuleBasedBrainDumpParser()
        let result = try await parser.parse("I am afraid of my partner and they threatened me", context: BrainDumpContext())

        XCTAssertTrue(result.suggestions.isEmpty)
        XCTAssertNotNil(result.safetyNotice)
    }

    func testCommonCrisisAndAbuseLanguageDoesNotBecomeNormalTasks() async throws {
        let parser = RuleBasedBrainDumpParser()
        let phrases = [
            "I want to die",
            "There is domestic violence at home",
            "My partner choked me",
            "I'm scared to go home",
            "They won't let me leave"
        ]

        for phrase in phrases {
            let result = try await parser.parse(phrase, context: BrainDumpContext())
            XCTAssertTrue(result.suggestions.isEmpty, phrase)
            XCTAssertNotNil(result.safetyNotice, phrase)
        }
    }

    func testFoundationParserFallsBackDeterministicallyForOrdinaryInput() async throws {
        let parser = FoundationModelsBrainDumpParser()
        let result = try await parser.parse("remember appointment tomorrow", context: BrainDumpContext())

        XCTAssertFalse(result.suggestions.isEmpty)
        XCTAssertTrue([ParserSource.ruleBased, ParserSource.foundationModels].contains(result.source))
    }
}
