//
//  SineEngine.swift
//  SimpleSpeed
//
//  Created by verdi65 on 10/14/25.
//


import Foundation
import AVFoundation

final class SineEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffers: [Int: AVAudioPCMBuffer] = [:] // midi -> 1s tone
    
    func start() {
        let hwFormat = engine.outputNode.inputFormat(forBus: 0)
        let monoFormat = AVAudioFormat(standardFormatWithSampleRate: hwFormat.sampleRate, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: monoFormat)
        prepareNoteBank(sampleRate: monoFormat.sampleRate)
        do {
            try engine.start()
        } catch {
            print("Audio engine failed: \(error)")
        }
        player.play()
    }
    
    func play(midi: Int, duration: Double = 1.0) {
        guard let base = buffers[midi] else { return }
        // For duration <= 1.0, we can schedule part of the buffer; keep it simple: schedule full 1s
        player.scheduleBuffer(base, at: nil, options: [], completionHandler: nil)
    }
    
    private func prepareNoteBank(sampleRate: Double) {
        // Build 1-second sines for white keys C4–B4
        let whiteMIDIs = [60, 62, 64, 65, 67, 69, 71]
        for m in whiteMIDIs {
            buffers[m] = makeSineBuffer(midi: m, seconds: 1.0, sampleRate: sampleRate)
        }
    }
    
    private func makeSineBuffer(midi: Int, seconds: Double, sampleRate: Double) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(seconds * sampleRate)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let freq = 440.0 * pow(2.0, (Double(midi) - 69.0) / 12.0)
        let twoPi = 2.0 * Double.pi
        let phaseStep = twoPi * freq / sampleRate
        
        // Simple 10ms fade-in/out to avoid clicks
        let fadeSamples = Int(0.010 * sampleRate)
        var phase = 0.0
        if let ptr = buffer.floatChannelData?.pointee {
            let total = Int(frameCount)
            for n in 0..<total {
                var s = sin(phase)
                // apply fade
                if n < fadeSamples {
                    s *= Double(n) / Double(fadeSamples)
                } else if n >= total - fadeSamples {
                    let k = total - n
                    s *= Double(k) / Double(fadeSamples)
                }
                ptr[n] = Float(s) * 0.2 // conservative level
                phase += phaseStep
                if phase > twoPi { phase -= twoPi }
            }
        }
        return buffer
    }
}
