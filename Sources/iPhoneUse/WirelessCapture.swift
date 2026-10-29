import Foundation

/// A single explicitly selected AirPlay source. USB capture is disabled in this mode.
final class WirelessCapture {
    static let shared = WirelessCapture()
    private let screen = Screen(id: "airplay-phone", name: "iPhone (AirPlay)")
    private let pipeline = VideoPipeline()
    private let lock = NSLock()
    private var present = false
    private var accepting = true
    private(set) var receiverName = ProcessInfo.processInfo.environment["IPHONE_USE_AIRPLAY_NAME"] ?? "iPhone Use Wireless"

    var all: [Screen] { lock.withLock { present ? [screen] : [] } }

    func start() {
        pipeline.onFrame = { [weak self] buffer in
            guard let self else { return }
            let changed = self.lock.withLock { () -> Bool in
                guard self.accepting else { return false }
                self.screen.accept(buffer)
                let changed = !self.present
                self.present = true
                return changed
            }
            if changed {
                log("AirPlay: first decoded frame received")
                ScreenCapture.shared.onScreensChanged?()
            }
        }
        let receiver = AirPlayReceiver.shared
        receiver.onVideo = { [weak self] bytes, length, h265 in
            guard !h265 else { log("AirPlay: unsupported H.265 stream"); return }
            self?.pipeline.handleAccessUnit(bytes, length)
        }
        receiver.onEvent = { [weak self] event in
            guard let self else { return }
            log("AirPlay event: \(event)")
            switch event {
            case .clientInfo(_, let model, let name):
                log("AirPlay source: \(name) (\(model))")
                self.lock.withLock { self.accepting = true }
            case .mirrorRunning(let running):
                if !running { self.clear() }
                else { self.lock.withLock { self.accepting = true } }
            case .connReset:
                self.clear()
            case .videoFlush:
                self.pipeline.flush()
            default: break
            }
        }
        receiver.onLog = { level, message in if level <= 3 { log("AirPlay: \(message)") } }
        if receiver.start(name: receiverName) { log("AirPlay receiver ready: \(receiverName)") }
        else { log("AirPlay receiver failed to start") }
    }

    private func clear() {
        lock.withLock { accepting = false; present = false; screen.clear() }
        pipeline.reset()
        ScreenCapture.shared.onScreensChanged?()
        log("AirPlay stream ended; screen removed")
    }
}
