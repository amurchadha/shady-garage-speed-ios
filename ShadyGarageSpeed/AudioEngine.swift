// AudioEngine.swift — port of audio.js: tiny synth SFX via AVAudioEngine.
// All sounds are pre-rendered to mono Float32 PCM buffers (44.1kHz) with the
// same envelopes/slides as the WebAudio version; playback is one-shot scheduling.
// Every playback path is fail-silent: an interrupted/dead engine must never
// crash a tap handler (playerNode.play() raises an NSException — uncatchable
// in Swift — when the engine isn't running, so we guard instead of catch).
import AVFoundation

final class AudioEngine: ObservableObject {
    static let shared = AudioEngine()

    private let engine = AVAudioEngine()
    private var oneShots: [AVAudioPlayerNode] = []
    private var oneShotIndex = 0
    private let nosPlayer = AVAudioPlayerNode()
    private let enginePlayer = AVAudioPlayerNode()
    private let musicPlayer = AVAudioPlayerNode()
    /// Bus split (web #37): SFX voices → sfxBus, music → musicBus; both → mainMixer.
    private let sfxBus = AVAudioMixerNode()
    private let musicBus = AVAudioMixerNode()
    private let lock = NSRecursiveLock() // sfx fire from both main and render threads
    private var started = false          // engine ran at least once (gates auto-resume)
    private var interrupted = false      // inside an AVAudioSession interruption
    private var nosOn = false
    private var engineOn = false

    /// Master mute, persisted; applied to the main mixer so every node is silenced.
    @Published var muted = UserDefaults.standard.bool(forKey: "sgs_muted") {
        didSet {
            UserDefaults.standard.set(muted, forKey: "sgs_muted")
            engine.mainMixerNode.outputVolume = muted ? 0 : 1
        }
    }

    /// Music volume (persisted; web default 0.5) — live slider target.
    @Published var musicVol: Float = UserDefaults.standard.object(forKey: "sgs_musicVol") as? Float ?? 0.5 {
        didSet {
            UserDefaults.standard.set(musicVol, forKey: "sgs_musicVol")
            lock.lock()
            musicBus.volume = musicVol
            lock.unlock()
        }
    }

    /// SFX volume (persisted; web default 1.0) — live slider target.
    @Published var sfxVol: Float = UserDefaults.standard.object(forKey: "sgs_sfxVol") as? Float ?? 1.0 {
        didSet {
            UserDefaults.standard.set(sfxVol, forKey: "sgs_sfxVol")
            lock.lock()
            sfxBus.volume = sfxVol
            lock.unlock()
        }
    }

    private let sampleRate: Double = 44100
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var beepCache: [Int: AVAudioPCMBuffer] = [:]
    private var nosAttack: AVAudioPCMBuffer?
    private var nosLoop: AVAudioPCMBuffer?
    private var nosFade: AVAudioPCMBuffer?
    private var engineLoop: AVAudioPCMBuffer?

    // MARK: music (garage radio + race loop; web SONGS note data)

    private struct Chord { let root: Double; let tones: [Double] }
    private static let chords: [String: Chord] = [
        "Am": Chord(root: 110.00, tones: [220.00, 261.63, 329.63]),
        "F":  Chord(root: 87.31,  tones: [174.61, 220.00, 261.63]),
        "C":  Chord(root: 130.81, tones: [261.63, 329.63, 392.00]),
        "G":  Chord(root: 98.00,  tones: [196.00, 246.94, 293.66]),
    ]
    private struct SongNote { var freq: Double; var dur: Double; var wave: Wave; var vol: Double }
    private var songSteps: [String: [AVAudioPCMBuffer]] = [:]
    private var songStepDur: [String: Double] = ["garage": 60.0 / 72 / 2, "race": 60.0 / 128 / 2]
    private var musSong: String? = nil
    private var musStep = 0
    private var musicGen = 0
    private var duckUntil = Date.distantPast

    private init() {
        // mono connection format — buffers are mono; the mixer upmixes.
        let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        engine.attach(sfxBus)
        engine.attach(musicBus)
        engine.connect(sfxBus, to: engine.mainMixerNode, format: nil)
        engine.connect(musicBus, to: engine.mainMixerNode, format: nil)
        for _ in 0..<6 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: sfxBus, format: mono)
            oneShots.append(p)
        }
        engine.attach(nosPlayer)
        engine.connect(nosPlayer, to: sfxBus, format: mono)
        engine.attach(enginePlayer)
        engine.connect(enginePlayer, to: sfxBus, format: mono)
        engine.attach(musicPlayer)
        engine.connect(musicPlayer, to: musicBus, format: mono)
        sfxBus.volume = sfxVol
        musicBus.volume = musicVol
        engine.mainMixerNode.outputVolume = muted ? 0 : 1
        buildBuffers()
        installObservers()
    }

    func toggleMute() { muted = !muted }

    // MARK: engine lifecycle

    /// Start (or restart) the engine. Returns false when audio is unavailable —
    /// every caller treats that as "stay silent", never as an error.
    @discardableResult
    private func ensureRunningLocked() -> Bool {
        if engine.isRunning { return true }
        guard !interrupted else { return false }
        let session = AVAudioSession.sharedInstance()
        do {
            // .ambient + .mixWithOthers: background music apps keep playing.
            try session.setCategory(.ambient, options: .mixWithOthers)
            try session.setActive(true)
        } catch {
            return false // session busy (e.g. interruption winding down) — retry next call
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            return false
        }
        started = true
        resumeNodesLocked()
        return true
    }

    /// After an engine restart, player nodes that should be sounding need play() again.
    private func resumeNodesLocked() {
        guard engine.isRunning else { return }
        for p in oneShots where !p.isPlaying { p.play() }
        if nosOn { startNosLocked() }
        if engineOn { startEngineLocked() }
        if musSong != nil { reseedMusicLocked() } // scheduled steps don't survive a restart
    }

    /// Dip the music bus −6dB under a one-shot SFX; slow release (web duck()).
    private func duckMusic(_ hold: Double) {
        guard musSong != nil else { return }
        duckUntil = Date().addingTimeInterval(hold + 0.25)
        musicBus.volume = musicVol * 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + hold + 0.25) { [weak self] in
            guard let self, Date() >= self.duckUntil else { return }
            self.lock.lock()
            self.musicBus.volume = self.musicVol
            self.lock.unlock()
        }
    }

    /// Observe interruptions (phone call, Siri, alarm), route changes and engine
    /// configuration changes — all three can kill the AVAudioEngine under us.
    /// (Observer tokens are never removed: the singleton outlives the app.)
    private func installObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                self.lock.lock()
                self.interrupted = true
                self.engine.pause() // graceful: rendering halts, nodes keep their schedules
                self.lock.unlock()
            case .ended:
                let opts = AVAudioSession.InterruptionOptions(
                    rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                self.lock.lock()
                self.interrupted = false
                let shouldResume = opts.contains(.shouldResume) && self.started
                self.lock.unlock()
                if shouldResume { self.recover() }
            @unknown default:
                break
            }
        }
        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.recover()
        }
        // The engine can also die on its own (device switch, sample-rate change):
        // AVAudioEngine stops itself and only posts this notification.
        nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil) { [weak self] _ in
            self?.recover()
        }
    }

    /// Restart the engine after a system event if the game had audio running.
    private func recover() {
        lock.lock()
        defer { lock.unlock() }
        guard started, !interrupted, !engine.isRunning else { return }
        _ = ensureRunningLocked()
    }

    // MARK: synth

    private enum Wave { case sine, square, saw, triangle, noise }

    private func waveSample(_ w: Wave, _ phase: Double) -> Float {
        let p = phase - floor(phase)
        switch w {
        case .sine:     return Float(sin(2 * .pi * phase))
        case .square:   return p < 0.5 ? 1 : -1
        case .saw:      return Float(2 * p - 1)
        case .triangle: return Float(2 * abs(2 * p - 1) - 1)
        case .noise:    return Float.random(in: -1...1)
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
        // new-best fanfare: ascending C-major arpeggio
        buffers["fanfare"] = render([
            Tone(freq: 523, dur: 0.12, wave: .triangle, vol: 0.12),
            Tone(freq: 659, dur: 0.12, wave: .triangle, vol: 0.12, delay: 0.10),
            Tone(freq: 784, dur: 0.12, wave: .triangle, vol: 0.12, delay: 0.20),
            Tone(freq: 1046, dur: 0.32, wave: .triangle, vol: 0.13, delay: 0.30),
        ])
        // ratchet ticks for the fix moment
        buffers["ratchet"] = render([
            Tone(freq: 1400, dur: 0.03, wave: .square, vol: 0.07),
            Tone(freq: 1400, dur: 0.03, wave: .square, vol: 0.07, delay: 0.055),
            Tone(freq: 1400, dur: 0.03, wave: .square, vol: 0.07, delay: 0.11),
        ])

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

        // engine loop: 60Hz saw with 6Hz ±8Hz wobble; 0.5s holds exactly 30
        // cycles & 3 wobbles → seamless loop; varispeed 1–3× gives 60→180Hz.
        engineLoop = renderCurve(dur: 0.5,
            freq: { t in 60 + 8 * sin(2 * .pi * 6 * t) },
            gain: { _ in 0.14 })

        // filtered-noise loop sources (played as loops with live gain)
        buildNoiseBuffer()
        makeNoiseLoop("skid", kind: "bandpass", freq: 900, q: 1.8, baseGain: 0.12)  // #33 ∝ slip
        makeNoiseLoop("rumble", kind: "lowpass", freq: 220, q: 0.6, baseGain: 0.14) // #35 ∝ speed
        makeNoiseLoop("rain", kind: "lowpass", freq: 1400, q: 0.4, baseGain: 0.05)  // #38 patter
        makeNoiseLoop("shophum", kind: "lowpass", freq: 320, q: 0.5, baseGain: 0.03) // #36 bed
    }

    // MARK: playback (mirrors web sfx API) — all fail-silent

    private func play(_ name: String) {
        guard let buffer = buffers[name] else { return }
        lock.lock()
        defer { lock.unlock() }
        guard ensureRunningLocked() else { return }
        duckMusic(0.25)
        oneShotIndex = (oneShotIndex + 1) % oneShots.count
        let p = oneShots[oneShotIndex]
        p.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !p.isPlaying { p.play() }
    }

    func click()   { play("click") }
    func cash()    { play("cash") }
    func success() { play("success") }
    func fail()    { play("fail") }
    func fanfare() { play("fanfare") }
    func ratchet() { play("ratchet") }

    func beep(_ f: Double = 440) {
        lock.lock()
        defer { lock.unlock() }
        let key = Int(f)
        if beepCache[key] == nil {
            beepCache[key] = render([Tone(freq: f, dur: 0.13, wave: .sine, vol: 0.15)])
        }
        guard let buffer = beepCache[key], ensureRunningLocked() else { return }
        oneShotIndex = (oneShotIndex + 1) % oneShots.count
        let p = oneShots[oneShotIndex]
        p.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !p.isPlaying { p.play() }
    }

    func nos(_ on: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if on {
            guard !nosOn else { return }
            nosOn = true
            guard ensureRunningLocked() else { return }
            startNosLocked()
        } else {
            guard nosOn else { return }
            nosOn = false
            nosPlayer.stop()
            if engine.isRunning, let fade = nosFade {
                nosPlayer.scheduleBuffer(fade, at: nil, options: [], completionHandler: nil)
                nosPlayer.play()
            }
        }
    }

    private func startNosLocked() {
        guard engine.isRunning, let attack = nosAttack, let loop = nosLoop else { return }
        nosPlayer.stop()
        nosPlayer.scheduleBuffer(attack, at: nil, options: [], completionHandler: nil)
        nosPlayer.scheduleBuffer(loop, at: nil, options: .loops, completionHandler: nil)
        nosPlayer.play()
    }

    // MARK: engine loop (race): 60Hz base, varispeed 1–3× tracks speed 60→180Hz

    func engineSound(_ on: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if on {
            guard !engineOn else { return }
            engineOn = true
            guard ensureRunningLocked() else { return }
            startEngineLocked()
        } else {
            guard engineOn else { return }
            engineOn = false
            enginePlayer.stop()
        }
    }

    /// 0…1 of top speed → playback rate 1…3 (i.e. 60→180Hz).
    func setEngineRPM(_ frac: Double) {
        lock.lock()
        enginePlayer.rate = Float(1 + 2 * min(1, max(0, frac)))
        lock.unlock()
    }

    private func startEngineLocked() {
        guard engine.isRunning, let loop = engineLoop else { return }
        enginePlayer.stop()
        enginePlayer.scheduleBuffer(loop, at: nil, options: .loops, completionHandler: nil)
        enginePlayer.play()
    }

    // MARK: filtered-noise loops (#33 skid / #35 rumble / #38 rain / #36 hum)

    /// A persistent filtered-noise loop with idempotent start/stop + live gain,
    /// matching the web's makeNoiseLoop (gain = baseGain × level).
    private final class NoiseLoop {
        let player: AVAudioPlayerNode
        var baseGain: Float
        var active = false
        init(_ player: AVAudioPlayerNode, _ baseGain: Float) {
            self.player = player
            self.baseGain = baseGain
        }
    }
    private var noiseBuffer: AVAudioPCMBuffer?
    private var noiseLoops: [String: NoiseLoop] = [:]

    private func buildNoiseBuffer() {
        let n = Int(sampleRate * 2) // 2s, looped
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)) else { return }
        buf.frameLength = AVAudioFrameCount(n)
        let d = buf.floatChannelData![0]
        for i in 0..<n { d[i] = Float.random(in: -1...1) }
        noiseBuffer = buf
    }

    /// Bake a one-pole filter into `frames` of white noise (lowpass or bandpass).
    private func filteredNoise(_ kind: String, freq: Double, q: Double) -> AVAudioPCMBuffer? {
        guard let src = noiseBuffer else { return nil }
        let n = Int(src.frameLength)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)) else { return nil }
        buf.frameLength = AVAudioFrameCount(n)
        let s = src.floatChannelData![0]
        let d = buf.floatChannelData![0]
        if kind == "lowpass" {
            // one-pole lowpass; freq ≈ cutoff
            let rc = 1.0 / (2 * .pi * freq)
            let a = 1.0 / (1.0 + rc * sampleRate)
            var y: Float = 0
            for i in 0..<n { y += Float(1 - a) * (s[i] - y); d[i] = y * 2.2 }
        } else {
            // bandpass ≈ lowpass(freq·(1+q)) minus lowpass(freq/(1+q))
            let rcHi = 1.0 / (2 * .pi * freq * (1 + q))
            let rcLo = 1.0 / (2 * .pi * max(30, freq / (1 + q)))
            let aHi = 1.0 / (1.0 + rcHi * sampleRate)
            let aLo = 1.0 / (1.0 + rcLo * sampleRate)
            var yHi: Float = 0, yLo: Float = 0
            for i in 0..<n {
                yHi += Float(1 - aHi) * (s[i] - yHi)
                yLo += Float(1 - aLo) * (s[i] - yLo)
                d[i] = (yHi - yLo) * 3.0
            }
        }
        return buf
    }

    private func makeNoiseLoop(_ name: String, kind: String, freq: Double, q: Double, baseGain: Float) {
        guard let buf = filteredNoise(kind, freq: freq, q: q) else { return }
        let p = AVAudioPlayerNode()
        engine.attach(p)
        engine.connect(p, to: sfxBus, format: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        p.scheduleBuffer(buf, at: nil, options: .loops, completionHandler: nil)
        p.volume = 0
        noiseLoops[name] = NoiseLoop(p, baseGain)
    }

    /// Idempotent start (volume ramps up on the next setLevel).
    private func loopStart(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let l = noiseLoops[name], !l.active, ensureRunningLocked() else { return }
        l.active = true
        l.player.volume = 0
        l.player.play()
        dbg("START", name)
    }

    private func loopStop(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let l = noiseLoops[name], l.active else { return }
        l.active = false
        l.player.volume = 0
        l.player.pause()
        dbg("STOP", name)
    }

    private func loopLevel(_ name: String, _ k: Float) {
        guard let l = noiseLoops[name], l.active else { return }
        l.player.volume = l.baseGain * max(0, min(1, k))
    }

    /// #38 rain patter for the whole rainy race.
    func rain(_ on: Bool) { on ? loopStart("rain") : loopStop("rain") }
    /// #33 skid sound on/off + #33 gain ∝ slip / #35 rumble gain ∝ speed.
    func skid(_ on: Bool) { on ? loopStart("skid") : loopStop("skid") }
    func skidLevel(_ k: Float) { loopLevel("skid", k) }
    func rumble(_ on: Bool) { on ? loopStart("rumble") : loopStop("rumble") }
    func rumbleLevel(_ k: Float) { loopLevel("rumble", k) }

    // MARK: #34 barrier thud (≤2 concurrent in a 150ms window)

    private var thudTimes: [TimeInterval] = []

    /// Impact-scaled thud: low 65Hz thump + filtered noise body (web thud()).
    func thud(_ k: Float) {
        lock.lock()
        defer { lock.unlock() }
        let now = Date().timeIntervalSince1970
        thudTimes = thudTimes.filter { now - $0 < 0.15 }
        guard thudTimes.count < 2 else { return }
        thudTimes.append(now)
        guard ensureRunningLocked() else { return }
        duckMusic(0.3)
        let kk = max(0, min(1, k))
        oneShotIndex = (oneShotIndex + 1) % oneShots.count
        let p = oneShots[oneShotIndex]
        if let buf = thudBodyCache(kk) {
            p.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
            if !p.isPlaying { p.play() }
        }
    }

    private var thudCache: [Int: AVAudioPCMBuffer] = [:]
    private func thudBodyCache(_ k: Float) -> AVAudioPCMBuffer? {
        let key = Int(k * 10)
        if let c = thudCache[key] { return c }
        // sine 65Hz → 38, 0.22s, vol 0.1+0.16k + lowpassed noise 0.12s, vol 0.06+0.1k
        let buf = render([
            Tone(freq: 65, dur: 0.22, wave: .sine, vol: Double(0.1 + 0.16 * k), slideTo: 38),
            Tone(freq: 65, dur: 0.22, wave: .sine, vol: 0.001), // keep envelope shape stable
        ])
        if let buf { thudCache[key] = buf }
        return buf
    }

    // MARK: sparse ambience (#36 build-bay bed / #39 shop sounds)

    private var ambTimer: Timer?
    private var clankTimer: Timer?
    private var humActive = false

    /// Schedule `fire` every minGap...maxGap seconds at random (web makeSparse).
    private func armSparse(_ slot: Int, minGap: Double, maxGap: Double, fire: @escaping () -> Void) -> Timer {
        Timer.scheduledTimer(withTimeInterval: minGap + Double.random(in: 0...(maxGap - minGap)), repeats: false) { [weak self] _ in
            guard let self else { return }
            fire()
            if slot == 0 {
                self.ambTimer = self.armSparse(slot, minGap: minGap, maxGap: maxGap, fire: fire)
            } else {
                self.clankTimer = self.armSparse(slot, minGap: minGap, maxGap: maxGap, fire: fire)
            }
        }
    }

    /// #39 garage shop sounds under the radio: wrench clink or compressor puff every 8–20s.
    func shopAmbience(_ on: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if on, self.ambTimer == nil {
                self.dbg("START", "shop-amb")
                self.ambTimer = self.armSparse(0, minGap: 8, maxGap: 20) { [weak self] in
                    self?.playShopSound()
                }
            } else if !on, let t = self.ambTimer {
                t.invalidate()
                self.ambTimer = nil
                self.dbg("STOP", "shop-amb")
            }
        }
    }

    private func playShopSound() {
        if Double.random(in: 0..<1) < 0.5 { // wrench clink: bright metallic tick + ring
            playTone(2100 + Double.random(in: 0..<900), 0.05, .triangle, 0.028)
            playTone(3200 + Double.random(in: 0..<600), 0.09, .sine, 0.016, delay: 0.03)
        } else { // compressor puff: soft filtered-noise exhale
            playNoiseHit(lowpassFreq: 750, dur: 0.28, vol: 0.035)
        }
    }

    /// #36 build-bay bed: low hum + distant clank every 10–25s (radio stays off).
    func buildBed(_ on: Bool) {
        if on {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.clankTimer == nil else { return }
                self.dbg("START", "shop-bed")
                self.loopStart("shophum")
                self.clankTimer = self.armSparse(1, minGap: 10, maxGap: 25) { [weak self] in
                    self?.playTone(280 + Double.random(in: 0..<120), 0.22, .triangle, 0.02, slideTo: 140)
                }
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.clankTimer != nil || self.humActive {
                    self.dbg("STOP", "shop-bed")
                }
                self.clankTimer?.invalidate()
                self.clankTimer = nil
                self.loopStop("shophum")
            }
        }
    }

    /// One-shot tone through the SFX pool (used by shop sounds/mumble).
    private func playTone(_ freq: Double, _ dur: Double, _ wave: Wave, _ vol: Double,
                          delay: Double = 0, slideTo: Double? = nil) {
        lock.lock()
        defer { lock.unlock() }
        guard let buf = render([Tone(freq: freq, dur: dur, wave: wave, vol: vol, delay: delay, slideTo: slideTo)]),
              ensureRunningLocked() else { return }
        duckMusic(dur + delay + 0.1)
        oneShotIndex = (oneShotIndex + 1) % oneShots.count
        let p = oneShots[oneShotIndex]
        p.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
        if !p.isPlaying { p.play() }
    }

    private var noiseHitCache: [Int: AVAudioPCMBuffer] = [:]
    private func playNoiseHit(lowpassFreq: Double, dur: Double, vol: Double) {
        lock.lock()
        defer { lock.unlock() }
        let key = Int(lowpassFreq)
        if noiseHitCache[key] == nil, let filtered = filteredNoise("lowpass", freq: lowpassFreq, q: 0.5) {
            // bake the envelope into a dur-length slice
            let frames = Int(dur * sampleRate)
            if let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
               let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) {
                buf.frameLength = AVAudioFrameCount(frames)
                let s = filtered.floatChannelData![0]
                let d = buf.floatChannelData![0]
                for i in 0..<frames {
                    let t = Double(i) / sampleRate
                    let g = vol * pow(0.0001 / vol, t / dur)
                    d[i] = s[i] * Float(g)
                }
                noiseHitCache[key] = buf
            }
        }
        guard let buf = noiseHitCache[key], ensureRunningLocked() else { return }
        duckMusic(dur + 0.1)
        oneShotIndex = (oneShotIndex + 1) % oneShots.count
        let p = oneShots[oneShotIndex]
        p.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
        if !p.isPlaying { p.play() }
    }

    // MARK: #40 mumble-blips (Animal-Crossing gibberish per archetype)

    private struct MumbleProfile { let base: Double, step: Double, n: ClosedRange<Int>, dur: Double, wave: Wave }
    private static let mumbles: [String: MumbleProfile] = [
        "skeptic":    MumbleProfile(base: 150, step: 0.11,  n: 3...4, dur: 0.07,  wave: .square),
        "rushed":     MumbleProfile(base: 540, step: 0.055, n: 4...5, dur: 0.045, wave: .square),
        "bigspender": MumbleProfile(base: 260, step: 0.1,   n: 3...5, dur: 0.08,  wave: .triangle),
        "regular":    MumbleProfile(base: 330, step: 0.08,  n: 3...4, dur: 0.06,  wave: .square),
    ]

    /// Played when a speech bubble shows (arrival/glance/rage/happy lines).
    func mumble(_ archetype: String) {
        let p = Self.mumbles[archetype] ?? Self.mumbles["regular"]!
        let n = Int.random(in: p.n)
        for i in 0..<n {
            playTone(p.base * (0.9 + Double.random(in: 0..<0.25)), p.dur, p.wave, 0.045, delay: Double(i) * p.step)
        }
    }

    // MARK: -audio-debug (loop orphan audit)

    /// Set from launch args; read at first use so the boot-time garage-radio
    /// START (AppState.init, before applyDebugArgs) is also captured.
    static var audioDebug = ProcessInfo.processInfo.arguments.contains("-audio-debug")
    private var loopCounts: [String: Int] = [:]

    private func dbg(_ verb: String, _ name: String) {
        guard Self.audioDebug else { return }
        loopCounts[name, default: 0] += (verb == "START" ? 1 : -1)
        print("[audio-debug] \(verb) \(name) — active: \(loopCounts[name] ?? 0)")
    }

    // MARK: music scheduler (data-driven 8th-note grid, 3 steps queued ahead)

    /// Build every step of a song once (64 garage steps / 32 race steps).
    private func songBuffers(for name: String) -> [AVAudioPCMBuffer]? {
        if let cached = songSteps[name] { return cached }
        guard let stepDur = songStepDur[name] else { return nil }
        let count = name == "garage" ? 64 : 32
        var out: [AVAudioPCMBuffer] = []
        out.reserveCapacity(count)
        for step in 0..<count {
            guard let buf = renderStep(name, step: step, stepDur: stepDur) else { return nil }
            out.append(buf)
        }
        songSteps[name] = out
        return out
    }

    /// One 8th-note step mixed to a buffer — note data ported from web SONGS.
    private func renderStep(_ song: String, step: Int, stepDur: Double) -> AVAudioPCMBuffer? {
        var notes: [SongNote] = []
        if song == "garage" {
            // 72bpm Am–F–C–G ×2, 8 bars of 8 steps (web SONGS.garage)
            let bars = ["Am", "F", "C", "G", "Am", "F", "C", "G"]
            let bar = Self.chords[bars[(step >> 3) % 8]]!
            let s = step & 7
            if s == 0 || s == 4 { notes.append(SongNote(freq: bar.root, dur: 0.38, wave: .triangle, vol: 0.055)) }
            if s == 6 { notes.append(SongNote(freq: bar.root * 1.5, dur: 0.2, wave: .triangle, vol: 0.04)) }
            if s == 1 || s == 3 || s == 6 { // sparse, swaying lead
                let pickIdx = ((step >> 3) + (s == 3 ? 1 : s == 6 ? 2 : 0)) % 3
                notes.append(SongNote(freq: bar.tones[pickIdx], dur: 0.32, wave: .square, vol: 0.026))
            }
        } else {
            // 128bpm Am–Am–F–G, 4 bars of 8 steps (web SONGS.race)
            let bars = ["Am", "Am", "F", "G"]
            let bar = Self.chords[bars[(step >> 3) % 4]]!
            let s = step & 7
            notes.append(SongNote(freq: bar.root / 2, dur: 0.12, wave: .square, vol: s % 4 == 0 ? 0.06 : 0.045)) // 8th pulse
            if s == 2 || s == 6 { notes.append(SongNote(freq: 0, dur: 0.03, wave: .noise, vol: 0.016)) }         // offbeat hats
            let arp = [0, 1, 2, 1][(step >> 1) % 4]
            if (s & 1) == 0 { notes.append(SongNote(freq: bar.tones[arp] * 2, dur: 0.14, wave: .saw, vol: 0.02)) }
        }
        let frames = AVAudioFrameCount(max(1, Int(stepDur * sampleRate)))
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        for n in notes {
            let count = min(Int(n.dur * sampleRate), Int(frames))
            var phase = 0.0
            for i in 0..<count {
                let t = Double(i) / sampleRate
                phase += n.freq / sampleRate
                let g = n.vol * pow(0.0001 / n.vol, t / n.dur) // same decay envelope as SFX
                data[i] += Float(g) * waveSample(n.wave, phase)
            }
        }
        return buffer
    }

    /// Start (or switch) a music loop: "garage" (menu/garage/build) or "race" (from GO).
    func musicStart(_ name: String) {
        lock.lock()
        guard musSong != name else { lock.unlock(); return }
        // stop OUTSIDE the lock: the audio worker may be inside a step-completion
        // handler waiting for it — stop() under lock is an AB-BA deadlock.
        let was = musSong
        musSong = nil
        musicGen += 1
        lock.unlock()
        if let was { dbg("STOP", "music-\(was)") } // audit: a switch is also a stop
        musicPlayer.stop()
        lock.lock()
        defer { lock.unlock() }
        guard ensureRunningLocked(), songBuffers(for: name) != nil else { return }
        musSong = name
        dbg("START", "music-\(name)")
        reseedMusicLocked()
    }

    func musicStop() {
        lock.lock()
        let was = musSong
        musSong = nil
        musicGen += 1
        lock.unlock()
        if let was { dbg("STOP", "music-\(was)") }
        musicPlayer.stop() // see musicStart: never under the lock
    }

    private func stopMusicLocked() {
        musSong = nil
        musicGen += 1
    }

    /// (Re)start the step queue at step 0 with 3 buffers in flight.
    private func reseedMusicLocked() {
        guard let name = musSong, engine.isRunning else { return }
        musicGen += 1
        musStep = 0
        musicBus.volume = musicVol
        // stop outside the lock (audio worker may be in a completion waiting for it)
        lock.unlock()
        musicPlayer.stop()
        lock.lock()
        for _ in 0..<3 { scheduleStepLocked() }
        musicPlayer.play()
    }

    private func scheduleStepLocked() {
        guard let name = musSong, let steps = songSteps[name], !steps.isEmpty else { return }
        let gen = musicGen
        let buf = steps[musStep % steps.count]
        musStep += 1
        musicPlayer.scheduleBuffer(buf, at: nil, options: []) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            if self.musicGen == gen, self.musSong != nil {
                self.scheduleStepLocked()
            }
            self.lock.unlock()
        }
    }
}
