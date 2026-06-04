import AVFoundation
import Foundation

final class MicLevelMonitor {
    private var engine: AVAudioEngine?

    func start(onLevel: @escaping @MainActor (Double) -> Void) throws {
        stop()

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            return
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            let level = Self.normalizedLevel(from: buffer)
            Task { @MainActor in
                onLevel(level)
            }
        }

        try engine.start()
        self.engine = engine
    }

    func stop() {
        guard let engine else {
            return
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    private static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData,
              buffer.frameLength > 0 else {
            return 0
        }

        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        var sum: Float = 0

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for index in 0..<frameCount {
                let sample = samples[index]
                sum += sample * sample
            }
        }

        let mean = sum / Float(max(channelCount * frameCount, 1))
        let rms = sqrt(mean)
        let decibels = 20 * log10(max(rms, 0.000_001))
        return max(0, min(1, Double((decibels + 60) / 48)))
    }
}
