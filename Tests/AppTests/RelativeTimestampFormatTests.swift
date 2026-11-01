@testable import CrossPost
import XCTest

@MainActor
final class RelativeTimestampFormatTests: XCTestCase {
    private let format: RelativeTimestampFormat = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return RelativeTimestampFormat(locale: Locale(identifier: "en_US"), calendar: calendar)
    }()

    /// 2026-11-01 12:00:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_793_534_400)

    private func compact(ago seconds: TimeInterval) -> String {
        format.compact(now.addingTimeInterval(-seconds), relativeTo: now)
    }

    func testCompactBucketsAtEachBoundary() {
        let cases: [(TimeInterval, String)] = [
            (-30, "now"),
            (0, "now"),
            (59, "now"),
            (60, "1m"),
            (59 * 60 + 59, "59m"),
            (3600, "1h"),
            (23 * 3600 + 59 * 60, "23h"),
            (86400, "1d"),
            (6 * 86400 + 23 * 3600, "6d"),
            (7 * 86400, "Oct 25")
        ]
        for (seconds, expected) in cases {
            XCTAssertEqual(compact(ago: seconds), expected, "\(seconds)s ago")
        }
    }

    func testOlderDatesShowTheYearOnlyOutsideTheCurrentYear() {
        let january = Date(timeIntervalSince1970: 1_767_268_800) // 2026-01-01 12:00 UTC
        let lastYear = Date(timeIntervalSince1970: 1_767_182_400) // 2025-12-31 12:00 UTC
        XCTAssertEqual(format.compact(january, relativeTo: now), "Jan 1")
        XCTAssertEqual(format.compact(lastYear, relativeTo: now), "Dec 31, 2025")
    }

    func testSpokenLabelUsesFullWords() {
        XCTAssertEqual(format.spoken(now.addingTimeInterval(-30), relativeTo: now), "now")
        XCTAssertEqual(format.spoken(now.addingTimeInterval(-13 * 3600), relativeTo: now), "13 hours ago")
        XCTAssertEqual(format.spoken(now.addingTimeInterval(-3 * 86400), relativeTo: now), "3 days ago")
        XCTAssertEqual(format.spoken(now.addingTimeInterval(-8 * 86400), relativeTo: now), "October 24, 2026")
    }

    /// A day-old interval can span two calendar days, so the spoken label states the
    /// elapsed days like the visible "1d" rather than naming a day ("yesterday").
    func testSpokenDaysCountElapsedTimeAcrossMidnight() {
        let wednesdayOneAM = Date(timeIntervalSince1970: 1_793_754_000) // 2026-11-04 01:00 UTC
        let mondayElevenPM = wednesdayOneAM.addingTimeInterval(-26 * 3600) // 2026-11-02 23:00 UTC
        XCTAssertEqual(format.compact(mondayElevenPM, relativeTo: wednesdayOneAM), "1d")
        XCTAssertEqual(format.spoken(mondayElevenPM, relativeTo: wednesdayOneAM), "1 day ago")
        XCTAssertEqual(format.spoken(now.addingTimeInterval(-86400), relativeTo: now), "1 day ago")
    }
}
