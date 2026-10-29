import Foundation

/// A phone: its USB screen, and the Bluetooth host that drives it once matched and connected.
struct Device {
    let screen: Screen
    let host: UUID?

    var id: String { screen.id }

    var json: [String: Any] {
        var info: [String: Any] = ["id": id, "name": screen.name, "bluetooth": host != nil, "transport": screen.transport]
        if let size = screen.size {
            info["width"] = Int(size.width)
            info["height"] = Int(size.height)
        }
        return info
    }
}

/// Matches each phone's Bluetooth connection to its USB screen. Bluetooth does not say which
/// phone is which, so matching moves the pointer through one connection and looks for the
/// screen where it moved. Matches are saved, so a phone is matched once.
final class Devices {
    static let shared = Devices()

    private static let thumbWidth = 90
    private static let thumbHeight = 195
    private static let maxProbeFrameAgeMs = 500.0
    private static let probeFrameTimeout = 1.5

    private let lock = NSLock()
    private var pairings: [String: UUID] = [:]
    private var inputs: [UUID: Input] = [:]
    private var matchPending = false
    private let matchQueue = DispatchQueue(label: "iphone-use.match")

    private let file: URL = {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iPhoneUse", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("pairings.json")
    }()

    func start() {
        load()
        ScreenCapture.shared.onScreensChanged = { [weak self] in self?.scheduleMatch() }
        HIDPeripheral.shared.onHostsChanged = { [weak self] in self?.scheduleMatch() }
    }

    func all() -> [Device] {
        let hosts = Set(HIDPeripheral.shared.connectedHosts)
        let pairings = lock.withLock { self.pairings }
        return ScreenCapture.shared.all.map { screen in
            Device(screen: screen, host: pairings[screen.id].flatMap { hosts.contains($0) ? $0 : nil })
        }
    }

    /// Connected Bluetooth hosts that no present screen is matched to.
    func unmatchedHosts() -> [UUID] {
        let matched = Set(all().compactMap(\.host))
        return HIDPeripheral.shared.connectedHosts.filter { !matched.contains($0) }
    }

    /// A phone by id, name or id prefix. Without a query there must be exactly one phone.
    func find(_ query: String?) throws -> Device {
        let devices = all()
        if let query, !query.isEmpty {
            let q = query.lowercased()
            let hit =
                devices.first { $0.id.lowercased() == q } ?? devices.first { $0.screen.name.lowercased() == q }
                ?? devices.first { $0.id.lowercased().hasPrefix(q) }
            guard let hit else { throw DeviceError("no phone matches \"\(query)\". \(Self.describe(devices))") }
            return hit
        }
        guard !devices.isEmpty else {
            throw DeviceError("no iPhone screen: unlock the iPhone and start Screen Mirroring to this receiver (or connect USB in USB mode)")
        }
        guard devices.count == 1 else {
            throw DeviceError("\(devices.count) phones are connected, pass device. \(Self.describe(devices))")
        }
        return devices[0]
    }

    /// Resolves the phone's existing Bluetooth pairing; matching is an explicit operation.
    func input(for device: Device) throws -> Input {
        guard let host = device.host else {
            throw DeviceError(
                "\(device.screen.name) has no confirmed Bluetooth pairing; unlock it, check AssistiveTouch is on, then POST /match"
            )
        }
        return input(for: host)
    }

    func input(for host: UUID) -> Input {
        lock.withLock {
            if let input = inputs[host] { return input }
            let input = Input(host: host)
            inputs[host] = input
            return input
        }
    }

    func pair(_ device: Device, host: UUID) {
        store([device.id: host])
    }

    /// Matches unmatched pointer hosts to unmatched screens using fresh, advancing frames.
    /// `force` rematches every screen present; a screen nothing is found for keeps its match.
    @discardableResult
    func match(force: Bool = false) -> [String: UUID] {
        matchQueue.sync { runMatch(force: force) }
    }

    func matchIfUnpaired(_ device: Device) throws -> Input {
        if let host = device.host { return input(for: host) }
        match()
        if let host = try find(device.id).host { return input(for: host) }
        if unmatchedHosts().isEmpty {
            throw DeviceError(
                "\(device.screen.name) has no Bluetooth connection: pair \"\(HIDPeripheral.shared.localName)\" in its Bluetooth settings"
            )
        }
        throw DeviceError(
            "could not tell which Bluetooth connection is \(device.screen.name): unlock it, check AssistiveTouch is on, then POST /match"
        )
    }

    // MARK: Matching

    private func scheduleMatch() {
        let alreadyPending = lock.withLock {
            defer { matchPending = true }
            return matchPending
        }
        guard !alreadyPending else { return }
        matchQueue.asyncAfter(deadline: .now() + 1.5) {
            self.lock.withLock { self.matchPending = false }
            self.runMatch(force: false)
        }
    }

    @discardableResult
    private func runMatch(force: Bool) -> [String: UUID] {
        let screens = ScreenCapture.shared.all
        let hosts = HIDPeripheral.shared.connectedHosts
        let pointerHosts = HIDPeripheral.shared.pointerHosts
        var pairings = lock.withLock { self.pairings }
        if force { for screen in screens { pairings[screen.id] = nil } }

        let matchedHosts = Set(screens.compactMap { pairings[$0.id] }.filter(hosts.contains))
        var freeScreens = screens.filter { pairings[$0.id].map { !hosts.contains($0) } ?? true }
        let freeHosts = pointerHosts.filter { !matchedHosts.contains($0) }
        guard !freeScreens.isEmpty, !freeHosts.isEmpty else { return [:] }

        var found: [String: UUID] = [:]
        if screens.count == 1, freeHosts.count == 1, hosts.count == 1,
            screens[0].observation()?.ageMs ?? .infinity < Self.maxProbeFrameAgeMs {
            found[screens[0].id] = freeHosts[0]
        } else {
            for host in freeHosts where !freeScreens.isEmpty {
                guard let screen = probe(host, among: freeScreens) else { continue }
                found[screen.id] = host
                freeScreens.removeAll { $0.id == screen.id }
            }
        }
        store(found)
        for (id, host) in found {
            log("matched \(screens.first { $0.id == id }?.name ?? id) to bluetooth host \(host)")
        }
        return found
    }

    /// Moves the host's pointer between two spots and compares only fresh, advancing frames.
    private func probe(_ host: UUID, among screens: [Screen]) -> Screen? {
        let input = input(for: host)
        let a = (x: 0.3, y: 0.35)
        let b = (x: 0.7, y: 0.65)
        let initial = screens.map { $0.thumbnailObservation(width: Self.thumbWidth, height: Self.thumbHeight) }
        input.move(x: a.x, y: a.y)
        Thread.sleep(forTimeInterval: 0.15)
        let before = screens.enumerated().map { index, screen in
            waitForFreshFrame(on: screen, after: initial[index]?.sequence)
        }
        input.move(x: b.x, y: b.y)
        Thread.sleep(forTimeInterval: 0.15)
        let after = screens.enumerated().map { index, screen in
            waitForFreshFrame(on: screen, after: before[index]?.sequence)
        }

        var scores: [(screen: Screen, score: Int)] = []
        for (i, screen) in screens.enumerated() {
            guard let p = before[i], let q = after[i],
                let score = Self.probeScore(before: p, after: q, firstPoint: a, secondPoint: b)
            else { continue }
            scores.append((screen, score))
        }
        log("probe \(host): " + scores.map { "\($0.screen.name)=\($0.score)" }.joined(separator: " "))

        let ranked = scores.sorted { $0.score > $1.score }
        guard let best = Self.uniquelyBestProbeScore(ranked.map(\.score)) else { return nil }
        guard let winner = ranked.first(where: { $0.score == best }) else { return nil }
        return winner.screen
    }

    private func waitForFreshFrame(on screen: Screen, after sequence: UInt64?) -> FrameObservation? {
        let deadline = ProcessInfo.processInfo.systemUptime + Self.probeFrameTimeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let frame = screen.thumbnailObservation(width: Self.thumbWidth, height: Self.thumbHeight),
                frame.ageMs < Self.maxProbeFrameAgeMs,
                sequence.map({ frame.sequence > $0 }) ?? (frame.ageMs < Self.maxProbeFrameAgeMs) {
                return frame
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return nil
    }

    static func acceptsProbeScore(_ score: Int) -> Bool { score >= 3 }

    static func uniquelyBestProbeScore(_ scores: [Int]) -> Int? {
        let ranked = scores.sorted(by: >)
        guard let best = ranked.first, acceptsProbeScore(best) else { return nil }
        if ranked.count > 1, ranked[1] * 2 >= best { return nil }
        return best
    }

    static func probeScore(
        before: FrameObservation, after: FrameObservation,
        firstPoint: (x: Double, y: Double), secondPoint: (x: Double, y: Double)
    ) -> Int? {
        guard before.ageMs < maxProbeFrameAgeMs, after.ageMs < maxProbeFrameAgeMs,
            after.sequence > before.sequence,
            before.pixels.count == thumbWidth * thumbHeight,
            after.pixels.count == thumbWidth * thumbHeight,
            [firstPoint.x, firstPoint.y, secondPoint.x, secondPoint.y].allSatisfy({ (0...1).contains($0) })
        else { return nil }
        let signal = min(
            changed(before.pixels, after.pixels, around: firstPoint),
            changed(before.pixels, after.pixels, around: secondPoint))
        let noise = max(
            changed(before.pixels, after.pixels, around: (firstPoint.x, secondPoint.y)),
            changed(before.pixels, after.pixels, around: (secondPoint.x, firstPoint.y)))
        return signal - noise
    }

    /// Pixels that changed noticeably in a small box around a point.
    private static func changed(_ p: [UInt8], _ q: [UInt8], around point: (Double, Double)) -> Int {
        let radius = 7
        let cx = Int(point.0 * Double(thumbWidth))
        let cy = Int(point.1 * Double(thumbHeight))
        var count = 0
        for y in max(0, cy - radius)...min(thumbHeight - 1, cy + radius) {
            for x in max(0, cx - radius)...min(thumbWidth - 1, cx + radius) {
                let i = y * thumbWidth + x
                if abs(Int(p[i]) - Int(q[i])) > 12 { count += 1 }
            }
        }
        return count
    }

    // MARK: Saved matches

    /// One host drives one screen, so a new match replaces the host's old one.
    private func store(_ found: [String: UUID]) {
        guard !found.isEmpty else { return }
        lock.withLock {
            for (id, host) in found {
                for (other, existing) in pairings where existing == host { pairings[other] = nil }
                pairings[id] = host
            }
            let encoded = pairings.mapValues(\.uuidString)
            if let data = try? JSONSerialization.data(withJSONObject: encoded, options: [.prettyPrinted]) {
                try? data.write(to: file)
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: file),
            let saved = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return }
        lock.withLock { pairings = saved.compactMapValues(UUID.init(uuidString:)) }
    }

    private static func describe(_ devices: [Device]) -> String {
        guard !devices.isEmpty else { return "No phone screens are available." }
        return "Phones: " + devices.map { "\($0.screen.name) (\($0.id))" }.joined(separator: ", ")
    }
}

struct DeviceError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
