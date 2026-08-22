import Foundation
import AVFoundation

enum SegmentFinalisationError: LocalizedError, Equatable {
    case missing
    case emptyFile
    case unreadable(String)
    case zeroDuration

    var errorDescription: String? {
        switch self {
        case .missing:
            return "The audio file is missing."
        case .emptyFile:
            return "The audio file is zero bytes."
        case .unreadable(let detail):
            return "The audio file could not be read. \(detail)"
        case .zeroDuration:
            return "The audio file reports no duration. It was probably never finalised."
        }
    }
}

/// Gate between the recorder and the transcription queue.
///
/// An m4a whose moov atom has not been written still exists on disk and still
/// has a plausible byte count, but every reader sees it as empty and it
/// transcribes to nothing, silently. That is the single most likely cause of
/// "transcription produced no output", so a segment is verified before it is
/// ever enqueued rather than after it has already failed.
enum SegmentFinalisation {

    static func verify(url: URL) async throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else {
            throw SegmentFinalisationError.missing
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try manager.attributesOfItem(atPath: url.path)
        } catch {
            throw SegmentFinalisationError.unreadable(error.localizedDescription)
        }

        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else {
            throw SegmentFinalisationError.emptyFile
        }

        let asset = AVURLAsset(url: url)
        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            throw SegmentFinalisationError.unreadable(error.localizedDescription)
        }

        guard duration.isNumeric, duration.seconds > 0 else {
            throw SegmentFinalisationError.zeroDuration
        }
    }

    /// Actual on disk duration, used to report a gap at a segment boundary.
    static func duration(of url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        do {
            let value = try await asset.load(.duration)
            return value.isNumeric ? value.seconds : 0
        } catch {
            return 0
        }
    }
}
