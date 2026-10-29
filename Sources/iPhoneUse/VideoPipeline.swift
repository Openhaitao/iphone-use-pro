// Adapted from MirrorDeck (GPL-3.0); see AIRPLAY-NOTICE.md.
import Foundation
import AVFoundation
import CoreMedia
import VideoToolbox

/// Serial H.264 Annex-B parser and VideoToolbox decoder, emitting decoded pixel buffers.
final class VideoPipeline {
    var onFrame: ((CVPixelBuffer) -> Void)?
    private var decoder: VTDecompressionSession?

    static let debugEnabled = ProcessInfo.processInfo.environment["MIRRORDECK_DEBUG"] == "1"

    private let queue = DispatchQueue(label: "mirrordeck.video", qos: .userInteractive)
    private var formatDescription: CMVideoFormatDescription?
    private var sps: Data?
    private var pps: Data?
    private var framesSeen = 0

    /// Apply backpressure rather than accumulating compressed frames and increasing latency.
    func handleAccessUnit(_ bytes: UnsafePointer<UInt8>, _ length: Int) {
        let data = Data(bytes: bytes, count: length)
        queue.sync { process(data) }
    }

    func flush() {
        queue.async { [weak self] in
            if let decoder = self?.decoder { VTDecompressionSessionWaitForAsynchronousFrames(decoder) }
        }
    }

    func reset() {
        queue.async { [weak self] in
            guard let self else { return }
            if let decoder = self.decoder {
                VTDecompressionSessionWaitForAsynchronousFrames(decoder)
                VTDecompressionSessionInvalidate(decoder)
            }
            self.decoder = nil
            self.formatDescription = nil
            self.sps = nil
            self.pps = nil
        }
    }

    // MARK: - Parsing

    private func process(_ frame: Data) {
        var vclUnits: [Data] = []
        var parameterSetsChanged = false

        let nals = VideoPipeline.splitAnnexB(frame)
        if VideoPipeline.debugEnabled && framesSeen < 5 {
            let types = nals.map { String(($0.first ?? 0) & 0x1F) }.joined(separator: ",")
            NSLog("[MirrorDeck] video frame %d: %d bytes, %d NAL(s), types=[%@]",
                  framesSeen, frame.count, nals.count, types)
        }
        framesSeen += 1

        for nal in nals {
            guard let first = nal.first else { continue }
            let nalType = first & 0x1F
            switch nalType {
            case 7:
                if sps != nal { sps = nal; parameterSetsChanged = true }
            case 8:
                if pps != nal { pps = nal; parameterSetsChanged = true }
            case 1, 5:
                vclUnits.append(nal)
            default:
                break // SEI / AUD etc. are not needed for display
            }
        }

        if parameterSetsChanged || formatDescription == nil {
            rebuildFormatDescription()
        }
        guard let formatDescription, !vclUnits.isEmpty else { return }
        guard let sampleBuffer = makeSampleBuffer(vclUnits, format: formatDescription) else { return }

        if decoder == nil {
            var callback = VTDecompressionOutputCallbackRecord(
                decompressionOutputCallback: { ref, _, status, _, buffer, _, _ in
                    guard status == noErr, let ref, let buffer else { return }
                    let owner = Unmanaged<VideoPipeline>.fromOpaque(ref).takeUnretainedValue()
                    owner.onFrame?(buffer)
                }, decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque())
            let attrs: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                       kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
            let result = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault,
                formatDescription: formatDescription, decoderSpecification: nil,
                imageBufferAttributes: attrs as CFDictionary, outputCallback: &callback,
                decompressionSessionOut: &decoder)
            guard result == noErr else { log("AirPlay decoder creation failed: \(result)"); return }
        }
        if let decoder {
            let result = VTDecompressionSessionDecodeFrame(decoder, sampleBuffer: sampleBuffer,
                flags: [], frameRefcon: nil, infoFlagsOut: nil)
            if result != noErr { log("AirPlay decode error: \(result)") }
        }
    }

    private func rebuildFormatDescription() {
        guard let sps, let pps else { return }
        var format: CMVideoFormatDescription?
        let status = sps.withUnsafeBytes { spsPtr -> OSStatus in
            pps.withUnsafeBytes { ppsPtr -> OSStatus in
                let pointers: [UnsafePointer<UInt8>] = [
                    spsPtr.bindMemory(to: UInt8.self).baseAddress!,
                    ppsPtr.bindMemory(to: UInt8.self).baseAddress!,
                ]
                let sizes: [Int] = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: pointers,
                    parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &format)
            }
        }
        guard status == noErr, let format else {
            NSLog("[MirrorDeck] format description FAILED (status %d) sps=%d pps=%d bytes",
                  Int(status), sps.count, pps.count)
            return
        }
        if let decoder {
            VTDecompressionSessionWaitForAsynchronousFrames(decoder)
            VTDecompressionSessionInvalidate(decoder)
            self.decoder = nil
        }
        formatDescription = format
        if VideoPipeline.debugEnabled {
            let d = CMVideoFormatDescriptionGetDimensions(format)
            NSLog("[MirrorDeck] format description ready: %dx%d", d.width, d.height)
        }


    }

    private func makeSampleBuffer(_ nalUnits: [Data], format: CMVideoFormatDescription) -> CMSampleBuffer? {
        // AVCC layout: 4-byte big-endian length prefix per NAL unit.
        var avcc = Data(capacity: nalUnits.reduce(0) { $0 + $1.count + 4 })
        for nal in nalUnits {
            var lengthBE = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: &lengthBE) { avcc.append(contentsOf: $0) }
            avcc.append(nal)
        }

        var blockBuffer: CMBlockBuffer?
        let count = avcc.count
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: count,
            flags: 0,
            blockBufferOut: &blockBuffer)
        guard status == kCMBlockBufferNoErr, let blockBuffer else { return nil }
        status = avcc.withUnsafeBytes { ptr in
            CMBlockBufferReplaceDataBytes(
                with: ptr.baseAddress!, blockBuffer: blockBuffer,
                offsetIntoDestination: 0, dataLength: count)
        }
        guard status == kCMBlockBufferNoErr else { return nil }

        var sampleBuffer: CMSampleBuffer?
        var sampleSize = count
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: format,
            sampleCount: 1,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer)
        guard status == noErr, let sampleBuffer else { return nil }

        // Display each frame as soon as it decodes — lowest possible latency.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) as? [CFMutableDictionary],
           let dict = attachments.first {
            CFDictionarySetValue(
                dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sampleBuffer
    }

    /// Splits an Annex-B byte stream into NAL unit payloads (start codes removed).
    static func splitAnnexB(_ data: Data) -> [Data] {
        var units: [Data] = []
        let bytes = [UInt8](data)
        var i = 0
        var currentStart: Int? = nil
        while i + 2 < bytes.count {
            if bytes[i] == 0, bytes[i + 1] == 0, bytes[i + 2] == 1 {
                let startCodeLength = (i > 0 && bytes[i - 1] == 0) ? 4 : 3
                let boundary = startCodeLength == 4 ? i - 1 : i
                if let start = currentStart, boundary > start {
                    units.append(Data(bytes[start..<boundary]))
                }
                i += 3
                currentStart = i
            } else {
                i += 1
            }
        }
        if let start = currentStart, start < bytes.count {
            units.append(Data(bytes[start...]))
        }
        return units
    }
}
