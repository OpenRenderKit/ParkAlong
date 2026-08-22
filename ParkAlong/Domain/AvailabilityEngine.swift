import Foundation

enum AvailabilityEngine {
    static let trustCutoff: TimeInterval = 24 * 60 * 60

    static func group(readings: [SensorReading], now: Date) -> [Int: AvailabilityStats] {
        var buckets: [Int: (available: Int, total: Int, newest: Date)] = [:]
        for reading in readings {
            guard let zone = reading.zoneNumber,
                  reading.status != .unknown,
                  now.timeIntervalSince(reading.timestamp) <= trustCutoff else { continue }
            var bucket = buckets[zone] ?? (0, 0, .distantPast)
            bucket.total += 1
            if reading.status == .unoccupied { bucket.available += 1 }
            bucket.newest = max(bucket.newest, reading.timestamp)
            buckets[zone] = bucket
        }
        return buckets.mapValues { AvailabilityStats(available: $0.available, total: $0.total, newestTimestamp: $0.newest) }
    }

    static func group(aggregates: [SensorAggregateRow], now: Date) -> [Int: AvailabilityStats] {
        var buckets: [Int: (available: Int, total: Int, newest: Date)] = [:]
        for row in aggregates where row.status != .unknown && now.timeIntervalSince(row.newestTimestamp) <= trustCutoff {
            var bucket = buckets[row.zoneNumber] ?? (0, 0, .distantPast)
            bucket.total += row.bayCount
            if row.status == .unoccupied { bucket.available += row.bayCount }
            bucket.newest = max(bucket.newest, row.newestTimestamp)
            buckets[row.zoneNumber] = bucket
        }
        return buckets.mapValues { AvailabilityStats(available: $0.available, total: $0.total, newestTimestamp: $0.newest) }
    }
}

