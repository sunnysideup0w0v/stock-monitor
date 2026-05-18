import XCTest
@testable import StockWatch

/// ScreenerEngine 및 ScreenerCondition 동작 검증.
/// stock_universe 테이블 데이터가 없어도 동작하는 케이스, 모델 속성 불변량 확인.
final class ScreenerEngineTests: XCTestCase {

    // MARK: - ScreenerCondition 속성 불변량

    func test_usesStringValue_trueForStringTypes() {
        XCTAssertTrue(ScreenerCondition.ConditionType.sectorFilter.usesStringValue)
        XCTAssertTrue(ScreenerCondition.ConditionType.marketFilter.usesStringValue)
        XCTAssertTrue(ScreenerCondition.ConditionType.instrumentType.usesStringValue)
    }

    func test_usesStringValue_falseForNumericTypes() {
        let numericTypes: [ScreenerCondition.ConditionType] = [
            .priceRange, .volumeMin, .changeRateRange, .perRange, .pbrRange, .marketCapRange
        ]
        for type in numericTypes {
            XCTAssertFalse(type.usesStringValue, "\(type.rawValue)은 usesStringValue=false여야 함")
        }
    }

    func test_supportsMin_falseForStringOnlyTypes() {
        XCTAssertFalse(ScreenerCondition.ConditionType.sectorFilter.supportsMin)
        XCTAssertFalse(ScreenerCondition.ConditionType.marketFilter.supportsMin)
        XCTAssertFalse(ScreenerCondition.ConditionType.instrumentType.supportsMin)
    }

    func test_supportsMax_falseForVolumeAndStringTypes() {
        XCTAssertFalse(ScreenerCondition.ConditionType.volumeMin.supportsMax)
        XCTAssertFalse(ScreenerCondition.ConditionType.sectorFilter.supportsMax)
        XCTAssertFalse(ScreenerCondition.ConditionType.marketFilter.supportsMax)
        XCTAssertFalse(ScreenerCondition.ConditionType.instrumentType.supportsMax)
    }

    func test_supportsMin_trueForNumericRangeTypes() {
        let types: [ScreenerCondition.ConditionType] = [
            .priceRange, .volumeMin, .changeRateRange, .perRange, .pbrRange, .marketCapRange
        ]
        for type in types {
            XCTAssertTrue(type.supportsMin, "\(type.rawValue)은 supportsMin=true여야 함")
        }
    }

    // MARK: - Codable 직렬화

    func test_screenerCondition_codableRoundtrip() throws {
        let original = ScreenerCondition(
            type: .priceRange,
            isEnabled: true,
            minValue: 10_000,
            maxValue: 100_000,
            stringValue: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScreenerCondition.self, from: data)

        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.isEnabled, original.isEnabled)
        XCTAssertEqual(decoded.minValue, original.minValue)
        XCTAssertEqual(decoded.maxValue, original.maxValue)
    }

    func test_screenerCondition_codable_withStringValue() throws {
        let original = ScreenerCondition(
            type: .sectorFilter,
            isEnabled: true,
            minValue: nil,
            maxValue: nil,
            stringValue: "반도체,IT"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScreenerCondition.self, from: data)
        XCTAssertEqual(decoded.stringValue, "반도체,IT")
    }

    func test_screenerCondition_codable_preservesDisabledState() throws {
        let original = ScreenerCondition(type: .volumeMin, isEnabled: false, minValue: 50_000)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScreenerCondition.self, from: data)
        XCTAssertFalse(decoded.isEnabled)
    }

    // MARK: - ScreenerEngine.run (stock_universe 비어있어도 에러 없음)

    func test_screenerEngine_run_emptyConditions_doesNotThrow() {
        XCTAssertNoThrow(try ScreenerEngine.shared.run(conditions: []))
    }

    func test_screenerEngine_run_allDisabledConditions_doesNotThrow() {
        let conditions = [
            ScreenerCondition(type: .priceRange, isEnabled: false, minValue: 1000),
            ScreenerCondition(type: .volumeMin, isEnabled: false, minValue: 100_000)
        ]
        XCTAssertNoThrow(try ScreenerEngine.shared.run(conditions: conditions))
    }

    func test_screenerEngine_run_disabledConditions_treatedAsNoFilter() throws {
        let disabled = ScreenerCondition(type: .priceRange, isEnabled: false, minValue: 999_999_999)
        let enabled  = ScreenerCondition(type: .priceRange, isEnabled: true,  minValue: 999_999_999)

        let resultDisabled = try ScreenerEngine.shared.run(conditions: [disabled])
        let resultEnabled  = try ScreenerEngine.shared.run(conditions: [enabled])

        // 비활성 조건은 극단적 필터가 있어도 모든 항목 반환
        // 활성 극단 조건은 대부분의 항목을 필터링
        XCTAssertGreaterThanOrEqual(resultDisabled.count, resultEnabled.count,
                                    "비활성 조건은 필터 적용 안 됨 → 결과 수 >= 활성 조건")
    }

    func test_screenerEngine_run_extremePriceMax_returnsEmpty() throws {
        // 현재가 최대 1원 → 거의 결과 없음
        let cond = ScreenerCondition(type: .priceRange, isEnabled: true, maxValue: 1)
        let result = try ScreenerEngine.shared.run(conditions: [cond])
        // stock_universe가 비어있거나 1원 이하 종목 없으면 빈 배열
        XCTAssertTrue(result.isEmpty || result.allSatisfy { $0.close <= 1 })
    }

    func test_screenerEngine_availableSectors_doesNotThrow() {
        XCTAssertNoThrow(try ScreenerEngine.shared.availableSectors())
    }

    func test_screenerEngine_availableMarkets_doesNotThrow() {
        XCTAssertNoThrow(try ScreenerEngine.shared.availableMarkets())
    }

    // MARK: - ConditionType 전체 케이스 망라 (exhaustive switch 안전망)

    func test_allConditionTypes_haveDisplayName() {
        for type in ScreenerCondition.ConditionType.allCases {
            XCTAssertFalse(type.displayName.isEmpty, "\(type.rawValue) displayName 비어있음")
        }
    }

    func test_allConditionTypes_haveShortName() {
        for type in ScreenerCondition.ConditionType.allCases {
            XCTAssertFalse(type.shortName.isEmpty, "\(type.rawValue) shortName 비어있음")
        }
    }

    // MARK: - ConditionType.instrumentType — ETF/일반주 필터

    func test_instrumentType_singleValue_etf() throws {
        let cond = ScreenerCondition(type: .instrumentType, isEnabled: true, stringValue: "ETF")
        let result = try ScreenerEngine.shared.run(conditions: [cond])
        XCTAssertTrue(result.allSatisfy { $0.isEtf }, "ETF 필터는 isEtf=true 종목만 반환해야 함")
    }

    func test_instrumentType_singleValue_stock() throws {
        let cond = ScreenerCondition(type: .instrumentType, isEnabled: true, stringValue: "주식")
        let result = try ScreenerEngine.shared.run(conditions: [cond])
        XCTAssertTrue(result.allSatisfy { !$0.isEtf }, "주식 필터는 isEtf=false 종목만 반환해야 함")
    }

    func test_instrumentType_bothValues_returnsAll() throws {
        let cond = ScreenerCondition(type: .instrumentType, isEnabled: true, stringValue: "ETF,주식")
        let result = try ScreenerEngine.shared.run(conditions: [cond])
        let allResult = try ScreenerEngine.shared.run(conditions: [])
        // 두 값이면 필터 없음 → 전체 결과와 같아야 함
        XCTAssertEqual(result.count, allResult.count)
    }
}
