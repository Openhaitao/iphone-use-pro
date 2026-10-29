import XCTest
@testable import iPhoneUse

final class ProtocolTests: XCTestCase {
    func parse(_ text: String) throws -> HTTPRequest? { try HTTPRequestParser.parse(Data(text.utf8)) }
    func testFragmentedJSONBody() throws {
        XCTAssertNil(try parse("POST /key HTTP/1.1\r\nContent-Length: 15\r\n\r\n{\"key\":"))
        let r = try XCTUnwrap(parse("POST /key?device=phone HTTP/1.1\r\nContent-Length: 15\r\n\r\n{\"key\":\"eject\"}"))
        XCTAssertEqual(r.path, "/key")
        XCTAssertEqual(r.query["device"], "phone")
        XCTAssertEqual(r.body["key"] as? String, "eject")
    }
    func testRejectMalformedLengthsAndJSON() {
        for value in ["-1", "hello", "9999999999999999999999", "1048577"] {
            XCTAssertThrowsError(try parse("POST /key HTTP/1.1\r\nContent-Length: \(value)\r\n\r\n"))
        }
        XCTAssertThrowsError(try parse("POST /key HTTP/1.1\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n"))
        XCTAssertThrowsError(try parse("POST /key HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"))
        XCTAssertThrowsError(try parse("POST /key HTTP/1.1\r\nContent-Length: 1\r\n\r\nx"))
    }
    func testRejectInvalidActionLimits() {
        for raw in ["0", "-1", "999999999999999999999", "bad"] { XCTAssertThrowsError(try Routes.positiveLimit(raw)) }
        XCTAssertThrowsError(try Routes.bounded(Double.nan, default: 1, range: 0...5))
        XCTAssertThrowsError(try Routes.bounded(true, default: 1, range: 0...5))
        XCTAssertThrowsError(try Routes.bounded(-1, default: 1, range: 0...5))
        XCTAssertEqual(try Routes.bounded(nil, default: 1, range: 0...5), 1)
    }
    func testScreenshotResolutionCoordinates() throws {
        defer { MCPServer.rememberScreenshot(device: nil, id: "", edge: 800) }
        XCTAssertEqual(try MCPServer.requestedEdge(nil), 800)
        XCTAssertEqual(try MCPServer.requestedEdge(1080), 1080)
        for raw: Any in [true, 0, -1, 800.5, Double.infinity] { XCTAssertThrowsError(try MCPServer.requestedEdge(raw)) }
        MCPServer.rememberScreenshot(device: nil, id: "primary", edge: 1080)
        MCPServer.rememberScreenshot(device: "other", id: "other", edge: 800)
        XCTAssertEqual(try MCPServer.scaled(["x":10,"y":20], ["x","y"])["maxEdge"] as? Int, 1080)
        XCTAssertEqual(try MCPServer.scaled(["x":10,"y":20,"device":"other"], ["x","y"])["maxEdge"] as? Int, 800)
    }
    func testFrameWaitNeedsFreshChangedSettledFrames() {
        func frame(_ id: UInt64, _ p: [UInt8], age: Double = 0) -> FrameObservation { FrameObservation(sequence: id, pixels: p, ageMs: age) }
        let old = [UInt8](repeating: 0, count: 8)
        let next = [UInt8](repeating: 200, count: 8)
        var waiter = FrameWaiter(baseline: frame(10,old))
        XCTAssertFalse(waiter.observe(frame(10,next), elapsed: 0.1))
        XCTAssertFalse(waiter.observe(frame(11,next, age: 600), elapsed: 0.2))
        XCTAssertFalse(waiter.observe(frame(12,old), elapsed: 0.3))
        XCTAssertFalse(waiter.observe(frame(13,next), elapsed: 0.4))
        XCTAssertFalse(waiter.observe(frame(14,next), elapsed: 0.45))
        XCTAssertTrue(waiter.observe(frame(15,next), elapsed: 0.52))
    }
    func testProbeScoreRejectsStaleFrozenAndMalformedFrames() {
        func frame(_ sequence: UInt64, age: Double = 0, pixels: [UInt8]? = nil) -> FrameObservation {
            FrameObservation(sequence: sequence, pixels: pixels ?? [UInt8](repeating: 0, count: 90 * 195), ageMs: age)
        }
        let pointA = (x: 0.3, y: 0.35)
        let pointB = (x: 0.7, y: 0.65)
        XCTAssertNil(Devices.probeScore(before: frame(1), after: frame(1), firstPoint: pointA, secondPoint: pointB))
        XCTAssertNil(Devices.probeScore(before: frame(1, age: 501), after: frame(2), firstPoint: pointA, secondPoint: pointB))
        XCTAssertNil(Devices.probeScore(before: frame(1), after: frame(2, age: 501), firstPoint: pointA, secondPoint: pointB))
        XCTAssertNil(Devices.probeScore(before: frame(1), after: frame(2, pixels: [0]), firstPoint: pointA, secondPoint: pointB))
        XCTAssertNil(Devices.probeScore(before: frame(1), after: frame(2), firstPoint: (x: -0.1, y: 0.35), secondPoint: pointB))
    }

    func testProbeScoreRequiresDistinctPointerMovementAtBothExpectedLocations() {
        let pointA = (x: 0.3, y: 0.35)
        let pointB = (x: 0.7, y: 0.65)
        let beforePixels = [UInt8](repeating: 0, count: 90 * 195)
        var afterPixels = beforePixels
        for point in [pointA, pointB] {
            let cx = Int(point.x * 90)
            let cy = Int(point.y * 195)
            for y in (cy - 7)...(cy + 7) {
                for x in (cx - 7)...(cx + 7) { afterPixels[y * 90 + x] = 255 }
            }
        }
        let before = FrameObservation(sequence: 10, pixels: beforePixels, ageMs: 10)
        let after = FrameObservation(sequence: 11, pixels: afterPixels, ageMs: 10)
        XCTAssertEqual(Devices.probeScore(before: before, after: after, firstPoint: pointA, secondPoint: pointB), 225)
        XCTAssertEqual(Devices.probeScore(before: before, after: after, firstPoint: (x: 0.5, y: 0.5), secondPoint: (x: 0.7, y: 0.65)), 0)
    }

    func testProbeScoreSelectionRequiresClearWinner() {
        XCTAssertEqual(Devices.uniquelyBestProbeScore([0, 16]), 16)
        XCTAssertNil(Devices.uniquelyBestProbeScore([0, 0]))
        XCTAssertNil(Devices.uniquelyBestProbeScore([6, 5]))
        XCTAssertNil(Devices.uniquelyBestProbeScore([2]))
    }

    func testActionGapBounds() {
        XCTAssertEqual(ActionTiming.gapSeconds(nil), 0.12)
        XCTAssertEqual(ActionTiming.gapSeconds("200"), 0.2)
        for raw in ["nan", "-1", "1001", "bad"] { XCTAssertEqual(ActionTiming.gapSeconds(raw), 0.12) }
    }
    func testUnknownKeysDoNotCrash() {
        let input = Input(host: UUID())
        for name in ["", "unknown-key", "eject"] {
            XCTAssertThrowsError(try input.key(name, modifiers: name == "eject" ? ["cmd"] : []))
        }
    }
    func testAnnexBMixedStartCodes() {
        let data = Data([0,0,0,1,0x67,2,0,0,1,0x68,3,0,0,0,1,0x65,4])
        XCTAssertEqual(VideoPipeline.splitAnnexB(data), [Data([0x67,2]),Data([0x68,3]),Data([0x65,4])])
        XCTAssertTrue(VideoPipeline.splitAnnexB(Data([1,2])).isEmpty)
    }
}
