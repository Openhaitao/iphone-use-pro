import Foundation

struct FrameObservation: Codable {
    let sequence: UInt64
    let pixels: [UInt8]
    let ageMs: Double
}

/// Small grayscale signature ignores the status bar and tiny cursor changes.
/// A stable changed image is evidence of rendering, never proof of task success.
struct FrameWaiter {
    let baseline: FrameObservation
    private(set) var changed = false
    private var previous: FrameObservation?
    private var stableSince: Double?

    init(baseline: FrameObservation) { self.baseline = baseline }

    static func difference(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count, !a.isEmpty else { return Int.max }
        return zip(a,b).filter { abs(Int($0) - Int($1)) > 20 }.count
    }

    mutating func observe(_ frame: FrameObservation, elapsed: Double) -> Bool {
        guard frame.sequence > baseline.sequence, frame.ageMs < 500 else { return false }
        if Self.difference(frame.pixels, baseline.pixels) >= 4 { changed = true }
        defer { previous = frame }
        guard changed, let previous, frame.sequence > previous.sequence else { return false }
        if Self.difference(frame.pixels, previous.pixels) <= 2 {
            if stableSince == nil { stableSince = elapsed }
            return elapsed - (stableSince ?? elapsed) >= 0.06
        }
        stableSince = nil
        return false
    }
}

enum ActionTiming {
    static func gapSeconds(_ raw: String?) -> Double {
        guard let raw, let value = Double(raw), value.isFinite, (0...1000).contains(value) else { return 0.12 }
        return value / 1000
    }
}
