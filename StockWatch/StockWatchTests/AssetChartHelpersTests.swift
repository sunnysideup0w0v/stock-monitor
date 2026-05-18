import XCTest
@testable import StockWatch

/// AssetChartView의 Y축 포맷터(fmtShort)와 눈금 단계 계산(niceStep)을 검증한다.
/// fmtShort는 v13 버전에서 1억 단위 중복 레이블 버그를 수정했다.
/// SwiftUI 렌더링 없이 순수 계산 경로만 테스트한다.
final class AssetChartHelpersTests: XCTestCase {

    private let view = AssetChartView()

    // MARK: - fmtShort: 기본 범위

    func test_fmtShort_zero() {
        // 0은 fmt() 경로 → 기본 포맷터 통과, "0" 반환
        XCTAssertEqual(view.fmtShort(0), "0")
    }

    func test_fmtShort_exactly1Man() {
        XCTAssertEqual(view.fmtShort(10_000), "1만")
    }

    func test_fmtShort_below1Man_noManSuffix() {
        // 1만 미만은 만 단위 없이 그대로 반환
        let result = view.fmtShort(9_999)
        XCTAssertFalse(result.contains("만"), "9999는 만 단위 표기 없이 반환돼야 함")
    }

    func test_fmtShort_5000Man() {
        XCTAssertEqual(view.fmtShort(50_000_000), "5000만")
    }

    func test_fmtShort_9900Man() {
        XCTAssertEqual(view.fmtShort(99_000_000), "9900만")
    }

    // MARK: - fmtShort: 1억 경계 (버그 수정 검증)

    func test_fmtShort_exactly1Eok() {
        XCTAssertEqual(view.fmtShort(100_000_000), "1억")
    }

    func test_fmtShort_1Eok500Man() {
        // 버그 수정 핵심 케이스: 이전 구현(absV / 100_000_000)이 나머지를 버려
        // 105_000_000 → 1억으로 잘못 표기됐던 문제를 검증
        XCTAssertEqual(view.fmtShort(105_000_000), "1억500만")
    }

    func test_fmtShort_1Eok1000Man() {
        XCTAssertEqual(view.fmtShort(110_000_000), "1억1000만")
    }

    func test_fmtShort_1Eok2500Man() {
        XCTAssertEqual(view.fmtShort(125_000_000), "1억2500만")
    }

    func test_fmtShort_2Eok() {
        XCTAssertEqual(view.fmtShort(200_000_000), "2억")
    }

    func test_fmtShort_2Eok500Man() {
        XCTAssertEqual(view.fmtShort(205_000_000), "2억500만")
    }

    // MARK: - fmtShort: 음수

    func test_fmtShort_negative5000Man() {
        XCTAssertEqual(view.fmtShort(-50_000_000), "-5000만")
    }

    func test_fmtShort_negativeExactly1Eok() {
        XCTAssertEqual(view.fmtShort(-100_000_000), "-1억")
    }

    func test_fmtShort_negative1Eok500Man() {
        XCTAssertEqual(view.fmtShort(-105_000_000), "-1억500만")
    }

    // MARK: - niceStep

    func test_niceStep_zero_returns1() {
        XCTAssertEqual(view.niceStep(0), 1.0)
    }

    func test_niceStep_negative_returns1() {
        XCTAssertEqual(view.niceStep(-100), 1.0)
    }

    func test_niceStep_1_2_roundsTo1() {
        // f=1.2 < 1.5 → 1 × mag
        XCTAssertEqual(view.niceStep(1.2), 1.0, accuracy: 1e-10)
    }

    func test_niceStep_2_0_stays2() {
        // f=2.0, 1.5 ≤ f < 3.5 → 2 × mag
        XCTAssertEqual(view.niceStep(2.0), 2.0, accuracy: 1e-10)
    }

    func test_niceStep_5_0_stays5() {
        // f=5.0, 3.5 ≤ f < 7.5 → 5 × mag
        XCTAssertEqual(view.niceStep(5.0), 5.0, accuracy: 1e-10)
    }

    func test_niceStep_8_0_roundsTo10() {
        // f=8.0 ≥ 7.5 → 10 × mag
        XCTAssertEqual(view.niceStep(8.0), 10.0, accuracy: 1e-10)
    }

    func test_niceStep_1200_roundsTo1000() {
        // mag=1000, f=1.2 < 1.5 → 1000
        XCTAssertEqual(view.niceStep(1_200), 1_000.0, accuracy: 1e-7)
    }

    func test_niceStep_2500_roundsTo2000() {
        // mag=1000, f=2.5, 1.5 ≤ f < 3.5 → 2000
        XCTAssertEqual(view.niceStep(2_500), 2_000.0, accuracy: 1e-7)
    }

    func test_niceStep_50000_stays50000() {
        // mag=10000, f=5.0, 3.5 ≤ f < 7.5 → 50000
        XCTAssertEqual(view.niceStep(50_000), 50_000.0, accuracy: 1e-6)
    }

    func test_niceStep_typicalMasterStep_100Man() {
        // 1회 intraday 변동폭 40만 → niceStep(40만/4) = niceStep(10만) = 10만 (f=1.0 < 1.5)
        XCTAssertEqual(view.niceStep(100_000), 100_000.0, accuracy: 1e-5)
    }

    func test_niceStep_typicalMasterStep_250Man() {
        // intraday 변동폭 / 4 = 250만 → niceStep(250만) → mag=100만, f=2.5 → 200만
        XCTAssertEqual(view.niceStep(2_500_000), 2_000_000.0, accuracy: 1.0)
    }
}
