import Foundation

/// The HTTP API. Every route takes an optional `device` (id or name), required only when
/// more than one phone is plugged in. Tap and swipe coordinates are pixels of the full
/// screen, or of a resized screenshot when `width`/`height` or `maxEdge` say so.
enum Routes {
    private static let actions: Set = ["/tap", "/swipe", "/move", "/nudge", "/type", "/key", "/home"]

    static func handle(_ request: HTTPRequest) -> HTTPResponse {
        let body = request.body
        let deviceQuery = (body["device"] as? String) ?? request.query["device"]
        do {
            switch (request.method, request.path) {
            case ("GET", "/"), ("GET", "/status"):
                return .json([
                    "bluetooth": HIDPeripheral.shared.state,
                    "devices": Devices.shared.all().map(\.json),
                    "unmatchedHosts": Devices.shared.unmatchedHosts().map(\.uuidString),
                ])

            case ("POST", "/capture/usb/pause"):
                ScreenCapture.shared.pauseUSB()
                return .json(["ok": true, "usbCapture": "paused"])
            case ("POST", "/capture/usb/resume"):
                ScreenCapture.shared.resumeUSB()
                return .json(["ok": true, "usbCapture": "resumed"])
            case ("GET", "/devices"):
                return .json(["devices": Devices.shared.all().map(\.json)])

            case ("POST", "/match"):
                let found = Devices.shared.match(force: (body["force"] as? Bool) ?? false)
                return .json([
                    "matched": found.mapValues(\.uuidString),
                    "devices": Devices.shared.all().map(\.json),
                    "unmatchedHosts": Devices.shared.unmatchedHosts().map(\.uuidString),
                ])

            case ("POST", "/pair"):
                guard let hostString = body["host"] as? String, let host = UUID(uuidString: hostString) else {
                    return .error("host is required (a UUID from unmatchedHosts)")
                }
                Devices.shared.pair(try Devices.shared.find(deviceQuery), host: host)
                return .json(["devices": Devices.shared.all().map(\.json)])

            case ("GET", "/frame"):
                guard let frame = try Devices.shared.find(deviceQuery).screen.observation() else {
                    return .error("no frame available", status: 503)
                }
                return .json(["sequence": frame.sequence, "pixels": frame.pixels, "ageMs": frame.ageMs])
            case ("GET", "/screenshot"):
                let device = try Devices.shared.find(deviceQuery)
                let png = request.query["format"] == "png"
                let maxWidth = try positiveLimit(request.query["maxWidth"])
                let maxEdge = try positiveLimit(request.query["maxEdge"])
                guard let size = device.screen.size,
                    let data = device.screen.snapshot(png: png, maxWidth: maxWidth, maxEdge: maxEdge)
                else { return .error("no frame yet from \(device.screen.name): unlock it", status: 503) }
                let image = imageSize(size, maxWidth: maxWidth, maxEdge: maxEdge)
                return HTTPResponse(
                    contentType: png ? "image/png" : "image/jpeg",
                    headers: [
                        "X-Device": device.id,
                        "X-Screen-Width": "\(Int(size.width))", "X-Screen-Height": "\(Int(size.height))",
                        "X-Image-Width": "\(image.0)", "X-Image-Height": "\(image.1)",
                    ],
                    body: data)

            default:
                guard request.method == "POST", actions.contains(request.path) else {
                    return .error("not found", status: 404)
                }
            }

            let device = try Devices.shared.find(deviceQuery)
            let input = try Devices.shared.input(for: device)
            switch (request.method, request.path) {
            case ("POST", "/tap"):
                let (x, y) = try point(body, "x", "y", on: device)
                input.tap(x: x, y: y, hold: try bounded(body["hold"], default: 0.08, range: 0.02...5))
            case ("POST", "/swipe"):
                let from = try point(body, "x1", "y1", on: device)
                let to = try point(body, "x2", "y2", on: device)
                input.swipe(from: from, to: to, duration: try bounded(body["duration"], default: 0.3, range: 0.05...5))
            case ("POST", "/move"):
                let (x, y) = try point(body, "x", "y", on: device)
                input.move(x: x, y: y)
            case ("POST", "/nudge"):
                let dx = try bounded(body["dx"], default: 0, range: -4096...4096)
                let dy = try bounded(body["dy"], default: 0, range: -4096...4096)
                input.nudge(
                    dx: Int(dx), dy: Int(dy),
                    click: (body["click"] as? Bool) ?? false)
            case ("POST", "/type"):
                guard let text = body["text"] as? String else { return .error("text is required") }
                guard text.count <= 4096 else { return .error("text exceeds 4096 characters") }
                try input.type(text)
            case ("POST", "/key"):
                guard let key = body["key"] as? String else { return .error("key is required") }
                try input.key(key, modifiers: (body["modifiers"] as? [String]) ?? [])
            case ("POST", "/home"):
                input.consumer(0x0223)
            default:
                return .error("not found", status: 404)
            }
            return .json(["ok": true, "device": device.id])
        } catch {
            return .error("\(error)")
        }
    }

    private static func imageSize(_ size: CGSize, maxWidth: Int?, maxEdge: Int?) -> (Int, Int) {
        var scale = 1.0
        if let maxWidth { scale = min(scale, Double(maxWidth) / size.width) }
        if let maxEdge { scale = min(scale, Double(maxEdge) / max(size.width, size.height)) }
        return (Int((size.width * scale).rounded()), Int((size.height * scale).rounded()))
    }

    /// Converts coordinates to 0...1 fractions of the phone's screen.
    private static func point(
        _ body: [String: Any], _ xKey: String, _ yKey: String, on device: Device
    ) throws -> (Double, Double) {
        guard let x = number(body[xKey]), let y = number(body[yKey]) else {
            throw DeviceError("\(xKey) and \(yKey) are required")
        }
        if (body["fraction"] as? Bool) == true {
            guard (0...1).contains(x), (0...1).contains(y) else { throw DeviceError("fractions must be in 0...1") }
            return (x, y)
        }
        guard let size = device.screen.size else { throw DeviceError("no frame yet from \(device.screen.name)") }
        var width = Double(size.width)
        var height = Double(size.height)
        if let raw = body["maxEdge"] {
            let maxEdge = Int(try bounded(raw, default: 1200, range: 1...16384))
            let image = imageSize(size, maxWidth: nil, maxEdge: maxEdge)
            width = Double(image.0)
            height = Double(image.1)
        }
        width = number(body["width"]) ?? width
        height = number(body["height"]) ?? height
        guard width > 0, height > 0, x >= 0, y >= 0, x <= width, y <= height else {
            throw DeviceError("coordinates must be inside a positive screen size")
        }
        return (x / width, y / height)
    }

    static func positiveLimit(_ raw: String?) throws -> Int? {
        guard let raw else { return nil }
        guard let value = Int(raw), (1...16384).contains(value) else { throw DeviceError("image limit must be in 1...16384") }
        return value
    }

    static func bounded(_ raw: Any?, default fallback: Double, range: ClosedRange<Double>) throws -> Double {
        guard let raw else { return fallback }
        guard let value = number(raw), range.contains(value) else { throw DeviceError("numeric parameter outside \(range)") }
        return value
    }

    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }
}
