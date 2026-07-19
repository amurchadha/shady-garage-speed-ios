// AudioEngine.swift — port of audio.js: tiny synth SFX via AVAudioEngine.
// All sounds are pre-rendered to mono Float32 PCM buffers (44.1kHz) with the
// same envelopes/slides as the WebAudio version; playback is one-shot scheduling.
import AVFoundation

final class AudioEngine {
    static let shared = AudioEngine()

    private let engine = AVAudioEngine()
    private var oneShots: [AVAudioPlayerNode] = []
    private var oneShotIndex = 0
    private let nosPlayer = AVAudioPlayerNode()
    private var started = false
    private var nosOn = false

    private let sampleRate: Double = 44100
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var beepCache: [Int: AVAudioPCMBuffer] = [:]
    private var nosAttack: AVAudioPCMBuffer?
    private var nosLoop: AVAudioPCMBuffer?
    private var nosFade: AVAudioPCMBuffer?

    private init() {
        // mono connection format — buffers are mono; the mixer upmixes.
        let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        for _ in 0..<6 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: mono)
            oneShots.append(p)
        }
        engine.attach(nosPlayer)
        engine.connect(nosPlayer, to: engine.mainMixerNode, format: mono)
        buildBuffers()
    }

    // MARK: engine lifecycle

    private func ensureStarted() {
        guard !started else { return }
        started = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        try? engine.start()
        for p in oneShots { p.play() }
    }

    // MARK: synth

    private enum Wave { case sine, square, saw, triangle }

    private func waveSample(_ w: Wave, _ phase: Double) -> Float {
        let p = phase - floor(phase)
        switch w {
        case .sine:     return Float(sin(2 * .pi * phase))
        case .square:   return p < 0.5 ? 1 : -1
        case .saw:      return Float(2 * p - 1)
        case .triangle: return Float(2 * abs(2 * p - 1) - 1)
        }
    }

    private struct Tone {
        var freq: Double
        var dur: Double
        var wave: Wave
        var vol: Double
        var delay: Double = 0
        var slideTo: Double? = nil
    }

    /// Render tones summed into one buffer. Envelope matches WebAudio:
    /// gain decays exponentially from vol to 0.0001 over dur.
    private func render(_ tones: [Tone], tailPad: Double = 0.05) -> AVAudioPCMBuffer? {
        let totalDur = (tones.map { $0.delay + $0.dur }.max() ?? 0) + tailPad
        guard totalDur > 0 else { return nil }
        let frames = AVAudioFrameCount(max(1, Int(totalDur * sampleRate)))
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        for tone in tones {
            let start = Int(tone.delay * sampleRate)
            let n = Int(tone.dur * sampleRate)
            var phase = 0.0
            for i in 0..<n {
                let t = Double(i) / sampleRate
                var f = tone.freq
                if let s = tone.slideTo, tone.freq > 0 {
                    f = tone.freq * pow(max(1, s) / tone.freq, t / tone.dur)
                }
                phase += f / sampleRate
                let g = tone.vol * pow(0.0001 / tone.vol, t / tone.dur)
                data[start + i] += Float(g) * waveSample(tone.wave, phase)
            }
        }
        return buffer
    }

    /// Custom render for the NOS loop family: explicit freq(t)/gain(t) curves, loop-friendly.
    private func renderCurve(dur: Double, freq: (Double) -> Double, gain: (Double) -> Double) -> AVAudioPCMBuffer? {
        let n = Int(dur * sampleRate)
        guard n > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(n)
        let data = buffer.floatChannelData![0]
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sampleRate
            phase += freq(t) / sampleRate
            data[i] = Float(gain(t)) * waveSample(.saw, phase)
        }
        return buffer
    }

    private func buildBuffers() {
        buffers["click"] = render([Tone(freq: 700, dur: 0.06, wave: .square, vol: 0.07)])
        buffers["cash"] = render([
            Tone(freq: 880, dur: 0.09, wave: .square, vol: 0.1),
            Tone(freq: 1318, dur: 0.15, wave: .square, vol: 0.1, delay: 0.08),
        ])
        buffers["success"] = render([
            Tone(freq: 523, dur: 0.1, wave: .triangle, vol: 0.12),
            Tone(freq: 659, dur: 0.1, wave: .triangle, vol: 0.12, delay: 0.09),
            Tone(freq: 784, dur: 0.18, wave: .triangle, vol: 0.12, delay: 0.18),
        ])
        buffers["fail"] = render([Tone(freq: 220, dur: 0.28, wave: .saw, vol: 0.12, slideTo: 110)])

        // NOS: 0.7s attack ramp 120→520Hz with 6Hz ±35 wobble, then steady loop.
        let wobble: (Double) -> Double = { t in 35 * sin(2 * .pi * 6 * t) }
        nosAttack = renderCurve(dur: 0.7,
            freq: { t in 120 * pow(520 / 120, t / 0.7) + wobble(t) },
            gain: { t in min(0.08, 0.0001 * pow(0.08 / 0.0001, t / 0.15)) })
        // loop: steady 520Hz + wobble; 0.5s holds exactly 260 cycles & 3 wobbles → seamless.
        nosLoop = renderCurve(dur: 0.5, freq: { t in 520 + wobble(t) }, gain: { _ in 0.08 })
        nosFade = renderCurve(dur: 0.2,
            freq: { t in 520 + wobble(t) },
            gain: { t in 0.08 * pow(0.0001 / 0.08, t / 0.2) })
    }

    // MARK: playback (mirrors web sfx API)

    private func play(_ name: String) {
        guard let buffer = buffers[name] else { return }
        ensureStarted()
        oneShotIndex = (oneShotIndex + 1) % oneShots.count
        let p = oneShots[oneShotIndex]
        p.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !p.isPlaying { p.play() }
    }

    func click()   { play("click") }
    func cash()    { play("cash") }
    func success() { play("success") }
    func fail()    { play("fail") }

    func beep(_ f: Double = 440) {
        ensureStarted()
        let key = Int(f)
        if beepCache[key] == nil {
            beepCache[key] = render([Tone(freq: f, dur: 0.13, wave: .sine, vol: 0.15)])
        }
        guard let buffer = beepCache[key] else { return }
        oneShotIndex = (oneShotIndex + 1) % oneShots.count
        let p = oneShots[oneShotIndex]
        p.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !p.isPlaying { p.play() }
    }

    func nos(_ on: Bool) {
        if on {
            guard !nosOn else { return }
            nosOn = true
            ensureStarted()
            guard let attack = nosAttack, let loop = nosLoop else { return }
            nosPlayer.stop()
            nosPlayer.scheduleBuffer(attack, at: nil, options: [], completionHandler: nil)
            nosPlayer.scheduleBuffer(loop, at: nil, options: .loops, completionHandler: nil)
            nosPlayer.play()
        } else {
            guard nosOn else { return }
            nosOn = false
            nosPlayer.stop()
            if let fade = nosFade {
                nosPlayer.scheduleBuffer(fade, at: nil, options: [], completionHandler: nil)
                nosPlayer.play()
            }
        }
    }
}
