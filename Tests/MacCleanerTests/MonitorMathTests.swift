import XCTest
@testable import MacCleaner

final class MonitorMathTests: XCTestCase {
    func testCounterResetDoesNotCreateWrappingDelta() {
        XCTAssertEqual(MonitorMath.counterDelta(current: 12, previous: 4_000_000_000), 0)
    }

    func testCounterIncreaseProducesExpectedDelta() {
        XCTAssertEqual(MonitorMath.counterDelta(current: 1_500, previous: 1_000), 500)
    }

    func testRateRejectsInvalidElapsedTime() {
        XCTAssertEqual(MonitorMath.bytesPerSecond(delta: 100, elapsed: 0), 0)
        XCTAssertEqual(MonitorMath.bytesPerSecond(delta: 100, elapsed: .nan), 0)
    }

    func testDisplayConversionRejectsNonFiniteValues() {
        XCTAssertEqual(MonitorMath.displayBytes(.infinity), 0)
        XCTAssertEqual(MonitorMath.displayBytes(.nan), 0)
        XCTAssertEqual(MonitorMath.displayBytes(-1), 0)
    }
}
