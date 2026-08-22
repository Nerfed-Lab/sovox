import Foundation

/// Free space policy. Pure arithmetic so the boundaries are unit testable.
enum StorageGuard {
    /// Refuse to begin a recording under one gigabyte.
    static let minimumStartBytes: Int64 = 1_073_741_824
    /// Stop cleanly once free space falls under three hundred megabytes.
    static let criticalBytes: Int64 = 314_572_800
    /// Warn in the Live Activity a little before the hard stop.
    static let warningBytes: Int64 = 524_288_000
    /// 64 kbps mono AAC, which is 8000 bytes per second, about 28.8 MB per hour.
    static let bytesPerSecond: Int64 = 8_000

    static func canStart(freeBytes: Int64) -> Bool {
        freeBytes >= minimumStartBytes
    }

    static func mustStop(freeBytes: Int64) -> Bool {
        freeBytes < criticalBytes
    }

    static func shouldWarn(freeBytes: Int64) -> Bool {
        freeBytes < warningBytes && freeBytes >= criticalBytes
    }

    /// Minutes still recordable before the hard stop threshold is reached.
    static func recordableMinutes(freeBytes: Int64) -> Int {
        let usable = freeBytes - criticalBytes
        guard usable > 0 else { return 0 }
        return Int(usable / (bytesPerSecond * 60))
    }

    static func estimatedBytes(forSeconds seconds: TimeInterval) -> Int64 {
        Int64(max(0, seconds)) * bytesPerSecond
    }

    /// Live figure for the volume backing the given directory.
    /// volumeAvailableCapacityForImportantUsage is the value that accounts for
    /// purgeable space, which is what the system will actually let us write.
    static func freeBytes(at url: URL) -> Int64 {
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let important = values.volumeAvailableCapacityForImportantUsage {
                return Int64(important)
            }
        } catch {
            // Fall through to the coarse figure below.
        }
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: url.path),
           let free = attrs[.systemFreeSize] as? NSNumber {
            return free.int64Value
        }
        return 0
    }

    static func formatted(bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}
