import Foundation

/// Descriptive, on-device summaries of saved observations. Counts use the
/// time an entry was recorded in PD Bridge; occurrence time remains available
/// for the event history and is never silently substituted here.
enum ObservationAnalyticsService {
    enum BucketSize: String, CaseIterable, Identifiable {
        case day
        case week
        case month

        var id: String { rawValue }

        var calendarComponent: Calendar.Component {
            switch self {
            case .day: return .day
            case .week: return .weekOfYear
            case .month: return .month
            }
        }

        var title: String {
            switch self {
            case .day: return "Daily"
            case .week: return "Weekly"
            case .month: return "Monthly"
            }
        }
    }

    struct Bucket: Equatable, Identifiable {
        let start: Date
        let total: Int
        let freezing: Int
        let tremor: Int

        var id: Date { start }
    }

    struct KindCount: Equatable, Identifiable {
        let kind: Observation.Kind
        let count: Int

        var id: String { kind.rawValue }
    }

    struct SourceCount: Equatable, Identifiable {
        let source: Observation.Origin
        let count: Int

        var id: String { source.rawValue }
    }

    struct HourCount: Equatable, Identifiable {
        let hour: Int
        let count: Int

        var id: Int { hour }
    }

    struct FallRecord: Equatable, Identifiable {
        let id: UUID
        let kind: Observation.Kind
        let occurredAt: Date
        let recordedAt: Date
        let source: Observation.Origin
        let confirmation: Observation.Confirmation
    }

    struct Snapshot: Equatable {
        let dateRange: DateInterval
        let uniqueEntryCount: Int
        let pendingReviewCount: Int
        let confirmedCount: Int
        let kindCounts: [KindCount]
        let sourceCounts: [SourceCount]
        let hourlyCounts: [HourCount]
        let fallHistory: [FallRecord]
        let dailyTotals: [Bucket]
        let weeklyTotals: [Bucket]
        let monthlyTotals: [Bucket]

        var fallCount: Int { count(for: .fall) }
        var nearFallCount: Int { count(for: .nearFall) }
        var freezingCount: Int { count(for: .freezing) }
        var tremorCount: Int { count(for: .tremor) }

        func count(for kind: Observation.Kind) -> Int {
            kindCounts.first(where: { $0.kind == kind })?.count ?? 0
        }

        func totals(for bucketSize: BucketSize) -> [Bucket] {
            switch bucketSize {
            case .day: return dailyTotals
            case .week: return weeklyTotals
            case .month: return monthlyTotals
            }
        }
    }

    /// Uses a half-open interval [start, end), de-duplicates by observation ID,
    /// and counts each retained record exactly once. A duplicate identifier
    /// uses the first payload in the supplied archive order, matching the
    /// archive's existing stable ordering.
    static func snapshot(
        observations: [Observation],
        in dateRange: DateInterval,
        calendar: Calendar = .current
    ) -> Snapshot {
        let unique = uniqueByID(observations)
        let selected = unique.filter {
            $0.recordedAt >= dateRange.start && $0.recordedAt < dateRange.end
        }

        let kinds = Observation.Kind.allCases.map { kind in
            KindCount(kind: kind, count: selected.filter { $0.kind == kind }.count)
        }
        let sources = Observation.Origin.allCases.map { source in
            SourceCount(source: source, count: selected.filter { $0.origin == source }.count)
        }
        let hours = (0..<24).map { hour in
            HourCount(hour: hour, count: selected.filter {
                calendar.component(.hour, from: $0.recordedAt) == hour
            }.count)
        }
        let falls = selected
            .filter { $0.kind == .fall || $0.kind == .nearFall }
            .sorted {
                if $0.recordedAt != $1.recordedAt { return $0.recordedAt > $1.recordedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            .map {
                FallRecord(id: $0.id, kind: $0.kind, occurredAt: $0.occurredAt,
                           recordedAt: $0.recordedAt, source: $0.origin,
                           confirmation: $0.confirmation)
            }

        return Snapshot(
            dateRange: dateRange,
            uniqueEntryCount: selected.count,
            pendingReviewCount: selected.filter { $0.confirmation == .pendingReview }.count,
            confirmedCount: selected.filter { $0.confirmation == .userConfirmed }.count,
            kindCounts: kinds,
            sourceCounts: sources,
            hourlyCounts: hours,
            fallHistory: falls,
            dailyTotals: bucketed(selected, in: dateRange, component: .day, calendar: calendar),
            weeklyTotals: bucketed(selected, in: dateRange, component: .weekOfYear, calendar: calendar),
            monthlyTotals: bucketed(selected, in: dateRange, component: .month, calendar: calendar)
        )
    }

    private static func uniqueByID(_ observations: [Observation]) -> [Observation] {
        var seen = Set<UUID>()
        return observations.filter { seen.insert($0.id).inserted }
    }

    private static func bucketed(
        _ observations: [Observation],
        in dateRange: DateInterval,
        component: Calendar.Component,
        calendar: Calendar
    ) -> [Bucket] {
        guard dateRange.start < dateRange.end,
              var cursor = calendar.dateInterval(of: component, for: dateRange.start)?.start else {
            return []
        }

        var totals: [Date: (total: Int, freezing: Int, tremor: Int)] = [:]
        for item in observations {
            guard let interval = calendar.dateInterval(of: component, for: item.recordedAt) else { continue }
            var value = totals[interval.start, default: (0, 0, 0)]
            value.total += 1
            if item.kind == .freezing { value.freezing += 1 }
            if item.kind == .tremor { value.tremor += 1 }
            totals[interval.start] = value
        }

        var buckets: [Bucket] = []
        var safetyLimit = 0
        while cursor < dateRange.end && safetyLimit < 20_000 {
            let value = totals[cursor, default: (0, 0, 0)]
            buckets.append(Bucket(start: cursor, total: value.total,
                                  freezing: value.freezing, tremor: value.tremor))
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor), next > cursor else { break }
            cursor = next
            safetyLimit += 1
        }
        return buckets
    }
}

/// Shared, testable filtering rules for the History timeline. Date presets are
/// based on local calendar days and the saved/receipt timestamp, never on an
/// imported event's occurrence time.
enum ObservationHistoryQuery {
    enum Status: String, CaseIterable, Identifiable {
        case all
        case needsReview
        case confirmed

        var id: String { rawValue }
    }

    enum DateWindow: String, CaseIterable, Identifiable {
        case allTime
        case sevenDays
        case thirtyDays
        case ninetyDays

        var id: String { rawValue }

        var dayCount: Int? {
            switch self {
            case .allTime: return nil
            case .sevenDays: return 7
            case .thirtyDays: return 30
            case .ninetyDays: return 90
            }
        }
    }

    static func filter(
        _ observations: [Observation],
        query: String = "",
        status: Status = .all,
        kind: Observation.Kind? = nil,
        source: Observation.Origin? = nil,
        dateWindow: DateWindow = .allTime,
        now: Date = Date(),
        calendar: Calendar = .current,
        kindLabel: (Observation.Kind) -> String = { $0.rawValue },
        sourceLabel: (Observation.Origin) -> String = { $0.rawValue }
    ) -> [Observation] {
        let dateStart = dateWindow.dayCount.flatMap { days in
            calendar.date(byAdding: .day, value: 1 - days, to: calendar.startOfDay(for: now))
        }

        return observations.filter { item in
            let statusMatches = status == .all
                || (status == .needsReview && item.confirmation == .pendingReview)
                || (status == .confirmed && item.confirmation == .userConfirmed)
            let kindMatches = kind == nil || item.kind == kind
            let sourceMatches = source == nil || item.origin == source
            let dateMatches = item.recordedAt <= now && (dateStart.map { item.recordedAt >= $0 } ?? true)
            let textMatches = ObservationSearch.matches(
                item,
                query: query,
                kindLabel: kindLabel(item.kind),
                sourceLabel: sourceLabel(item.origin)
            )
            return statusMatches && kindMatches && sourceMatches && dateMatches && textMatches
        }
        .sorted {
            if $0.recordedAt != $1.recordedAt { return $0.recordedAt > $1.recordedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
