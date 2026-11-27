// test-research.swift
// Created 2026-11-27 · Claude Code
// Checks the research-study schedule without Swift Package Manager or XCTest.

import Foundation

@main
struct ResearchStudyTestRunner {
    static func main() {
        var failures: [String] = []
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
        }
        func check(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }
        func localMinute(_ date: Date) -> Int {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return parts.hour! * 60 + parts.minute!
        }

        // 1. Full days: N prompts per day, all inside the window, spaced apart.
        let started = date(2026, 12, 1, 8)
        let study = ResearchStudy(startedAt: started, days: 14, promptsPerDay: 4,
                                  windowStartMinute: 10 * 60, windowEndMinute: 23 * 60, timeZone: zone)
        let all = study.allPrompts()
        check(all.count == 56, "14 full days × 4 prompts = 56, got \(all.count)")
        check(all == all.sorted { $0.date < $1.date }, "prompts are in time order")
        check(all.allSatisfy { (10 * 60...23 * 60).contains(localMinute($0.date)) }, "every prompt is inside 10:00–23:00")
        let minimumGap = zip(all, all.dropFirst()).map { $1.date.timeIntervalSince($0.date) }.min() ?? 0
        check(minimumGap >= 0.2 * (13 * 3600 / 4) - 60, "prompts are at least a fifth of a block apart, got \(minimumGap / 60) min")
        check(Set(all.map(\.key)).count == all.count, "prompt keys are unique")
        check(all.first?.day == 1 && all.last?.day == 14, "days are numbered 1…14")

        // 2. Deterministic per study, different between studies.
        let again = ResearchStudy(id: study.id, startedAt: started, days: 14, promptsPerDay: 4,
                                  windowStartMinute: 10 * 60, windowEndMinute: 23 * 60, timeZone: zone)
        check(again.allPrompts() == all, "the same study id reproduces the same schedule")
        let other = ResearchStudy(startedAt: started, days: 14, promptsPerDay: 4, timeZone: zone)
        check(other.allPrompts().map(\.date) != all.map(\.date), "a new study gets a new schedule")

        // 3. Starting mid-window drops earlier slots that day; through(date) is bounded.
        let late = ResearchStudy(startedAt: date(2026, 12, 1, 18), days: 3, promptsPerDay: 4,
                                 windowStartMinute: 10 * 60, windowEndMinute: 23 * 60, timeZone: zone)
        check(late.allPrompts().allSatisfy { $0.date >= late.startedAt }, "no prompt before the start time")
        check(late.allPrompts().count < 12, "a late start yields fewer prompts on day 1")
        check(late.prompts(through: date(2026, 12, 1, 17)).isEmpty, "nothing is due before the start")
        check(late.dayNumber(at: date(2026, 12, 3, 12)) == 3 && late.dayNumber(at: date(2026, 12, 4, 12)) == nil,
              "day numbers stop after the last day")

        // 4. A manual stop ends sampling.
        var stopped = study
        stopped.stoppedAt = date(2026, 12, 3, 0)
        check(stopped.allPrompts().allSatisfy { $0.date < stopped.stoppedAt! }, "no prompt after a manual stop")
        check(!stopped.isActive(at: date(2026, 12, 4, 12)), "a stopped study is inactive")

        // 5. The daylight-saving change keeps wall-clock windows.
        let dst = ResearchStudy(startedAt: date(2026, 10, 31, 6), days: 3, promptsPerDay: 6,
                                windowStartMinute: 9 * 60, windowEndMinute: 24 * 60, timeZone: zone)
        check(dst.allPrompts().count == 18, "3 days × 6 prompts across the DST change")
        check(dst.allPrompts().allSatisfy { localMinute($0.date) >= 9 * 60 }, "DST-day prompts stay after 09:00 local")

        // 6. Bounds and round trip.
        let clamped = ResearchStudy(startedAt: started, days: 100, promptsPerDay: 0,
                                    windowStartMinute: 23 * 60, windowEndMinute: 60, timeZone: zone)
        check(clamped.days == 28 && clamped.promptsPerDay == 2, "days and prompts are clamped")
        check(clamped.windowEndMinute - clamped.windowStartMinute >= 120, "the window keeps at least two hours")
        do {
            let data = try JSONEncoder().encode(stopped)
            let decoded = try JSONDecoder().decode(ResearchStudy.self, from: data)
            check(decoded == stopped && decoded.allPrompts() == stopped.allPrompts(), "a study round-trips through JSON")
        } catch {
            failures.append("study encoding threw \(error)")
        }

        if failures.isEmpty {
            print("ResearchStudy checks passed: 6 test groups")
        } else {
            print("ResearchStudy checks failed: \(failures.count) assertion(s)")
            for failure in failures { print("FAIL: \(failure)") }
            exit(1)
        }
    }
}
