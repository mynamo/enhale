import XCTest
@testable import EnhaleCore

/// Guards the seam between the Swift client and the FastAPI backend: a sample
/// `ParsedMeal` payload exactly as the backend emits it (snake_case keys,
/// ISO-8601 dates) must decode cleanly into the Swift model. If the backend
/// contract changes, this fails — the whole point of pinning it in a test now
/// that parsing lives in a separate codebase.
final class ContractDecodingTests: XCTestCase {

    /// Mirrors `EnhaleAPIClient`'s decoder configuration.
    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func testDecodesBackendParsedMealPayload() throws {
        // Shape produced by GET/POST on the backend (see backend/tests/test_api.py).
        let json = """
        {
          "id": "1B9D6BCD-BBFD-4B2D-9B5D-AB8DFBBD4BED",
          "items": [
            {
              "id": "2B9D6BCD-BBFD-4B2D-9B5D-AB8DFBBD4BED",
              "name": "scrambled eggs",
              "quantity": "two",
              "calories": 180,
              "protein_grams": 12,
              "carb_grams": 2,
              "fat_grams": 13,
              "estimated": true
            }
          ],
          "meal_type": "breakfast",
          "eaten_at": "2026-07-19T08:30:00Z",
          "raw_transcript": "two scrambled eggs",
          "confidence": 0.9
        }
        """.data(using: .utf8)!

        let meal = try makeDecoder().decode(ParsedMeal.self, from: json)

        XCTAssertEqual(meal.mealType, .breakfast)
        XCTAssertEqual(meal.rawTranscript, "two scrambled eggs")
        XCTAssertEqual(meal.confidence, 0.9, accuracy: 0.0001)
        XCTAssertEqual(meal.items.count, 1)

        let item = try XCTUnwrap(meal.items.first)
        XCTAssertEqual(item.name, "scrambled eggs")
        XCTAssertEqual(item.proteinGrams, 12)
        XCTAssertEqual(item.carbGrams, 2)
        XCTAssertEqual(item.fatGrams, 13)
        XCTAssertEqual(meal.totalCalories, 180)
    }
}
