import AVFoundation
import CoreImage
import CoreMediaIO
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One iPhone's screen over USB.
final class Screen: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private static let context = CIContext()

    /// The capture device's uniqueID, stable for a given phone.
    let id: String
    let name: String
    let transport: String
    let device: AVCaptureDevice?

    private let session = AVCaptureSession()
    private let queue: DispatchQueue
    private var latest: CVPixelBuffer?
    private var sequence: UInt64 = 0
    private var receivedAt = 0.0

    init(device: AVCaptureDevice) throws {
        self.device = device
        id = device.uniqueID
        name = device.localizedName
        transport = "usb"
        queue = DispatchQueue(label: "iphone-use.capture.\(device.uniqueID)")
        super.init()

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CaptureError("cannot capture \(name)") }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CaptureError("cannot read frames from \(name)") }
        session.addOutput(output)
        session.startRunning()
    }

    init(id: String, name: String) {
        self.device = nil
        self.id = id
        self.name = name
        self.transport = "airplay"
        queue = DispatchQueue(label: "iphone-use.capture.\(id)")
        super.init()
    }

    func accept(_ buffer: CVPixelBuffer) { queue.sync { update(buffer) } }
    private func update(_ buffer: CVPixelBuffer) {
        latest = buffer
        sequence &+= 1
        receivedAt = ProcessInfo.processInfo.systemUptime
    }

    func observation() -> FrameObservation? {
        let state = queue.sync { (latest, sequence, receivedAt) }
        guard let buffer = state.0, let pixels = thumbnail(buffer: buffer, width: 16, height: 32) else { return nil }
        // Exclude the status bar and bottom home indicator; retain the keyboard and app content.
        return FrameObservation(sequence: state.1, pixels: Array(pixels[64..<496]),
            ageMs: max(0, (ProcessInfo.processInfo.systemUptime - state.2) * 1000))
    }
    func clear() { queue.sync { latest = nil } }

    func stop() {
        session.stopRunning()
    }

    var size: CGSize? {
        frame().map { CGSize(width: CVPixelBufferGetWidth($0), height: CVPixelBufferGetHeight($0)) }
    }

    func frame() -> CVPixelBuffer? {
        queue.sync { latest }
    }

    /// JPEG or PNG of the latest frame, scaled so neither edge exceeds the limits.
    func snapshot(png: Bool, maxWidth: Int? = nil, maxEdge: Int? = nil) -> Data? {
        guard let buffer = frame() else { return nil }
        var image = CIImage(cvPixelBuffer: buffer)
        var scale = 1.0
        if let maxWidth { scale = min(scale, Double(maxWidth) / image.extent.width) }
        if let maxEdge { scale = min(scale, Double(maxEdge) / max(image.extent.width, image.extent.height)) }
        if scale < 1 { image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) }
        guard let cgImage = Self.context.createCGImage(image, from: image.extent) else { return nil }
        let data = NSMutableData()
        let type = (png ? UTType.png : UTType.jpeg).identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else { return nil }
        CGImageDestinationAddImage(
            destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// A thumbnail tied to the frame sequence and capture time used to produce it.
    func thumbnailObservation(width: Int, height: Int) -> FrameObservation? {
        let state = queue.sync { (latest, sequence, receivedAt) }
        guard let buffer = state.0,
            let pixels = thumbnail(buffer: buffer, width: width, height: height)
        else { return nil }
        let ageMs = max(0, (ProcessInfo.processInfo.systemUptime - state.2) * 1000)
        return FrameObservation(sequence: state.1, pixels: pixels, ageMs: ageMs)
    }

    /// Grayscale pixels of the latest frame at a small size, first row at the top.
    func thumbnail(width: Int, height: Int) -> [UInt8]? {
        guard let buffer = frame() else { return nil }
        return thumbnail(buffer: buffer, width: width, height: height)
    }

    private func thumbnail(buffer: CVPixelBuffer, width: Int, height: Int) -> [UInt8]? {
        let image = CIImage(cvPixelBuffer: buffer)
        let small = image.transformed(
            by: CGAffineTransform(
                scaleX: CGFloat(width) / image.extent.width, y: CGFloat(height) / image.extent.height))
        guard let cgImage = Self.context.createCGImage(small, from: small.extent) else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard
                let context = CGContext(
                    data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        if let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) { update(buffer) }
    }

    struct CaptureError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}

/// Every iPhone plugged in over USB. A trusted iPhone shows up as a muxed capture
/// device once screen-capture devices are allowed (the same switch QuickTime flips).
final class ScreenCapture {
    static let shared = ScreenCapture()

    private let lock = NSLock()
    private var screens: [String: Screen] = [:]
    private var usbPaused = false

    /// Called when a phone's screen appears or goes away.
    var onScreensChanged: (() -> Void)?

    static var wireless: Bool { ["airplay", "airplay-bootstrap"].contains(ProcessInfo.processInfo.environment["IPHONE_USE_SCREEN"] ?? "") }

    func start() {
        if Self.wireless {
            WirelessCapture.shared.start()
            if ProcessInfo.processInfo.environment["IPHONE_USE_SCREEN"] == "airplay" { return }
        }
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var allow: UInt32 = 1
        CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &allow)

        NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.refresh() }
        NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.refresh() }

        AVCaptureDevice.requestAccess(for: .video) { granted in
            log("camera access \(granted ? "granted" : "denied")")
            self.refresh()
        }
    }

    var all: [Screen] {
        if Self.wireless {
            let streams = WirelessCapture.shared.all
            if !streams.isEmpty || ProcessInfo.processInfo.environment["IPHONE_USE_SCREEN"] == "airplay" { return streams }
        }
        return lock.withLock { screens.values.sorted { $0.name < $1.name } }
    }

    func pauseUSB() {
        let active = lock.withLock { () -> [Screen] in
            usbPaused = true
            let active = Array(screens.values)
            screens.removeAll()
            return active
        }
        active.forEach { $0.stop() }
        log("USB capture explicitly paused")
        onScreensChanged?()
    }

    func resumeUSB() {
        lock.withLock { usbPaused = false }
        refresh()
    }

    private func refresh() {
        guard !lock.withLock({ usbPaused }) else { return }
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external], mediaType: .muxed, position: .unspecified
        ).devices.filter { $0.modelID.contains("iOS") && $0.isConnected }
        let present = Set(devices.map(\.uniqueID))
        var changed = false
        lock.withLock {
            for (id, screen) in screens where !present.contains(id) {
                screen.stop()
                screens[id] = nil
                changed = true
                log("screen gone: \(screen.name)")
            }
            for device in devices where screens[device.uniqueID] == nil {
                do {
                    screens[device.uniqueID] = try Screen(device: device)
                    changed = true
                    log("capturing \(device.localizedName) (\(device.uniqueID))")
                } catch {
                    log("capture failed for \(device.localizedName): \(error)")
                }
            }
            if screens.isEmpty { log("no iPhone screen yet (plug in over USB and trust this Mac)") }
        }
        if changed { onScreensChanged?() }
    }
}
