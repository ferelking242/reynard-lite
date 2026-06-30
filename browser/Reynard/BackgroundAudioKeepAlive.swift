import AVFoundation

/// Keeps the process alive in background by activating iOS's "audio" background
/// mode with a silent, looping AVAudioPlayer.
///
/// iOS only honours the `audio` background mode (declared in Info.plist) when
/// there is an active AVAudioSession with category `.playback`. Without this,
/// the process is suspended ~30 s after the UIBackgroundTask expires, the
/// keep-alive timer stops firing, and the Gecko child process gets jetsam-killed.
///
/// Usage:
///   BackgroundAudioKeepAlive.shared.start()  // call from handleBackground()
///   BackgroundAudioKeepAlive.shared.stop()   // call from handleForeground()
final class BackgroundAudioKeepAlive {
    static let shared = BackgroundAudioKeepAlive()

    private var player: AVAudioPlayer?

    private init() {}

    func start() {
        guard player == nil else { return }

        do {
            // .playback keeps the process in the OS "audio" scheduling tier,
            // preventing suspension. .mixWithOthers avoids interrupting music
            // or podcasts the user is already playing.
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            NSLog("[Reynard] AVAudioSession setup failed: %@", error.localizedDescription)
            return
        }

        // Build a minimal valid WAV in memory (44-byte RIFF header + 1 silent
        // 16-bit PCM sample). No asset dependency, works on iOS 13+.
        let wav = Self.silentWAV()

        do {
            let p = try AVAudioPlayer(data: wav, fileTypeHint: AVFileType.wav.rawValue)
            p.numberOfLoops = -1    // loop indefinitely
            p.volume = 0            // inaudible
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            NSLog("[Reynard] AVAudioPlayer init failed: %@", error.localizedDescription)
        }
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    // MARK: - WAV builder

    /// Builds a 46-byte RIFF/WAV containing one silent mono 16-bit PCM sample
    /// at 8 kHz — the smallest valid WAV AVAudioPlayer will accept.
    private static func silentWAV() -> Data {
        var d = Data()

        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func str(_ s: String)  { d.append(contentsOf: s.utf8) }

        let dataSize: UInt32 = 2            // 1 sample × 2 bytes (16-bit)
        let chunkSize: UInt32 = 36 + dataSize

        str("RIFF"); u32(chunkSize); str("WAVE")
        str("fmt "); u32(16)                // PCM sub-chunk size
        u16(1)                              // AudioFormat = PCM
        u16(1)                              // NumChannels = mono
        u32(8_000)                          // SampleRate
        u32(8_000 * 1 * 2)                  // ByteRate
        u16(1 * 2)                          // BlockAlign
        u16(16)                             // BitsPerSample
        str("data"); u32(dataSize)
        u16(0)                              // silent sample

        return d
    }
}
