import Foundation
import AVFoundation
import OpusBinding
import AudioWaveform

// Voice changer presets.
//
// Recorded voice messages: every non-off preset runs its full offline
// AVAudioEngine chain below (pitch, rate, EQ, distortion, delay, reverb).
//
// Calls (1:1 and group): the same preset id selects a realtime,
// sample-count-preserving timbre effect applied in-place to captured mic
// PCM inside TgVoipWebrtc (miraCallVoiceFXProcessBuffer in
// OngoingCallThreadLocalContext.mm, fed by [SharedCallAudioDevice
// setVoiceChangerPreset:]). Pitch shifting is not sample-safe on the
// realtime 10 ms audio callback, so call effects are timbre-disguise only:
// 3 Robot -> ring mod 55 Hz + 6-bit crush; 7 Radio -> 300-3400 Hz bandpass;
// 9 Anonymous / 10 Anonymous Pro -> bandpass + tanh drive + 30 Hz ring mod;
// 11 Demon -> 30 Hz ring mod + hard drive; 12 Cyber -> 7-bit crush + 2x
// sample-hold decimation + 45 Hz ring mod; any other non-zero preset ->
// mild bandpass + gentle drive. Call processing is gated by
// voiceChangerEnabled && voiceChangerPreset != 0 via MiraCoreGate.
public enum MiraVoiceChangerPreset: Int32, CaseIterable {
    case off = 0
    case chipmunk = 1
    case deep = 2
    case robot = 3
    case helium = 4
    case echo = 5
    case child = 6
    case radio = 7
    case reverb = 8
    case anonymous = 9
    case anonymousPro = 10
    case demon = 11
    case cyber = 12
    case masked = 13

    public var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .chipmunk:
            return "Chipmunk"
        case .deep:
            return "Deep"
        case .robot:
            return "Robot"
        case .helium:
            return "Helium"
        case .echo:
            return "Echo"
        case .child:
            return "Child"
        case .radio:
            return "Radio"
        case .reverb:
            return "Whisper"
        case .anonymous:
            return "Anonymous"
        case .anonymousPro:
            return "Anonymous Pro"
        case .demon:
            return "Demon"
        case .cyber:
            return "Cyber"
        case .masked:
            return "Masked"
        }
    }
}

public struct MiraProcessedVoiceMessage {
    public let url: URL
    public let duration: Double
    public let waveform: Data?
}

private struct MiraVoiceChangerEQBand {
    var filterType: AVAudioUnitEQFilterType
    var frequency: Float
    var bandwidth: Float = 1.0
    var gain: Float = 0.0
}

private struct MiraVoiceChangerEffectParams {
    var pitchStages: [(pitchCents: Float, rate: Float)] = []
    var eqBands: [MiraVoiceChangerEQBand] = []
    var distortionStages: [(preset: AVAudioUnitDistortionPreset, wetDryMix: Float)] = []
    var delay: (time: Double, feedback: Float, wetDryMix: Float)?
    var reverb: (preset: AVAudioUnitReverbPreset, wetDryMix: Float)?
    var tailSeconds: Double = 0.0

    init() {
    }

    var totalRate: Float {
        var rate: Float = 1.0
        for stage in self.pitchStages {
            rate *= stage.rate
        }
        return rate
    }

    var isPitchOnly: Bool {
        return self.eqBands.isEmpty && self.distortionStages.isEmpty && self.delay == nil && self.reverb == nil
    }

    func pitchOnlyFallback() -> MiraVoiceChangerEffectParams {
        var fallback = MiraVoiceChangerEffectParams()
        if !self.pitchStages.isEmpty {
            fallback.pitchStages = self.pitchStages
        } else {
            fallback.pitchStages = [(-300.0, 1.0)]
        }
        return fallback
    }

    init?(preset: Int32) {
        guard let value = MiraVoiceChangerPreset(rawValue: preset), value != .off else {
            return nil
        }
        switch value {
        case .off:
            return nil
        case .chipmunk:
            self.pitchStages = [(700.0, 1.0)]
        case .deep:
            self.pitchStages = [(-600.0, 1.0)]
        case .robot:
            self.distortionStages = [(.multiDecimated1, 65.0)]
        case .helium:
            self.pitchStages = [(1000.0, 1.06)]
        case .echo:
            self.delay = (0.3, 50.0, 45.0)
            self.tailSeconds = 1.0
        case .child:
            self.pitchStages = [(400.0, 1.0)]
        case .radio:
            self.eqBands = [
                MiraVoiceChangerEQBand(filterType: .highPass, frequency: 500.0),
                MiraVoiceChangerEQBand(filterType: .lowPass, frequency: 3200.0)
            ]
            self.distortionStages = [(.speechRadioTower, 30.0)]
        case .reverb:
            self.reverb = (.cathedral, 45.0)
            self.tailSeconds = 1.5
        case .anonymous:
            self.pitchStages = [(-350.0, 0.92)]
            self.eqBands = [
                MiraVoiceChangerEQBand(filterType: .lowShelf, frequency: 220.0, gain: -12.0)
            ]
            self.distortionStages = [(.multiDecimated1, 25.0)]
        case .anonymousPro:
            self.pitchStages = [(400.0, 1.0), (-750.0, 1.03)]
            self.eqBands = [
                MiraVoiceChangerEQBand(filterType: .lowShelf, frequency: 250.0, gain: 3.0),
                MiraVoiceChangerEQBand(filterType: .highShelf, frequency: 3800.0, gain: -7.0)
            ]
        case .demon:
            self.pitchStages = [(-900.0, 1.0)]
            self.distortionStages = [(.multiDecimated3, 60.0)]
            self.reverb = (.largeHall, 20.0)
            self.tailSeconds = 0.6
        case .cyber:
            self.distortionStages = [(.speechCosmicInterference, 50.0), (.drumsBitBrush, 35.0)]
            self.eqBands = [
                MiraVoiceChangerEQBand(filterType: .highPass, frequency: 250.0),
                MiraVoiceChangerEQBand(filterType: .lowPass, frequency: 7000.0)
            ]
        case .masked:
            self.pitchStages = [(250.0, 0.85)]
            self.eqBands = [
                MiraVoiceChangerEQBand(filterType: .parametric, frequency: 1500.0, bandwidth: 1.2, gain: 6.0)
            ]
        }
    }
}

public enum MiraVoiceChanger {
    private static let sampleRate: Double = 48000.0
    private static let encoderFrameSize = 960
    private static let maximumProcessingDuration: Double = 5.0 * 60.0

    public static func miraProcessVoiceMessage(sourceURL: URL, preset: Int32, completion: @escaping (URL?) -> Void) {
        miraProcessVoiceMessageDetailed(sourceURL: sourceURL, preset: preset, completion: { result in
            completion(result?.url)
        })
    }

    public static func miraProcessVoiceMessageDetailed(sourceURL: URL, preset: Int32, completion: @escaping (MiraProcessedVoiceMessage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = miraProcessVoiceMessageSynchronously(sourceURL: sourceURL, preset: preset)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    public static func miraProcessVoiceMessageData(_ data: Data, preset: Int32, completion: @escaping ((data: Data, duration: Double, waveform: Data?)?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let inputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mira-voice-input-\(Int64.random(in: 0 ..< Int64.max)).ogg")
            var result: MiraProcessedVoiceMessage?
            if (try? data.write(to: inputURL, options: [])) != nil {
                result = miraProcessVoiceMessageSynchronously(sourceURL: inputURL, preset: preset)
            }
            try? FileManager.default.removeItem(at: inputURL)

            var output: (data: Data, duration: Double, waveform: Data?)?
            if let result = result, let processedData = try? Data(contentsOf: result.url) {
                output = (processedData, result.duration, result.waveform)
                try? FileManager.default.removeItem(at: result.url)
            }
            DispatchQueue.main.async {
                completion(output)
            }
        }
    }

    public static func miraProcessVoiceMessageSynchronously(sourceURL: URL, preset: Int32) -> MiraProcessedVoiceMessage? {
        guard let params = MiraVoiceChangerEffectParams(preset: preset) else {
            return nil
        }
        guard let pcmSamples = decodeOggOpus(path: sourceURL.path), !pcmSamples.isEmpty else {
            return nil
        }
        var effectSamples = applyEffects(samples: pcmSamples, params: params)
        if (effectSamples == nil || effectSamples!.isEmpty), !params.isPitchOnly {
            effectSamples = applyEffects(samples: pcmSamples, params: params.pitchOnlyFallback())
        }
        guard let processedSamples = effectSamples, !processedSamples.isEmpty else {
            return nil
        }
        guard let encodedData = encodeOggOpus(samples: processedSamples) else {
            return nil
        }
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mira-voice-\(Int64.random(in: 0 ..< Int64.max)).ogg")
        do {
            try encodedData.write(to: outputURL, options: [])
        } catch {
            return nil
        }
        let duration = Double(processedSamples.count) / sampleRate
        let waveform = makeWaveformBitstream(samples: processedSamples)
        return MiraProcessedVoiceMessage(url: outputURL, duration: duration, waveform: waveform)
    }

    private static func decodeOggOpus(path: String) -> [Int16]? {
        guard let reader = OggOpusReader(path: path) else {
            return nil
        }
        let capacity = encoderFrameSize * 8
        let buffer = UnsafeMutablePointer<Int16>.allocate(capacity: capacity)
        defer {
            buffer.deallocate()
        }
        var samples: [Int16] = []
        let maximumSampleCount = Int(sampleRate * maximumProcessingDuration)
        while true {
            let count = reader.read(buffer, bufSize: Int32(capacity * MemoryLayout<Int16>.size))
            if count <= 0 {
                break
            }
            let sampleCount = Int(count)
            guard sampleCount <= capacity, sampleCount <= maximumSampleCount - samples.count else {
                return nil
            }
            samples.append(contentsOf: UnsafeBufferPointer(start: buffer, count: sampleCount))
        }
        return samples
    }

    private static func applyEffects(samples: [Int16], params: MiraVoiceChangerEffectParams) -> [Int16]? {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else {
            return nil
        }

        let inputFrameCount = AVAudioFrameCount(samples.count)
        guard inputFrameCount > 0 else {
            return nil
        }
        let tailFrameCount = AVAudioFrameCount(params.tailSeconds * sampleRate)

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: inputFrameCount) else {
            return nil
        }
        inputBuffer.frameLength = inputFrameCount
        if let channelData = inputBuffer.floatChannelData?[0] {
            for i in 0 ..< samples.count {
                channelData[i] = Float(samples[i]) / 32768.0
            }
        } else {
            return nil
        }

        var tailBuffer: AVAudioPCMBuffer?
        if tailFrameCount > 0 {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: tailFrameCount) else {
                return nil
            }
            buffer.frameLength = tailFrameCount
            if let channelData = buffer.floatChannelData?[0] {
                memset(channelData, 0, Int(tailFrameCount) * MemoryLayout<Float>.size)
            }
            tailBuffer = buffer
        }

        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)

        var lastNode: AVAudioNode = playerNode
        for stage in params.pitchStages {
            let timePitch = AVAudioUnitTimePitch()
            timePitch.pitch = stage.pitchCents
            timePitch.rate = stage.rate
            engine.attach(timePitch)
            engine.connect(lastNode, to: timePitch, format: format)
            lastNode = timePitch
        }
        if !params.eqBands.isEmpty {
            let eq = AVAudioUnitEQ(numberOfBands: params.eqBands.count)
            for i in 0 ..< params.eqBands.count {
                let bandParams = params.eqBands[i]
                let band = eq.bands[i]
                band.filterType = bandParams.filterType
                band.frequency = bandParams.frequency
                band.bandwidth = bandParams.bandwidth
                band.gain = bandParams.gain
                band.bypass = false
            }
            engine.attach(eq)
            engine.connect(lastNode, to: eq, format: format)
            lastNode = eq
        }
        for distortion in params.distortionStages {
            let distortionNode = AVAudioUnitDistortion()
            distortionNode.loadFactoryPreset(distortion.preset)
            distortionNode.wetDryMix = distortion.wetDryMix
            engine.attach(distortionNode)
            engine.connect(lastNode, to: distortionNode, format: format)
            lastNode = distortionNode
        }
        if let delay = params.delay {
            let delayNode = AVAudioUnitDelay()
            delayNode.delayTime = delay.time
            delayNode.feedback = delay.feedback
            delayNode.wetDryMix = delay.wetDryMix
            delayNode.lowPassCutoff = 8000.0
            engine.attach(delayNode)
            engine.connect(lastNode, to: delayNode, format: format)
            lastNode = delayNode
        }
        if let reverb = params.reverb {
            let reverbNode = AVAudioUnitReverb()
            reverbNode.loadFactoryPreset(reverb.preset)
            reverbNode.wetDryMix = reverb.wetDryMix
            engine.attach(reverbNode)
            engine.connect(lastNode, to: reverbNode, format: format)
            lastNode = reverbNode
        }
        engine.connect(lastNode, to: engine.mainMixerNode, format: format)

        let maximumFrameCount: AVAudioFrameCount = 4096
        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maximumFrameCount)
        } catch {
            return nil
        }
        do {
            try engine.start()
        } catch {
            return nil
        }

        playerNode.scheduleBuffer(inputBuffer)
        if let tailBuffer = tailBuffer {
            playerNode.scheduleBuffer(tailBuffer)
        }
        playerNode.play()

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maximumFrameCount) else {
            engine.stop()
            return nil
        }

        var outputSamples: [Int16] = []
        outputSamples.reserveCapacity(samples.count + Int(tailFrameCount))

        let expectedFrames = AVAudioFramePosition(Double(inputFrameCount + tailFrameCount) / Double(max(params.totalRate, 0.25)))
        let maxOutputFrames = expectedFrames + AVAudioFramePosition(sampleRate * 2.0)

        renderLoop: while engine.manualRenderingSampleTime < maxOutputFrames {
            let status: AVAudioEngineManualRenderingStatus
            do {
                status = try engine.renderOffline(maximumFrameCount, to: outputBuffer)
            } catch {
                engine.stop()
                return nil
            }
            switch status {
            case .success:
                let renderedFrames = Int(outputBuffer.frameLength)
                if renderedFrames == 0 {
                    break renderLoop
                }
                if let channelData = outputBuffer.floatChannelData?[0] {
                    for i in 0 ..< renderedFrames {
                        let clamped = max(-1.0, min(1.0, channelData[i]))
                        outputSamples.append(Int16((Double(clamped) * 32767.0).rounded()))
                    }
                }
            case .insufficientDataFromInputNode:
                break renderLoop
            case .cannotDoInCurrentContext, .error:
                break renderLoop
            @unknown default:
                break renderLoop
            }
        }
        engine.stop()

        if outputSamples.isEmpty {
            return nil
        }
        return outputSamples
    }

    private static func encodeOggOpus(samples: [Int16]) -> Data? {
        let writer = TGOggOpusWriter()
        let dataItem = TGDataItem()
        guard writer.begin(with: dataItem) else {
            return nil
        }
        var offset = 0
        while offset < samples.count {
            let count = min(encoderFrameSize, samples.count - offset)
            let success = samples.withUnsafeBufferPointer { bufferPointer -> Bool in
                guard let baseAddress = bufferPointer.baseAddress else {
                    return false
                }
                return writer.writeFrame(UnsafeMutableRawPointer(mutating: baseAddress.advanced(by: offset)).assumingMemoryBound(to: UInt8.self), frameByteCount: UInt(count * MemoryLayout<Int16>.size))
            }
            if !success {
                return nil
            }
            offset += count
        }
        guard writer.writeFrame(nil, frameByteCount: 0) else {
            return nil
        }
        return dataItem.data()
    }

    private static func makeWaveformBitstream(samples: [Int16]) -> Data? {
        guard !samples.isEmpty else {
            return nil
        }
        var scaledSamples = [Int16](repeating: 0, count: 100)
        for i in 0 ..< samples.count {
            var sample = samples[i]
            if sample < 0 {
                sample = sample == Int16.min ? Int16.max : -sample
            }
            let index = i * 100 / samples.count
            if scaledSamples[index] < sample {
                scaledSamples[index] = sample
            }
        }
        var sumSamples: Int64 = 0
        for sample in scaledSamples {
            sumSamples += Int64(sample)
        }
        var calculatedPeak = Int64(Double(sumSamples) * 1.8 / 100.0)
        if calculatedPeak < 2500 {
            calculatedPeak = 2500
        }
        var quantized = [Int16](repeating: 0, count: 100)
        for i in 0 ..< 100 {
            let minPeak = min(Int64(scaledSamples[i]), calculatedPeak)
            let resultPeak = minPeak * 31 / calculatedPeak
            quantized[i] = Int16(clamping: min(31, resultPeak))
        }
        let samplesData = quantized.withUnsafeBufferPointer { Data(buffer: $0) }
        return AudioWaveform(samples: samplesData, peak: 31).makeBitstream()
    }
}
